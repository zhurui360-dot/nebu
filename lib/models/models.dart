// 云听 CloudTune · 数据模型
// 曲库对象已经和数据库表对齐（见 data/db/app_database.dart）

enum MusicFormat { flac, ape, wav, m4a, mp3, aac, ogg, dsf }

extension MusicFormatX on MusicFormat {
  /// 界面角标用的短名
  String get label => switch (this) {
        MusicFormat.flac => 'FLAC',
        MusicFormat.ape => 'APE',
        MusicFormat.wav => 'WAV',
        MusicFormat.m4a => 'M4A',
        MusicFormat.mp3 => 'MP3',
        MusicFormat.aac => 'AAC',
        MusicFormat.ogg => 'OGG',
        MusicFormat.dsf => 'DSF',
      };

  /// 常见扩展名，导入扫描时用
  List<String> get extensions => switch (this) {
        MusicFormat.flac => ['flac'],
        MusicFormat.ape => ['ape'],
        MusicFormat.wav => ['wav'],
        MusicFormat.m4a => ['m4a', 'alac', 'mp4'],
        MusicFormat.mp3 => ['mp3'],
        MusicFormat.aac => ['aac'],
        MusicFormat.ogg => ['ogg', 'opus'],
        MusicFormat.dsf => ['dsf', 'dff'],
      };

  /// 是否无损
  bool get lossless => this != MusicFormat.mp3 &&
      this != MusicFormat.aac &&
      this != MusicFormat.ogg;

  static MusicFormat? fromExtension(String ext) {
    final e = ext.toLowerCase();
    for (final f in MusicFormat.values) {
      if (f.extensions.contains(e)) return f;
    }
    return null;
  }

  static MusicFormat fromName(String? name) =>
      MusicFormat.values.firstWhere((f) => f.name == name, orElse: () => MusicFormat.mp3);
}

class Album {
  const Album({
    required this.id,
    required this.name,
    required this.year,
    this.artist = '未知歌手',
    this.coverStyle = 1,
  });

  final String id;
  final String name;
  final int year;
  final String artist;

  /// 0 = 《学不会》山景封面（代码绘制），1..6 = 渐变封面
  final int coverStyle;

  /// 专辑 id 由专辑名生成，保证同名专辑归到一起
  static String idOf(String name) => 'al-${_hash(name)}';

