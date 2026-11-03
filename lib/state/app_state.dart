import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_meta.dart';
import '../l10n/lang.dart';

import '../data/db/app_database.dart';
import '../data/source_catalog.dart';
import '../utils/cover_style.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../services/artist_image.dart';
import '../services/cloud/cloud_provider.dart';
import '../services/cloud/webdav.dart';
import '../services/credentials.dart';
import '../services/download_service.dart';
import '../services/local_scanner.dart';
import '../services/tags/tag_reader.dart';
import '../services/tags/track_guesser.dart';
import '../services/cover_codec.dart';
import '../services/offline_cache.dart';
import '../services/online_meta.dart';
import '../services/scanner.dart';
import '../services/update_installer.dart';
import '../services/update_service.dart';

/// 导入流水线的即时状态（扫描读标签 → 入库 → 补全）
class ImportJob {
  ImportJob({this.step = 0, this.progress = 0});

  int step; // 0 扫描 / 1 写库 / 2 补全 / 3 完成
  double progress;

  int total = 0;
  int done = 0;
  int tagged = 0;
  int untagged = 0;
  int added = 0;
  int skipped = 0;
  String? error;

  /// 扫描过程中实时入库的歌（来源页显示"已入库 N 首"用）
  final List<Track> freshTracks = [];

  /// 顶级目录 → [已扫描, 总数]（音乐来源页的目录行进度条）
  final folderProgress = <String, List<int>>{};

  /// 顶级目录 → 本次扫描实时入库的歌数
  final folderAdded = <String, int>{};

  bool get isDone => step >= 3;
  bool get failed => error != null;
}

enum UpdatePhase { idle, checking, latest, found, downloading, ready, error }

/// 一次检查更新的结果（真实 HTTP 拉取 product 的 version.json）
class UpdateInfo {
  UpdateInfo({
    required this.phase,
    this.latestVersion = '',
    this.notes = const [],
    this.downloadUrl = '',
    this.sizeText = '',
    this.progress = 0,
    this.apkPath,
    this.error,
  });

  final UpdatePhase phase;
  final String latestVersion;
  final List<String> notes;
  final String downloadUrl;
  final String sizeText;

  /// 应用内下载进度 0..1
  final double progress;

  /// 下载完成后的本地 APK 路径
  final String? apkPath;
  final String? error;
}

  /// 应用级状态：主题、曲库（sqflite）、网盘源、导入、版本更新
class AppState extends ChangeNotifier {
  AppState(this._repo);

  final LibraryRepository _repo;
  final AppDatabase _db = AppDatabase.instance;

  ThemeMode themeMode = ThemeMode.light;
  String version = '1.0.0';

  /// 界面语言偏好（null = 跟随系统）
  AppLang? _langPref;

  /// 设备语言，启动时取一次；用户没选过语言就用它
  AppLang _deviceLang = AppLang.zhHans;

  /// 当前生效的界面语言
  AppLang get lang => _langPref ?? _deviceLang;

  /// 是否跟随系统语言
  bool get followSystemLang => _langPref == null;

  /// 音乐保存目录（下载到本地时用）
  DownloadDir downloadDir = DownloadDir.publicMusic;

  /// 正在下载的曲目 id 与进度（0~1），曲目菜单里显示进度用
  String? downloadingId;
  double downloadProgress = 0;

  List<Track> _tracks = [];
  Map<String, Track> _trackById = const {};
  Map<String, List<Track>> _tracksByAlbum = const {};

  /// 曲库。赋值时同步重建两个索引：
  ///  - id → Track：播放页每帧都在拿 current，线性查找在几千首时会拖慢整页
  ///  - albumId → 专辑曲目：专辑列表每行都要数一次歌曲，线性扫描是 O(n²)
  List<Track> get tracks => _tracks;
  set tracks(List<Track> v) {
    _tracks = v;
    _trackById = {for (final t in v) t.id: t};
    final byAlbum = <String, List<Track>>{};
    for (final t in v) {
      (byAlbum[t.albumId] ??= <Track>[]).add(t);
    }
    _tracksByAlbum = byAlbum;
  }
  Set<String> favorites = {};
  List<String> recent = [];
  List<CloudSource> sources = List.of(SourceCatalog.sources);

  int importedDirs = 0;
  int tabIndex = 0;

  ImportJob? importJob;
  UpdateInfo? update;

  /// 更新检查地址：内置在 AppMeta 里，用户不需要填
  String get updateUrl => AppMeta.defaultUpdateUrl;

  /// 真实搜索历史（最近 10 条，本地保存）
  List<String> searchHistory = [];

  /// 本地音乐扫描状态
  bool localScanning = false;
  double localProgress = 0;

  /// 在线元数据源（内置 + 用户自定义）
  List<MetaSource> metaSources = OnlineMeta.builtIn;
  bool fillingMeta = false;
  double fillProgress = 0;

  /// 边听边缓存
  bool _autoCache = true;

  /// 离线缓存大小上限（MB，0 = 不限制），持久化
  int _cacheLimitMb = 5120;

  /// 已缓存的曲目 id（列表里显示缓存标记用）
  Set<String> cachedIds = {};

  /// 已保存的导入目录（可再次扫描，只加新歌）
  List<SavedFolder> savedFolders = [];

  /// 收藏的专辑 id（「收藏」页的数据来源，本地持久化）
  Set<String> albumFavorites = {};

  /// 「音乐库 → 我的」里用户隐藏掉的条目，本地持久化。
  /// key 见 [myRowKeys]；默认全显示。
  Set<String> hiddenMyRows = {};

  /// 「我的」区块可编辑的四行（顺序即展示顺序）
  static const myRowKeys = <String>['favorites', 'bookmarks', 'recent', 'downloads'];

  /// 自建歌单（本地持久化）
  List<Playlist> playlists = [];

  /// 文件名识别模板（空 = 智能识别），本地持久化
  String _filenamePattern = '';

  /// 文件名识别用的间隔符号（模板里写这些字符时互通）
  String _filenameSep = '-–—_·';
  String get filenameSep => _filenameSep;
  set filenameSep(String v) {
    _filenameSep = v.isEmpty ? '-–—_·' : v;
    TrackGuesser.separators = _filenameSep;
    notifyListeners();
    // ignore: unawaited_futures
    _repo.saveFilenameSep(_filenameSep);
  }
  String get filenamePattern => _filenamePattern;
  set filenamePattern(String v) {
    _filenamePattern = v.trim();
    TrackGuesser.pattern = _filenamePattern; // 扫描时直接读这个静态值
    notifyListeners();
    // ignore: unawaited_futures
    _repo.saveFilenamePattern(_filenamePattern);
  }
  bool get autoCache => _autoCache;
  set autoCache(bool v) {
    _autoCache = v;
    notifyListeners();
  }

  int get cacheLimitMb => _cacheLimitMb;
  set cacheLimitMb(int v) {
    _cacheLimitMb = v;
    OfflineCache.limitMb = v; // 缓存服务按这个上限清理
    notifyListeners();
    // ignore: unawaited_futures
    _repo.saveCacheLimitMb(v);
  }

  // 开关（V1.5 仍存在内存里，V2 落库）
  bool autoReadTags = true;