  static String _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.albumId,
    required this.duration,
    required this.format,
    this.artist = '未知歌手',
    this.albumName = '',
    this.year,
    this.quality = '',
    this.hiRes = false,
    this.hasTags = false,
    this.url,
    this.sourceId,
    this.path,
    this.coverPath,
    this.lyricPath,
    this.sizeBytes = 0,
    this.addedAt = 0,
    this.createdAt = 0,
  });

  final String id;

  /// 稳定 id：sourceId + 网盘路径 的哈希
  static String idOf(String sourceId, String path) =>
      'tr-${Album._hash('$sourceId::$path')}';

  /// 空曲目：还没有导入任何歌时给 UI 占位用（不是示例数据，不会入库）
  factory Track.empty() => const Track(
        id: '',
        title: '还没有歌曲',
        albumId: '',
        albumName: '',
        artist: '未知歌手',
        duration: Duration.zero,
        format: MusicFormat.mp3,
      );

  final String title;
  final String albumId;
  final String albumName;
  final String artist;
  final int? year;
  final Duration duration;
  final MusicFormat format;

  /// 规格描述，如 "24bit/96kHz"
  final String quality;
  final bool hiRes;

  /// 是否读到了内置标签（标题/歌手/专辑/封面）
  final bool hasTags;

  /// 直链。为空时播放器走模拟进度
  final String? url;
  final String? sourceId;

  /// 网盘内路径（重新授权后可以据此续签直链）
  final String? path;

  /// 内嵌封面落盘后的本地文件路径（没有封面则为 null）
  final String? coverPath;

  /// 从网盘同目录下载的 .lrc 落盘路径（没有则为 null）
  final String? lyricPath;
  final int sizeBytes;
  final int addedAt;

  /// 文件本身的创建/修改时间（毫秒时间戳）：网盘的 getlastmodified
  /// 或本地文件的 mtime，用于「按创建时间」排序
  final int createdAt;

  String get durationText =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

  Track copyWith({
    String? title,
    String? albumName,
    String? albumId,
    String? artist,
    int? year,
    bool? hasTags,
    String? url,
    String? quality,
    bool? hiRes,
    MusicFormat? format,
    Duration? duration,
    String? coverPath,
    String? lyricPath,
  }) =>
      Track(
        id: id,
        title: title ?? this.title,
        albumId: albumId ?? this.albumId,
        albumName: albumName ?? this.albumName,
        artist: artist ?? this.artist,
        year: year ?? this.year,
        duration: duration ?? this.duration,
        format: format ?? this.format,
        quality: quality ?? this.quality,
        hiRes: hiRes ?? this.hiRes,
        hasTags: hasTags ?? this.hasTags,
        url: url ?? this.url,
        sourceId: sourceId,
        path: path,
        coverPath: coverPath ?? this.coverPath,
        lyricPath: lyricPath ?? this.lyricPath,
        sizeBytes: sizeBytes,
        addedAt: addedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': albumName,
        'album_id': albumId,
        'year': year,
        'duration_ms': duration.inMilliseconds,
        'format': format.name,
        'quality': quality,
        'hi_res': hiRes ? 1 : 0,
        'has_tags': hasTags ? 1 : 0,
        'url': url,
        'source_id': sourceId,
        'path': path,
        'cover_path': coverPath,
        'lyric_path': lyricPath,
        'size_bytes': sizeBytes,
        'added_at': addedAt,
        'created_at': createdAt,
      };

  static Track fromMap(Map<String, Object?> m) => Track(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '未知歌曲',
        artist: (m['artist'] as String?) ?? '未知歌手',
        albumName: (m['album'] as String?) ?? '',
        albumId: (m['album_id'] as String?) ?? Album.idOf(m['album'] as String? ?? ''),
        year: m['year'] as int?,
        duration: Duration(milliseconds: (m['duration_ms'] as int?) ?? 0),
        format: MusicFormatX.fromName(m['format'] as String?),
        quality: (m['quality'] as String?) ?? '',
        hiRes: (m['hi_res'] as int? ?? 0) == 1,
        hasTags: (m['has_tags'] as int? ?? 0) == 1,
        url: m['url'] as String?,
        sourceId: m['source_id'] as String?,
        path: m['path'] as String?,
        coverPath: m['cover_path'] as String?,
        lyricPath: m['lyric_path'] as String?,
        sizeBytes: (m['size_bytes'] as int?) ?? 0,
        addedAt: (m['added_at'] as int?) ?? 0,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

enum SourceKind { quark, baidu, unicom, webdav }

class CloudSource {
  const CloudSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.subtitle,
    required this.connected,
    required this.gradient,
    this.badge,
    this.importedDirs = 0,
    this.baseUrl,
    this.username,
  });

  final String id;
  final String name;
  final SourceKind kind;
  final String subtitle;
  final bool connected;
  final List<int> gradient; // [colorA, colorB]（ARGB）
  final String? badge; // 如「通用」
  final int importedDirs;

  /// WebDAV 用：服务器地址与账号
  final String? baseUrl;
  final String? username;

  CloudSource copyWith({
    int? importedDirs,
    bool? connected,
    String? baseUrl,
    String? username,
    String? subtitle,
  }) =>
      CloudSource(
        id: id,
        name: name,
        kind: kind,
        subtitle: subtitle ?? this.subtitle,
        connected: connected ?? this.connected,
        gradient: gradient,
        badge: badge,
        importedDirs: importedDirs ?? this.importedDirs,
        baseUrl: baseUrl ?? this.baseUrl,
        username: username ?? this.username,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'base_url': baseUrl,
        'username': username,
        'connected': connected ? 1 : 0,
        'imported_dirs': importedDirs,
      };

  static CloudSource fromMap(Map<String, Object?> m, List<int> gradient) => CloudSource(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        kind: SourceKind.values.firstWhere(
          (e) => e.name == m['kind'],
          orElse: () => SourceKind.webdav,
        ),
        subtitle: '',
        connected: (m['connected'] as int? ?? 0) == 1,
        gradient: gradient,
        importedDirs: (m['imported_dirs'] as int?) ?? 0,
        baseUrl: m['base_url'] as String?,
        username: m['username'] as String?,
      );
}

/// 待导入的目录
class CloudFolder {
  const CloudFolder({
    required this.id,
    required this.path,
    required this.fileCount,
    this.selected = false,
  });

  final String id;
  final String path;
  final int fileCount;
  final bool selected;

  CloudFolder copyWith({bool? selected}) =>
      CloudFolder(id: id, path: path, fileCount: fileCount, selected: selected ?? this.selected);
}

/// 已保存下来的导入目录（之后可以再次扫描，只把新歌加进来）
class SavedFolder {
  const SavedFolder({
    required this.id,
    required this.sourceId,
    required this.path,
    this.fileCount = 0,
    this.includeSub = false,
    this.lastScan = 0,
  });

  final String id;
  final String sourceId;
  final String path;
  final int fileCount;
  final bool includeSub;
  final int lastScan;

  SavedFolder copyWith({int? fileCount, bool? includeSub, int? lastScan}) => SavedFolder(
        id: id,
        sourceId: sourceId,
        path: path,
        fileCount: fileCount ?? this.fileCount,
        includeSub: includeSub ?? this.includeSub,
        lastScan: lastScan ?? this.lastScan,
      );
}

/// 一行歌词
class LyricLine {
  const LyricLine(this.time, this.text, [this.trans]);
  final Duration time;
  final String text;

  /// 翻译行：双语 LRC 里同一时间戳的第二行（如网易云/LRCLIB 的中英对照）
  final String? trans;
}

/// 自建歌单：只有名字和一串曲目 id，曲目信息仍从曲库取。
/// 用 id 而不是整条 Track，这样重新扫描/换封面后歌单自动跟着更新。
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    DateTime? createdAt,
  })  : trackIds = trackIds ?? <String>[],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final List<String> trackIds;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '未命名歌单',
        trackIds: [
          for (final t in (j['trackIds'] as List? ?? const [])) t as String,
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (j['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );
}