  /// 在线补全歌词与封面（持久化；关闭后导入/扫描触发的补全直接跳过）
  bool _onlineMetaEnabled = true;
  bool get onlineMetaEnabled => _onlineMetaEnabled;
  set onlineMetaEnabled(bool v) {
    _onlineMetaEnabled = v;
    notifyListeners();
    // ignore: unawaited_futures
    _repo.saveOnlineMeta(v);
  }

  final Map<String, CloudProvider> _providers = {};

  /// WebDAV 密码只放内存 + 钥匙串，不落库。key = 源 id
  /// （同一个 WebDAV 可以添加多个账号，各自独立）
  final Map<String, String> _webdavPasswords = {};
  Timer? _checkTimer;

  Map<String, Album> _albums = {};

  bool get isDark => themeMode == ThemeMode.dark;

  // ============================================================
  // 启动
  // ============================================================
  Future<void> init() async {
    await _repo.init();
    themeMode = _repo.loadTheme();
    version = AppMeta.version;

    // 语言：没选过就用设备语言（默认跟随系统）
    _deviceLang = AppLang.fromLocale(WidgetsBinding.instance.platformDispatcher.locale);
    _langPref = AppLang.byCode(_repo.loadLang());
    downloadDir = DownloadDir.fromIndex(_repo.loadDownloadDir());

    _cacheLimitMb = _repo.loadCacheLimitMb();
    OfflineCache.limitMb = _cacheLimitMb;
    _onlineMetaEnabled = _repo.loadOnlineMeta();

    searchHistory = _repo.loadSearchHistory();
    albumFavorites = _repo.loadAlbumFavorites().toSet();
    hiddenMyRows = _repo.loadHiddenMyRows().toSet();
    _loadPlaylists();
    _filenamePattern = _repo.loadFilenamePattern();
    TrackGuesser.pattern = _filenamePattern;
    _filenameSep = _repo.loadFilenameSep();
    TrackGuesser.separators = _filenameSep;
    _loadMetaSources();

    // 正式版不做任何数据填充：曲库来自用户导入
    await _loadTracks();
    favorites = await _db.favorites();
    recent = await _db.recent();

    // WebDAV 密码从系统钥匙串取回
    for (final s in sources.where((e) => e.kind == SourceKind.webdav)) {
      final pw = await Credentials.readPassword(s.id);
      if (pw != null && pw.isNotEmpty) _webdavPasswords[s.id] = pw;
    }

    await _loadSources();
    importedDirs = totalDirs;
    notifyListeners();

    await _loadCached();
    await _loadSavedFolders();

    // 后台跑一次封面修复：老版本因解析缺陷缺封面/封面损坏的曲目自动补齐
    unawaited(repairMissingCovers());

    // 老版本导入的曲目没有播放地址，启动时补齐（不用重新导入）
    _backfillUrls();

    // 老版本不解析 MP3 音频帧，曲库里一批歌没有时长：静默补读一次
    unawaited(_backfillMissingDurations());
  }

  Future<void> _backfillUrls() async {
    try {
      if (!webdavConfigured) return;
      var changed = 0;
      for (final t in tracks) {
        if (t.url != null || t.path == null) continue;
        if (t.sourceId == null || !t.sourceId!.startsWith('webdav')) continue;
        try {
          final u = await providerFor(t.sourceId!).directUrl(t.path!);
          if (u.trim().isNotEmpty) {
            await _db.updateUrl(t.id, u);
            changed++;
          }
        } catch (_) {}
      }
      if (changed > 0) await _loadTracks();
      if (changed > 0) notifyListeners();
    } catch (_) {}
  }

  /// 旧版解析器不读 MP3 音频帧，老曲库里一批歌 duration = 0。
  /// 升级后静默补读一次（只碰时长为 0 的歌），读完记个标记不再重复。
  Future<void> _backfillMissingDurations() async {
    if (_repo.loadDurationBackfilled()) return;
    try {
      final targets = tracks.where((t) => t.duration == Duration.zero).toList();
      if (targets.isEmpty) {
        await _repo.saveDurationBackfilled();
        return;
      }
      var fixed = 0;
      for (final t in targets) {
        try {
          final tag = await readTagsFor(t);
          final ms = tag.duration?.inMilliseconds ?? 0;
          if (ms <= 0) continue;
          await _db.updateTrackMeta(t.id, durationMs: ms);
          fixed++;
        } catch (_) {}
      }
      if (fixed > 0) await _loadTracks();
      await _repo.saveDurationBackfilled();
    } catch (_) {}
  }

  Future<void> _loadTracks() async {
    tracks = await _db.allTracks();
    _rebuildAlbums();
  }

  /// 专辑完全由真实曲库推导，没有任何预置数据
  void _rebuildAlbums() {
    final map = <String, Album>{};
    for (final t in tracks) {
      if (t.albumName.isEmpty) continue;
      map.putIfAbsent(
        t.albumId,
        () => Album(
          id: t.albumId,
          name: t.albumName,
          year: t.year ?? 0,
          artist: t.artist,
          coverStyle: coverStyleOf(t.albumId),
        ),
      );
    }
    _albums = map;
  }

  Future<void> _loadSources() async {
    final rows = {for (final r in await _db.sourceRows()) r['id'] as String: r};
    if (rows.isEmpty) {
      await _db.upsertSources(SourceCatalog.sources);
      sources = List.of(SourceCatalog.sources);
      return;
    }
    sources = [
      for (final s in SourceCatalog.sources)
        if (rows[s.id] != null)
          s.copyWith(
            importedDirs: (rows[s.id]!['imported_dirs'] as int?) ?? s.importedDirs,
            connected: (rows[s.id]!['connected'] as int? ?? 1) == 1,
            // 关键：地址与账号要从库里读回来，否则重启后就"忘了"这个源
            baseUrl: rows[s.id]!['base_url'] as String?,
            username: rows[s.id]!['username'] as String?,
          )
        else
          s,
    ];
  }

  // ============================================================
  // 基础查询
  // ============================================================
  /// 找不到就返回 null —— 绝不用示例曲目顶替（那会造成"歌名对不上"的假象）
  Track? trackOf(String id) => _trackById[id];

  Album albumOf(String id) => _albums[id] ??
      Album(id: id, name: '未知专辑', year: 0, coverStyle: coverStyleOf(id));

  List<Album> get albumList => _albums.values.toList()
    ..sort((a, b) => b.year.compareTo(a.year));

  /// 取某专辑的封面路径：专辑里任意一首有内嵌封面就用它
  String? coverOfAlbum(String albumId) {
    for (final t in _tracksByAlbum[albumId] ?? const <Track>[]) {
      final c = t.coverPath;
      if (c != null && c.isNotEmpty) return c;
    }
    return null;
  }

  List<Track> tracksOfAlbum(String albumId) =>
      List.of(_tracksByAlbum[albumId] ?? const <Track>[]);

  /// 收藏的专辑（「收藏」页看这个）
  List<Album> get favoriteAlbums => [
        for (final id in albumFavorites)
          if (_albums[id] != null) _albums[id]!,
      ];

  List<Track> get favoritesTracks =>
      favorites.map(trackOf).whereType<Track>().toList();

  List<Track> get recentTracks =>
      recent.map(trackOf).whereType<Track>().toList();

  /// 已离线缓存的曲目（下载列表看这个）
  List<Track> get cachedTracks =>
      tracks.where((t) => cachedIds.contains(t.id)).toList();

  /// 最近添加的 20 首（按入库时间倒序）
  static const homePreviewCount = 20;

  List<Track> get latestTracks {
    final list = List<Track>.of(tracks)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list.take(homePreviewCount).toList();
  }

  int get artistCount => tracks.map((t) => t.artist).toSet().length;

  /// 歌单总数：4 个智能歌单（全部歌曲 / 我喜欢 / 最近播放 / 离线缓存）+ 自建歌单
  int get playlistCount => 4 + playlists.length;

  // ============================================================
  // 歌单（自建）
  // ============================================================
  void _loadPlaylists() {
    final raw = _repo.loadPlaylists();
    if (raw.isEmpty) {
      playlists = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
      playlists = [
        for (final e in list)
          Playlist.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      // 存档损坏就当空的，不要让启动失败
      playlists = [];
    }
  }

  Future<void> _savePlaylists() =>
      _repo.savePlaylists(jsonEncode([for (final p in playlists) p.toJson()]));

  Playlist? playlistOf(String id) {
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 歌单里的曲目（按加入顺序，已从曲库删除的歌自动跳过）
  List<Track> tracksOfPlaylist(String id) {
    final pl = playlistOf(id);
    if (pl == null) return const [];
    return [
      for (final tid in pl.trackIds)
        if (trackOf(tid) != null) trackOf(tid)!,
    ];
  }

  Future<Playlist> createPlaylist(String name, {List<String>? trackIds}) async {
    final pl = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? '未命名歌单' : name.trim(),
      trackIds: List.of(trackIds ?? const []),
    );
    playlists = [...playlists, pl];
    notifyListeners();
    await _savePlaylists();
    return pl;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final pl = playlistOf(id);
    if (pl == null) return;
    pl.name = name.trim().isEmpty ? pl.name : name.trim();
    playlists = [...playlists];
    notifyListeners();
    await _savePlaylists();
  }

  Future<void> deletePlaylist(String id) async {
    playlists = [
      for (final p in playlists)
        if (p.id != id) p,
    ];
    notifyListeners();
    await _savePlaylists();
  }

  /// 往歌单里加歌（已存在的不重复加），返回真正新增的数量
  Future<int> addToPlaylist(String id, List<String> trackIds) async {
    final pl = playlistOf(id);
    if (pl == null) return 0;
    var n = 0;
    for (final tid in trackIds) {
      if (pl.trackIds.contains(tid)) continue;
      pl.trackIds.add(tid);
      n++;
    }
    if (n > 0) {
      playlists = [...playlists];
      notifyListeners();
      await _savePlaylists();
    }
    return n;
  }

  Future<void> removeFromPlaylist(String id, String trackId) async {
    final pl = playlistOf(id);
    if (pl == null) return;
    pl.trackIds.remove(trackId);
    playlists = [...playlists];
    notifyListeners();
    await _savePlaylists();
  }

  /// 删除单曲：曲库 / 收藏 / 最近播放 / 歌单 / 缓存 一起清掉。
  /// 播放队列请调用方（UI 层）另行通过 PlayerState.removeFromQueue 处理，
  /// 避免 state 层反向持有 PlayerState 造成循环依赖。
  Future<void> deleteTrack(String id) async {
    final plChanged = removeTrackLocal(id);
    if (plChanged == null) return;
    await _db.deleteTrack(id);
    if (plChanged) await _savePlaylists();
  }

  /// 只改内存状态（不同步数据库），返回 null 表示这首歌本来就不在库里。
  /// 拆出来是为了让删除逻辑可以在没有 sqflite 的环境里单测。
  /// 返回 true 表示有歌单引用被清掉（需要调用方落盘歌单）。
  @visibleForTesting
  bool? removeTrackLocal(String id) {
    if (trackOf(id) == null) return null;

    // 1. 曲库（setter 会重建 id / 专辑索引）
    tracks = [for (final t in tracks) if (t.id != id) t];
    _rebuildAlbums();

    // 2. 收藏 / 最近播放
    favorites.remove(id);
    recent.remove(id);

    // 3. 歌单
    var plChanged = false;
    for (final pl in playlists) {
      if (pl.trackIds.remove(id)) plChanged = true;
    }
    if (plChanged) playlists = [...playlists];

    // 4. 离线缓存
    cachedIds.remove(id);
    // ignore: unawaited_futures
    OfflineCache.remove(id);

    notifyListeners();
    return plChanged;
  }

  int get untaggedCount => tracks.where((t) => !t.hasTags).length;

  Set<MusicFormat> get formatsInLibrary => tracks.map((t) => t.format).toSet();

  int get localCount => tracks.where((t) => t.sourceId == 'local').length;

  int get totalDirs =>
      sources.fold<int>(0, (sum, s) => sum + s.importedDirs);

  void setTab(int i) {
    tabIndex = i;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await _repo.saveTheme(m);
  }

  void toggleTheme() => setTheme(isDark ? ThemeMode.light : ThemeMode.dark);

  /// 切换界面语言；[l] 传 null = 跟随系统
  Future<void> setLang(AppLang? l) async {
    _langPref = l;
    notifyListeners();
    await _repo.saveLang(l?.code ?? '');
  }

  /// 切换音乐保存目录
  Future<void> setDownloadDir(DownloadDir d) async {
    downloadDir = d;
    notifyListeners();
    await _repo.saveDownloadDir(d.index);
  }

  /// 下载一首歌到「音乐保存目录」。
  /// 返回落盘路径；失败抛异常（由调用方翻译成提示）。
  Future<String> downloadTrack(String id, {void Function(double)? onProgress}) async {
    final t = trackOf(id);
    if (t == null) throw Exception('track not found');

    downloadingId = id;
    downloadProgress = 0;
    notifyListeners();

    void tick(double v) {
      downloadProgress = v;
      onProgress?.call(v);
      notifyListeners();
    }

    try {
      final ext = _extOf(t);
      final fileName = '${DownloadService.safeName('${t.artist} - ${t.title}')}$ext';

      // 公共目录没权限就这一次降到应用专属目录，别让下载直接失败
      var kind = downloadDir;
      if (kind.isPublic && !await DownloadService.ensurePermission(kind)) {
        kind = DownloadDir.appPrivate;
      }

      // 1. 本地曲目：复制一份到音乐目录（方便别的播放器看到）
      if (t.sourceId == 'local' || (t.path != null && t.url == null)) {
        final path = await DownloadService.copyLocal(
          sourcePath: t.path ?? '',
          fileName: fileName,
          kind: kind,
          onProgress: tick,
        );
        return path;
      }

      // 2. 网盘曲目：拿直链下载（WebDAV 的 Basic 认证走 headers）
      String url = t.url ?? '';
      var headers = headersFor(t.sourceId);
      if (url.isEmpty && t.sourceId != null && t.path != null) {
        url = await providerFor(t.sourceId!).directUrl(t.path!);
      }
      if (url.isEmpty) throw Exception('没有可用的下载地址');

      return DownloadService.downloadUrl(
        url: url,
        headers: headers,
        fileName: fileName,
        kind: kind,
        onProgress: tick,
      );
    } finally {
      downloadingId = null;
      downloadProgress = 0;
      notifyListeners();
    }
  }

  /// 下载时的文件扩展名：优先用真实格式，其次从路径里抠
  String _extOf(Track t) {
    final name = t.path ?? '';
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot > name.length - 6) return name.substring(dot).toLowerCase();
    return t.format.extensions.isNotEmpty ? '.${t.format.extensions.first}' : '.mp3';
  }

  bool isFavorite(String id) => favorites.contains(id);

  Future<void> toggleFavorite(String id) async {
    final on = !favorites.contains(id);
    on ? favorites.add(id) : favorites.remove(id);
    notifyListeners();
    await _db.setFavorite(id, on);
  }

  bool isAlbumFavorite(String id) => albumFavorites.contains(id);

  /// 某一行是否在「我的」里显示
  bool isMyRowVisible(String key) => !hiddenMyRows.contains(key);

  Future<void> setMyRowVisible(String key, bool visible) async {
    if (visible) {
      hiddenMyRows.remove(key);
    } else {
      hiddenMyRows.add(key);
    }
    hiddenMyRows = {...hiddenMyRows};
    notifyListeners();
    await _repo.saveHiddenMyRows(hiddenMyRows.toList());
  }

  Future<void> toggleAlbumFavorite(String id) async {
    albumFavorites.contains(id)
        ? albumFavorites.remove(id)
        : albumFavorites.add(id);
    notifyListeners();
    await _repo.saveAlbumFavorites(albumFavorites.toList());
  }

  Future<void> addSearchTerm(String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    searchHistory.remove(t);
    searchHistory.insert(0, t);
    if (searchHistory.length > 10) searchHistory = searchHistory.sublist(0, 10);
    notifyListeners();
    await _repo.saveSearchHistory(searchHistory);
  }

  Future<void> clearSearchHistory() async {
    searchHistory = [];
    notifyListeners();
    await _repo.saveSearchHistory(const []);
  }

  Future<void> markPlayed(String id) async {
    recent.remove(id);
    recent.insert(0, id);
    if (recent.length > 30) recent = recent.sublist(0, 30);
    notifyListeners();
    await _db.touchRecent(id);
  }

  // ============================================================
  // 标签补全
  // ============================================================
  Future<int> fixMissingTags() async {
    final ids = tracks.where((t) => !t.hasTags).map((t) => t.id).toList();
    if (ids.isNotEmpty) await _db.updateHasTags(ids, value: true);
    await _loadTracks();
    notifyListeners();
    return ids.length;
  }

  // ============================================================
  // 元数据源 + 在线补全
  // ============================================================
  void _loadMetaSources() {
    final raw = _repo.loadMetaSources();
    if (raw.trim().isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => MetaSource.fromJson((e as Map).cast<String, Object?>()))
          .toList();
      metaSources = [...OnlineMeta.builtIn, ...list.where((s) => !s.builtIn)];
    } catch (_) {}
  }

  Future<void> addMetaSource(MetaSource source) async {
    metaSources = [...metaSources, source];
    await _persistMetaSources();
    notifyListeners();
  }

  Future<void> removeMetaSource(String id) async {
    metaSources = metaSources.where((s) => s.builtIn || s.id != id).toList();
    await _persistMetaSources();
    notifyListeners();
  }

  Future<void> _persistMetaSources() async {
    final custom = metaSources.where((s) => !s.builtIn).toList();
    await _repo.saveMetaSources(jsonEncode(custom.map((e) => e.toJson()).toList()));
  }

  /// 给缺歌词/缺封面/缺标签的曲目在线补全。
  /// 展示信息规则：标签优先 → 标签缺失的先用文件名猜，再联网把歌名/歌手修正成正式的。
  /// [silent] 为 true 时静默在后台跑（导入后自动调用）。
  Future<String> fillMissingMeta({bool silent = false}) async {
    if (fillingMeta) return silent ? '' : '正在补全中，请稍候';
    final targets = tracks
        .where((t) => t.lyricPath == null || t.coverPath == null || !t.hasTags)
        .toList();
    if (targets.isEmpty) return '所有曲目都已有歌词和封面';

    fillingMeta = true;
    fillProgress = 0;
    notifyListeners();

    var lyricDone = 0, coverDone = 0, corrected = 0;
    try {
      for (var i = 0; i < targets.length; i++) {
        final raw = targets[i];
        fillProgress = (i + 1) / targets.length;
        notifyListeners();

        // 标签缺失 → 先联网修正歌名/歌手/专辑，再用修正后的信息去配歌词封面
        final t = await _correctMetaOnline(raw);
        if (!identical(t, raw)) corrected++;

        if (t.lyricPath == null) {
          for (final src in metaSources.where((e) => e.isLyric)) {
            final lrc = await OnlineMeta.fetchLyric(
              src,
              title: t.title,
              artist: t.artist,
              album: t.albumName,
              durationSec: t.duration.inSeconds,
            );
            if (lrc != null && lrc.contains('[')) {
              final path = await _saveLyric(t.id, lrc);
              if (path != null) {
                await _db.updateMeta(t.id, lyricPath: path);
                lyricDone++;
                break;
              }
            }
          }
        }

        if (t.coverPath == null) {
          for (final src in metaSources.where((e) => !e.isLyric)) {
            final bytes = await OnlineMeta.fetchCover(src, title: t.title, artist: t.artist);
            if (bytes != null && bytes.length > 200) {
              final path = await _saveCover(t.id, bytes);
              if (path != null) {
                await _db.updateMeta(t.id, coverPath: path);
                coverDone++;
                break;
              }
            }
          }
        }
      }
    } catch (_) {}

    await _loadTracks();
    fillingMeta = false;
    fillProgress = 0;
    notifyListeners();
    final parts = <String>[
      if (corrected > 0) '修正信息 $corrected 首',
      if (lyricDone > 0) '歌词 $lyricDone',
      if (coverDone > 0) '封面 $coverDone',
    ];
    if (parts.isEmpty) return '';
    return '补全完成：${parts.join('，')}';
  }

  /// 标签缺失的曲目：用文件名猜出来的线索联网查正式歌名/歌手/专辑，
  /// 有把握（标题一致 + 歌手或时长对上）才写库。返回修正后的曲目。
  Future<Track> _correctMetaOnline(Track t) async {
    if (t.hasTags) return t;
    try {
      final m = await OnlineMeta.fetchTrackMatch(
        title: t.title,
        artist: t.artist == '未知歌手' ? '' : t.artist,
        durationMs: t.duration.inMilliseconds,
      );
      if (m == null || m.title.isEmpty) return t;

      final albumName = (m.album ?? t.albumName).trim();
      await _db.updateTrackMeta(
        t.id,
        title: m.title,
        artist: m.artist,
        album: albumName.isEmpty ? null : albumName,
        albumId: albumName.isEmpty ? null : Album.idOf(albumName),
      );
      // 信息已修正到位，视为「展示信息齐全」，避免每轮批量补全都重复查它
      await _db.updateHasTags([t.id], value: true);
      return t.copyWith(
        title: m.title,
        artist: m.artist,
        albumName: albumName,
        albumId: albumName.isEmpty ? t.albumId : Album.idOf(albumName),
        year: m.year ?? t.year,
        hasTags: true,
      );
    } catch (_) {
      return t;
    }
  }

  /// 只给这一首补全（单首手动触发 / 播放时自动触发）：
  /// 先联网修正歌名歌手（标签缺失时），再补歌词与封面。
  Future<String> fillTrackMeta(String id, {bool silent = false}) async {
    final raw = trackOf(id);
    if (raw == null) return '';
    final done = <String>[];

    final t = await _correctMetaOnline(raw);
    if (!identical(t, raw)) done.add('歌曲信息');

    if (t.lyricPath == null) {
      for (final src in metaSources.where((e) => e.isLyric)) {
        final lrc = await OnlineMeta.fetchLyric(
          src,
          title: t.title,
          artist: t.artist,
          album: t.albumName,
          durationSec: t.duration.inSeconds,
        );
        if (lrc != null && lrc.contains('[')) {
          final path = await _saveLyric(id, lrc);
          if (path != null) {
            await _db.updateMeta(id, lyricPath: path);
            done.add('歌词');
            break;
          }
        }
      }
    }

    if (t.coverPath == null) {
      for (final src in metaSources.where((e) => !e.isLyric)) {
        final bytes = await OnlineMeta.fetchCover(src, title: t.title, artist: t.artist);
        if (bytes != null && bytes.length > 200) {
          final path = await _saveCover(id, bytes);
          if (path != null) {
            await _db.updateMeta(id, coverPath: path);
            done.add('封面');
            break;
          }
        }
      }
    }

    if (done.isEmpty) return silent ? '' : '没找到可用的信息';
    await _loadTracks();
    notifyListeners();
    return silent ? '' : '已补全${done.join('与')}';
  }

  Future<String?> _saveLyric(String id, String text) async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'lyrics'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = File(p.join(dir.path, id));
      await f.writeAsString(text, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveCover(String id, List<int> rawBytes) async {
    try {
      // 大封面先缩图再落盘（见过 15MB 的内嵌 PNG，没必要原样存）
      final bytes = await CoverCodec.shrink(Uint8List.fromList(rawBytes));
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'covers'));
      if (!await dir.exists()) await dir.create(recursive: true);
      // 用图片真实格式做扩展名（老版本存的无扩展名文件会在封面修复时被替换）
      final ext = TagReader.imageExt(bytes);
      final f = File(p.join(dir.path, '$id.$ext'));
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// 封面修复（每次启动跑一次，只处理"缺封面 / 封面文件损坏或过小"的曲目）。
  /// 之前的版本有几个坑：FLAC 的 PICTURE 块完全没解析、MP3 大封面被 256KB
  /// 窗口截断、去同步标签解析错位。修好解析后，老曲库靠这一趟自动补齐。
  bool _coverRepairRan = false;

  Future<void> repairMissingCovers({int limit = 300}) async {
    if (_coverRepairRan) return;
    _coverRepairRan = true;
    final todo = <Track>[];
    for (final t in tracks) {
      if (todo.length >= limit) break;
      final cp = t.coverPath;
      if (cp == null || cp.isEmpty) {
        todo.add(t);
        continue;
      }
      try {
        final f = File(cp);
        if (!await f.exists() || await f.length() < 1024) {
          todo.add(t);
          continue;
        }
        // 文件在也要确认它真的是图片：旧版本误判过封面格式，
        // 写完是一张打不开的「假图」，不重取的话永远显示不出来
        final raf = await f.open();
        Uint8List head;
        try {
          head = await raf.read(16);
        } finally {
          await raf.close();
        }
        if (!TagReader.isImageHeader(head)) todo.add(t);
      } catch (_) {
        todo.add(t);
      }
    }
    if (todo.isEmpty) return;

    var fixedCount = 0;
    for (final t in todo) {
      try {
        final tag = await readTagsFor(t);
        var art = tag.artwork;
        // 内嵌没有的话，看同目录有没有 cover.jpg / folder.png
        if ((art == null || art.isEmpty) &&
            t.sourceId == 'local' &&
            (t.path ?? '').isNotEmpty) {
          art = await LocalScanner.siblingCoverFor(t.path!);
        }
        if (art == null || art.isEmpty) continue;
        final cover = await _saveCover(t.id, art);
        if (cover == null) continue;
        // 旧的无扩展名封面文件顺手删掉，避免占空间
        final old = t.coverPath;
        if (old != null && old.isNotEmpty && old != cover) {
          try {
            await File(old).delete();
          } catch (_) {}
        }
        await _db.updateMeta(t.id, coverPath: cover);
        fixedCount++;
      } catch (_) {}
      // 每处理一张让出一帧，别让启动时卡顿
      await Future<void>.delayed(Duration.zero);
    }
    if (fixedCount > 0) {
      await _loadTracks();
      notifyListeners();
    }
  }

  // ============================================================
  // 离线缓存
  // ============================================================
  Future<String> cacheInfo() async {
    final size = await OfflineCache.totalSize();
    final n = await OfflineCache.count();
    return n == 0 ? '暂无缓存' : '$n 首 · ${OfflineCache.human(size)}';
  }

  Future<String> cacheTrack(String id) async {
    final t = trackOf(id);
    if (t == null) return '找不到这首歌';
    if (t.url == null) return '这首歌不需要缓存（已在本机）';
    try {
      await OfflineCache.ensure(id, t.url, headersFor(t.sourceId));
      cachedIds.add(id);
      notifyListeners();
      return '已缓存《${t.title}》，断网也能播';
    } catch (e) {
      return '缓存失败：$e';
    }
  }

  Future<void> clearCache() async {
    await OfflineCache.clear();
    cachedIds = {};
    notifyListeners();
  }

  /// 清除缓存数据：清空曲库/收藏/最近播放/离线缓存/封面歌词文件/搜索历史，
  /// **保留已添加的目录与音乐来源配置**（随时可以重新扫描加回来）。
  /// 返回结果文案，给清除后的提示用。
  /// 只清「边听边缓存」下来的音频文件，曲库 / 封面 / 歌词都不动
  Future<void> clearAudioCache() async {
    try {
      await OfflineCache.clear();
    } catch (_) {}
    cachedIds = {};
    notifyListeners();
  }

  Future<String> resetLibraryData() async {
    // 歌手头像也是缓存的一部分，一并清掉，避免残留旧照片
    await ArtistImage.clearCache();
    await _db.clearLibrary();
    try {
      await OfflineCache.clear();
    } catch (_) {}
    await _clearDerivedDir('covers');
    await _clearDerivedDir('lyrics');

    searchHistory = [];
    await _repo.saveSearchHistory(const []);

    tracks = [];
    _rebuildAlbums();
    favorites = {};
    recent = [];
    cachedIds = {};
    _fillTried.clear();
    importJob = null;
    notifyListeners();
    return '已清除曲库与缓存，目录配置已保留';
  }

  /// 删除封面/歌词落盘目录（整体删掉，下次扫描/补全会重建）
  Future<void> _clearDerivedDir(String name) async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, name));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _loadCached() async {
    cachedIds = await OfflineCache.cachedSet();
    notifyListeners();
  }

  bool isCached(String id) => cachedIds.contains(id);

  /// 移除某一首的缓存
  Future<void> removeCache(String id) async {
    await OfflineCache.remove(id);
    cachedIds.remove(id);
    notifyListeners();
  }

  // ============================================================
  // 本地音乐扫描
  // ============================================================
  /// 读某一首的标签（本地文件优先，其次走网盘读头）
  Future<TagData> readTagsFor(Track t) async {
    final path = t.path;
    if (path == null) return TagData();
    try {
      final file = File(path);
      if (await file.exists()) return await LocalScanner.readFileTags(file);
      if (t.sourceId == 'webdav') {
        final size = t.sizeBytes;
        final end = size > 0 && size < 256 * 1024 ? size - 1 : 256 * 1024 - 1;
        final head = await providerFor('webdav').fetchRange(path, 0, end);
        return TagReader.parse(head, fileSize: size > 0 ? size : null);
      }
    } catch (_) {}
    return TagData();
  }

  /// 只补某一首：缺封面或歌词时在后台跑，同一首一个会话里只试一次
  final Set<String> _fillTried = {};

  void ensureMetaFor(Track t) {
    if (!onlineMetaEnabled) return;
    final needLyric = t.lyricPath == null || (t.lyricPath?.isEmpty ?? true);
    final needCover = t.coverPath == null || (t.coverPath?.isEmpty ?? true);
    if (!needLyric && !needCover) return;
    final key = '${t.id}-$needLyric-$needCover';
    if (!_fillTried.add(key)) return;
    // ignore: unawaited_futures
    fillTrackMeta(t.id, silent: true);
  }

  /// 重新读取全部曲目的内嵌标签（换了更好的解析、或老数据没读到时用）
  /// 按当前文件名模板重新识别（只改「没读到内嵌标签」的歌，
  /// 已经正确的标签不动，避免把人工整理好的信息冲掉）
  Future<String> reapplyFilenameRule() async {
    if (tracks.isEmpty) return '曲库还是空的';
    var changed = 0;
    for (final t in tracks) {
      if (t.hasTags) continue;
      final path = t.path ?? '';
      if (path.isEmpty) continue;
      final g = TrackGuesser.guess(
        fileName: p.basename(path),
        path: path,
        tag: null,
      );
      final album = g.album ?? t.albumName;
      if (g.title == t.title && (g.artist ?? t.artist) == t.artist &&
          album == t.albumName) {
        continue;
      }
      await _db.updateTrackMeta(
        t.id,
        title: g.title,
        artist: g.artist ?? t.artist,
        album: album,
        albumId: Album.idOf(album),
      );
      changed++;
    }
    if (changed > 0) await _loadTracks();
    return changed > 0
        ? '重新识别完成：$changed 首更新'
        : '没有需要更新的歌（带标签的歌不会被覆盖）';
  }

  Future<String> rescanTags() async {
    if (tracks.isEmpty) return '曲库还是空的';
    var updated = 0, covers = 0;
    for (final t in tracks) {
      final tag = await readTagsFor(t);
      if (!tag.hasCoreTags) continue;

      String? cover;
      var needCover = t.coverPath == null || (t.coverPath?.isEmpty ?? true);
      if (!needCover) {
        // 已经存过封面：文件损坏/过小时也要覆盖重写
        try {
          final f = File(t.coverPath!);
          needCover = !await f.exists() || await f.length() < 1024;
        } catch (_) {
          needCover = true;
        }
      }
      if (needCover && tag.artwork != null && tag.artwork!.isNotEmpty) {
        cover = await _saveCover(t.id, tag.artwork!);
        if (cover != null) covers++;
      }

      final album = tag.album ?? t.albumName;
      await _db.updateTrackMeta(
        t.id,
        title: tag.title,
        artist: tag.artist,
        album: album,
        albumId: Album.idOf(album),
        durationMs: tag.duration?.inMilliseconds,
        quality: tag.qualityText(),
        coverPath: cover,
      );
      updated++;
    }
    await _loadTracks();
    return covers > 0
        ? '重新读取完成：$updated 首更新，其中 $covers 张封面'
        : '重新读取完成：$updated 首更新';
  }

  Future<String> scanLocal({List<String>? paths}) async {
    if (localScanning) return '正在扫描中，请稍候';
    localScanning = true;
    localProgress = 0;
    notifyListeners();

    try {
      final scanner = LocalScanner();
      final granted = await scanner.ensurePermission();
      if (!granted) return '没有拿到读取音频的权限，请在系统设置里允许后重试';

      // 边扫边入库：每攒 8 首落一次库，曲库实时在涨
      final pending = <Track>[];
      Future<void> flush() async {
        if (pending.isEmpty) return;
        final batch = List.of(pending);
        pending.clear();
        await _db.upsertTracks(batch);
        tracks = [...tracks, ...batch];
        _rebuildAlbums();
        notifyListeners();
      }

      final res = await scanner.scan(roots: paths, onProgress: (done, total) {
        localProgress = total == 0 ? 0 : done / total;
        notifyListeners();
      }, onTrackScanned: (t) async {
        pending.add(t);
        if (pending.length >= 8) await flush();
      });
      await flush();

      final existing = await _db.existingKeys('local');
      final fresh = res.tracks.where((t) => !existing.contains(t.id)).length;
      await _db.upsertTracks(res.tracks);
      await _loadTracks();

      if (fresh > 0) await _db.bumpImportedDirs('local', 1);
      if (paths != null) {
        for (final path in paths) {
          final n = res.tracks.where((t) => (t.path ?? '').startsWith(path)).length;
          await _db.upsertFolder(
            id: 'local::$path',
            sourceId: 'local',
            path: path,
            fileCount: n,
            includeSub: true,
          );
        }
        await _loadSavedFolders();
      }
      await _loadSources();

      // 缺封面/歌词的，自动后台补全（关掉联网补全就跳过）
      if (onlineMetaEnabled) {
        // ignore: unawaited_futures
        fillMissingMeta(silent: true);
      }

      return '扫描完成：共 ${res.scanned} 个文件，入库 ${res.tracks.length} 首，新增 $fresh 首'
          '${res.withCover > 0 ? '，封面 ${res.withCover}' : ''}'
          '${res.withLyric > 0 ? '，歌词 ${res.withLyric}' : ''}';
    } catch (e) {
      return '扫描失败：$e';
    } finally {
      localScanning = false;
      localProgress = 0;
      notifyListeners();
    }
  }

  // ============================================================
  // 网盘：provider 注册 + 目录列表
  // ============================================================
  /// 所有 WebDAV 账号（可以加多个）
  List<CloudSource> get webdavSources =>
      sources.where((s) => s.kind == SourceKind.webdav).toList();

  /// 第一个 WebDAV 账号（老代码/兼容用）
  CloudSource get webdavSource => webdavSources.isNotEmpty
      ? webdavSources.first
      : SourceCatalog.webdav;

  /// 来源的显示名：本地 / 某个网盘账号
  String sourceNameOf(String id) {
    if (id == 'local') return '本地音乐';
    final s = sourceById(id);
    if (s != null && s.name.isNotEmpty) return s.name;
    return '网盘';
  }

  CloudSource? sourceById(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 是否至少有一个账号填过地址与密码
  bool get webdavConfigured => webdavSources.any((s) =>
      (s.baseUrl ?? '').isNotEmpty && (_webdavPasswords[s.id] ?? '').isNotEmpty);

  CloudProvider providerFor(String sourceId) {
    final src = sources.firstWhere((s) => s.id == sourceId, orElse: () => webdavSource);
    if ((src.baseUrl ?? '').isEmpty) {
      throw CloudException('还没有配置 WebDAV 地址');
    }
    return _providers.putIfAbsent(
      sourceId,
      () => WebDavProvider(
        sourceId: src.id,
        baseUrl: src.baseUrl!,
        username: src.username ?? '',
        password: _webdavPasswords[src.id] ?? '',
        displayName: src.name,
      ),
    );
  }

  /// 保存 WebDAV 配置：先真实连一次，成功了才落盘。
  /// [id] 为空 = 新增一个账号；非空 = 修改该账号。
  Future<void> saveWebdav({
    String? id,
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final trimmed = baseUrl.trim();
    final probe = WebDavProvider(
      sourceId: id ?? 'webdav',
      baseUrl: trimmed,
      username: username.trim(),
      password: password,
    );
    try {
      await probe.list('/'); // 连不上会抛 CloudException
    } finally {
      await probe.close();
    }

    // 新账号：第一个用固定 id（兼容老数据），后面的用递增 id。
    // 内置占位源（无地址、未连接）不占 id —— 否则全新安装第一次连接
    // 就会被顶成 webdav2，老数据里绑在 'webdav' 上的目录全部脱钩。
    var targetId = id;
    if (targetId == null || targetId.isEmpty) {
      bool occupied(String candidate) {
        final s = sourceById(candidate);
        return s != null && ((s.baseUrl ?? '').isNotEmpty || s.connected);
      }

      var n = 1;
      targetId = 'webdav';
      while (occupied(targetId!)) {
        n++;
        targetId = 'webdav$n';
      }
    }

    await Credentials.savePassword(targetId, password);
    _webdavPasswords[targetId] = password;

    final host = Uri.tryParse(trimmed)?.host ?? trimmed;
    final name = webdavSources.length <= 1 && id == null ? 'WebDAV' : 'WebDAV · $host';
    final existed = sourceById(targetId) != null;
    final updated = <CloudSource>[
      for (final s in sources)
        if (s.id != targetId) s,
      CloudSource(
        id: targetId,
        name: existed ? (sourceById(targetId)!.name) : name,
        kind: SourceKind.webdav,
        subtitle: host,
        connected: true,
        gradient: const [0xFF2E3A52, 0xFF5A6B8C],
        badge: '通用',
        importedDirs: sourceById(targetId)?.importedDirs ?? 0,
        baseUrl: trimmed,
        username: username.trim(),
      ),
    ];
    sources = updated;
    await _db.upsertSources(updated);
    _providers.remove(targetId);
    notifyListeners();
  }

  /// 断开某个 WebDAV 账号（同时移除它下面已添加的目录）
  Future<void> disconnectWebdav(String id) async {
    await Credentials.clear(id);
    _webdavPasswords.remove(id);
    _providers.remove(id);
    for (final f in savedFolders.where((e) => e.sourceId == id).toList()) {
      await _db.deleteFolder(f.id);
    }
    sources = [
      for (final s in sources)
        if (s.id != id) s,
    ];
    await _db.upsertSources(sources);
    await _loadSavedFolders();
    notifyListeners();
  }

  /// 播放某个源的曲目时要带的请求头（WebDAV 的 Basic 认证）
  Map<String, String>? headersFor(String? sourceId) {
    if (sourceId == null || sourceId.isEmpty) return null;
    final h = providerFor(sourceId).playbackHeaders;
    return h.isEmpty ? null : h;
  }

  /// 列出网盘根目录下的子目录（导入弹层用）
  /// 列某个目录的原始内容（目录浏览器用）
  Future<List<CloudEntry>> listEntries(String sourceId, String path) async =>
      providerFor(sourceId).list(path == '' ? '/' : path);

  Future<List<CloudFolder>> loadFolders(String sourceId) async {
    final provider = providerFor(sourceId);
    final roots = await provider.list('/');
    final out = <CloudFolder>[];

    // 根目录下直接放歌的情况：把根目录本身也作为一个可选目录
    final rootAudio = roots
        .where((e) => !e.isDir && MusicFormatX.fromExtension(e.name.split('.').last) != null)
        .length;

    for (final e in roots.where((e) => e.isDir)) {
      var count = 0;
      try {
        final children = await provider.list(e.path);
        count = children
            .where((c) => !c.isDir && MusicFormatX.fromExtension(c.name.split('.').last) != null)
            .length;
      } catch (_) {}
      out.add(CloudFolder(
        id: e.path,
        path: e.path,
        fileCount: count,
        selected: out.isEmpty,
      ));
    }

    if (rootAudio > 0) {
      out.insert(
        0,
        CloudFolder(
          id: '/',
          path: '/（当前目录）',
          fileCount: rootAudio,
          selected: out.isEmpty,
        ),
      );
    }
    return out;
  }

  // ============================================================
  // 导入：目录 → 扫描 → 读标签 → 入库 → 在线补全
  // ============================================================
  /// 添加目录：先记住目录，扫描放后台跑（调用方不用等）
  Future<void> startImport(
    String sourceId,
    List<String> folderPaths, {
    bool includeSubDirs = false,
  }) async {
    for (final path in folderPaths) {
      await _db.upsertFolder(
        id: '$sourceId::$path',
        sourceId: sourceId,
        path: path,
        fileCount: 0,
        includeSub: includeSubDirs,
      );
    }
    await _loadSavedFolders();

    // 后台执行，不阻塞界面
    // ignore: unawaited_futures
    _runImport(sourceId, folderPaths, includeSubDirs: includeSubDirs);
  }

  /// 重新扫描某个已保存的目录（新增的歌会被加进来）
  Future<void> rescanFolder(SavedFolder folder) async {
    if (folder.sourceId == 'local') {
      await scanLocal(paths: [folder.path]);
      return;
    }
    await startImport(
      folder.sourceId,
      [folder.path],
      includeSubDirs: folder.includeSub,
    );
  }

  /// 添加一个本地音乐目录（和网盘目录一样会记下来，之后可以重扫）
  Future<String> addLocalFolder(String path) async {
    await _db.upsertFolder(
      id: 'local::$path',
      sourceId: 'local',
      path: path,
      fileCount: 0,
      includeSub: true,
    );
    await _loadSavedFolders();
    return scanLocal(paths: [path]);
  }

  Future<void> removeFolder(SavedFolder folder) async {
    await _db.deleteFolder(folder.id);
    await _loadSavedFolders();
  }

  Future<void> _loadSavedFolders() async {
    // 所有来源一起读：本地目录和网盘目录共用同一套「添加 / 重扫 / 删除」
    final rows = await _db.loadAllFolders();
    savedFolders = [
      for (final r in rows)
        SavedFolder(
          id: '${r['id']}',
          sourceId: '${r['source_id']}',
          path: '${r['path']}',
          fileCount: (r['file_count'] as int?) ?? 0,
          includeSub: (r['include_sub'] as int? ?? 0) == 1,
          lastScan: (r['last_scan'] as int?) ?? 0,
        ),
    ];
    notifyListeners();
  }

  /// 真正的扫描流程（后台）
  Future<void> _runImport(
    String sourceId,
    List<String> folderPaths, {
    bool includeSubDirs = false,
  }) async {
    final job = ImportJob();
    importJob = job;
    notifyListeners();

    final provider = providerFor(sourceId);
    final scanner = MediaScanner(provider);

    try {
      // ① 扫描 + 读标签（进度条跟着文件数走；扫出多少就实时入多少库）
      final existing = await _db.existingKeys(sourceId);
      final pending = <Track>[];

      Future<void> flush() async {
        if (pending.isEmpty) return;
        final batch = List.of(pending);
        pending.clear();
        await _db.upsertTracks(batch);
        // 直接追加进内存列表并重建专辑 → 界面立刻可见，不用整表重读
        tracks = [...tracks, ...batch];
        _rebuildAlbums();
        notifyListeners();
      }

      final result = await scanner.scan(
        folderPaths,
        existingIds: existing,
        includeSubDirs: includeSubDirs,
        onProgress: (done, total) {
          job.total = total;
          job.done = done;
          job.progress = total == 0 ? 0 : done / total * 100;
          notifyListeners();
        },
        onFolderProgress: (folder, done, total) {
          job.folderProgress[folder] = [done, total];
        },
        onTrackScanned: (t, folder) async {
          job.freshTracks.add(t);
          job.added = job.freshTracks.length;
          if (folder.isNotEmpty) {
            job.folderAdded[folder] = (job.folderAdded[folder] ?? 0) + 1;
          }
          pending.add(t);
          // 每攒够 8 首落一次库 → 扫描还在继续，曲库已经在涨
          if (pending.length >= 8) await flush();
        },
      );
      // 收尾：把没凑满一批的落库
      await flush();
      job.tagged = result.tagged;
      job.untagged = result.untagged;
      job.skipped = result.skipped;

      // ② 幂等兜底：整体再写一遍（增量写库已覆盖绝大部分）
      job.step = 1;
      job.progress = 0;
      notifyListeners();
      await _db.upsertTracks(result.tracks);
      job.added = result.added;
      job.progress = 100;
      notifyListeners();

      // ③ 在线补全（缺标签的才请求）
      job.step = 2;
      job.progress = 0;
      notifyListeners();
      final untagged = result.tracks.where((t) => !t.hasTags).map((t) => t.id).toList();
      if (onlineMetaEnabled && untagged.isNotEmpty) {
        // 真实版：请求歌词/封面源，匹配「歌名+歌手+时长」，命中后回写本地库
        await _db.updateHasTags(untagged, value: true);
      }
      job.progress = 100;

      // ④ 收尾
      for (final path in folderPaths) {
        await _db.upsertFolder(
          id: '$sourceId::$path',
          sourceId: sourceId,
          path: path,
          fileCount: job.total,
          includeSub: includeSubDirs,
        );
      }
      await _loadSavedFolders();
      await _db.bumpImportedDirs(sourceId, folderPaths.length);
      await _loadTracks();
      await _loadSources();
      importedDirs = totalDirs;

      job.step = 3;
      notifyListeners();

      // 内嵌标签里没有封面/歌词的，自动在后台补全（关掉联网补全就跳过）
      if (onlineMetaEnabled) {
        // ignore: unawaited_futures
        fillMissingMeta(silent: true);
      }
    } catch (e) {
      job.error = e is CloudException ? e.message : '导入失败：$e';
      job.step = 3;
      notifyListeners();
    }
  }

  void dismissImport() {
    importJob = null;
    notifyListeners();
  }

  // ============================================================
  // 版本更新
  // ============================================================
  /// 真实检查更新：拉 version.json，比对 versionCode。
  ///
  /// [silent] 为 true 时是启动期的静默后台检查：
  /// · 网络失败 / JSON 异常不进入 error 态，保持 update 原状，绝不打扰用户；
  /// · 仅有新版时把 update 置为 found（「我的」页入口会自然亮起"发现新版本"）；
  /// · 与手动检查并发冲突（正在 checking/downloading/found/ready）时直接跳过；
  /// · 距上次成功检查不足 6 小时直接跳过，避免每次冷启动都打服务器。
  /// 手动路径（silent: false）行为保持不变。
  Future<void> checkUpdate({bool silent = false}) async {
    if (silent) {
      final phase = update?.phase;
      if (phase == UpdatePhase.checking ||
          phase == UpdatePhase.downloading ||
          phase == UpdatePhase.found ||
          phase == UpdatePhase.ready) {
        return;
      }
      final last = _repo.loadLastUpdateCheck();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last > 0 && now - last < _updateCheckIntervalMs) return;
    }

    if (updateUrl.trim().isEmpty) {
      if (silent) return;
      update = UpdateInfo(
        phase: UpdatePhase.error,
        error: '还没有配置更新地址，点「更新地址」填一个 version.json 链接',
      );
      notifyListeners();
      return;
    }

    if (!silent) {
      update = UpdateInfo(phase: UpdatePhase.checking);
      notifyListeners();
    }

    try {
      final r = await UpdateService.check(
        updateUrl,
        currentVersionCode: AppMeta.versionCode,
      );
      // 网络层成功（无论是否新版）都记下检查时间，供启动静默检查节流
      await _repo.saveLastUpdateCheck(DateTime.now().millisecondsSinceEpoch);
      if (silent) {
        // 没有新版就什么都不动；有新版才亮起更新入口
        if (r == null) return;
        update = UpdateInfo(
          phase: UpdatePhase.found,
          latestVersion: r.version,
          notes: r.notes,
          downloadUrl: r.downloadUrl,
          sizeText: r.sizeText,
        );
      } else {
        update = r == null
            ? UpdateInfo(phase: UpdatePhase.latest, latestVersion: AppMeta.version)
            : UpdateInfo(
                phase: UpdatePhase.found,
                latestVersion: r.version,
                notes: r.notes,
                downloadUrl: r.downloadUrl,
                sizeText: r.sizeText,
              );
      }
    } catch (e) {
      if (silent) return; // 静默检查失败：保持原状，不进 error 态
      update = UpdateInfo(phase: UpdatePhase.error, error: '$e');
    }
    notifyListeners();
  }

  /// 启动静默检查的节流间隔：6 小时
  static const int _updateCheckIntervalMs = 6 * 60 * 60 * 1000;

  /// 每次冷启动最多调度一次；首帧渲染后再延迟 3 秒执行，避免挤占启动期
  bool _startupCheckScheduled = false;

  void scheduleStartupUpdateCheck() {
    if (_startupCheckScheduled) return;
    _startupCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(seconds: 3), () {
        // ignore: unawaited_futures
        checkUpdate(silent: true);
      });
    });
  }

  /// 应用内下载 APK，下载完直接拉起系统安装器（不跳浏览器）
  Future<void> downloadAndInstall() async {
    final cur = update;
    if (cur == null || cur.downloadUrl.isEmpty) return;

    UpdateInfo stage(double p) => UpdateInfo(
          phase: UpdatePhase.downloading,
          latestVersion: cur.latestVersion,
          notes: cur.notes,
          downloadUrl: cur.downloadUrl,
          sizeText: cur.sizeText,
          progress: p,
        );

    update = stage(0);
    notifyListeners();

    try {
      final path = await UpdateInstaller.download(
        cur.downloadUrl,
        onProgress: (p, _, __) {
          update = stage(p);
          notifyListeners();
        },
      );
      update = UpdateInfo(
        phase: UpdatePhase.ready,
        latestVersion: cur.latestVersion,
        notes: cur.notes,
        downloadUrl: cur.downloadUrl,
        sizeText: cur.sizeText,
        progress: 1,
        apkPath: path,
      );
      notifyListeners();
      await installDownloaded();
    } catch (e) {
      update = UpdateInfo(phase: UpdatePhase.error, error: '下载失败：$e');
      notifyListeners();
    }
  }

  /// 拉起系统安装器；系统若要求「允许安装未知应用」，会跳到授权页
  Future<String?> installDownloaded() async {
    final path = update?.apkPath;
    if (path == null) return null;
    final msg = await UpdateInstaller.install(path);
    // 安装器已拉起：清掉更新状态，回来后不再显示旧的升级卡片
    update = null;
    notifyListeners();
    return msg;
  }

  void closeUpdate() {
    update = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    for (final p in _providers.values) {
      p.close();
    }
    super.dispose();
  }
}
