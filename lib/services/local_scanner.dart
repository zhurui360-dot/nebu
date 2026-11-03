import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';
import 'tags/lrc_parser.dart';
import 'cover_codec.dart';
import 'tags/tag_reader.dart';
import 'tags/track_guesser.dart';

class LocalScanResult {
  LocalScanResult({
    required this.tracks,
    required this.scanned,
    required this.withCover,
    required this.withLyric,
  });

  final List<Track> tracks;

  /// 扫到的音频文件数（含与库里重复的）
  final int scanned;
  final int withCover;
  final int withLyric;
}

/// 扫描手机本地音乐。
///
/// 不依赖 MediaStore 插件：直接遍历外部存储里的音频文件，
/// 用自带的 TagReader 读标签（和网盘导入走同一套解析）。
class LocalScanner {
  static const _headSize = 256 * 1024;
  static const _bigHead = 2 * 1024 * 1024;
  static const _maxTag = 6 * 1024 * 1024;

  /// 封面最多读这么大。现实里见过 15MB 的内嵌 PNG，
  /// 上限给足才能读出来，落盘前再统一缩图（见 CoverCodec）。
  static const _maxArt = 24 * 1024 * 1024;

  /// 同目录下的封面文件名 / 扩展名（很多整轨专辑只带一个 cover.jpg）
  static const _coverNames = {'cover', 'folder', 'album', 'front', 'artwork', 'thumb'};
  static const _coverExts = {'jpg', 'jpeg', 'png', 'webp', 'bmp'};
  static const _tailSize = 128 * 1024;
  static const _maxFiles = 20000;

  /// 这些目录不扫（缓存/聊天记录/系统）
  static const _skipDirs = {
    'android', 'lost.dir', '.thumbnails', '.trashed', '.trash',
    'miui', 'backups', 'telegram', 'whatsapp', 'wechat', 'micromsg',
    '.git', 'node_modules',
  };

  /// 这些目录里的短音频多半是铃声，不当音乐
  static const _ringtoneDirs = {'ringtones', 'notifications', 'alarms', 'ui'};

  Future<bool> ensurePermission() async {
    // Android 13+ 是 READ_MEDIA_AUDIO，之前是 READ_EXTERNAL_STORAGE
    if (await Permission.audio.isGranted) return true;
    if (await Permission.storage.isGranted) return true;

    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;

    final storage = await Permission.storage.request();
    if (storage.isGranted) return true;

    // 被永久拒绝时，只能引导用户去设置里开
    if (audio.isPermanentlyDenied || storage.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
  }

  Future<LocalScanResult> scan({
    /// 只扫这些目录（空 = 全盘：手机里的存储根目录）
    List<String>? roots,
    void Function(int done, int total)? onProgress,
    void Function(String status)? onStatus,

    /// 每解析出一首歌就回调一次 → 曲库实时可见
    void Function(Track track)? onTrackScanned,
  }) async {
    final dirs = (roots == null || roots.isEmpty)
        ? await storageRoots()
        : roots;
    final covers = await _subDir('covers');
    final lyrics = await _subDir('lyrics');

    // 先收集文件，再解析，这样进度条有总量
    final files = <File>[];
    for (final root in dirs) {
      if (files.length >= _maxFiles) break;
      await _walkDirectory(Directory(root), files, depth: 0);
    }
    onStatus?.call('找到 ${files.length} 个音频文件');

    // 同目录封面只找一次；封面字节也按内容去重，一张专辑不会存 N 份
    final _dirCoverCache = <String, Uint8List?>{};

    final out = <Track>[];
    var withCover = 0, withLyric = 0;

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      onProgress?.call(i + 1, files.length);

      final path = file.path;
      final ext = path.contains('.') ? path.split('.').last : '';
      final fmt = MusicFormatX.fromExtension(ext);
      if (fmt == null) continue;

      TagData tag = TagData();
      try {
        tag = await _readTags(file);
      } catch (_) {}

      final id = Track.idOf('local', path);

      // 内嵌封面拿不到时，看同目录有没有 cover.jpg / folder.png 之类
      Uint8List? art = tag.artwork;
      if (art == null || art.isEmpty) {
        art = await _siblingCover(_dirCoverCache, path);
      }
      String? coverPath;
      if (art != null && art.isNotEmpty) {
        coverPath = await _writeCover(covers, art);
        if (coverPath != null) withCover++;
      }

      String? lyricPath;
      final lrc = File(path.replaceAll(RegExp(r'\.\w+$'), '.lrc'));
      if (await lrc.exists()) {
        try {
          final text = await lrc.readAsString();
          if (LrcParser.looksLikeLrc(text)) {
            lyricPath = await _write(lyrics, id, utf8.encode(text));
            if (lyricPath != null) withLyric++;
          }
        } catch (_) {}
      }
      // 没有 .lrc 就用文件里内嵌的歌词
      if (lyricPath == null && tag.lyrics != null) {
        final text = LrcParser.toLrc(tag.lyrics!);
        if (text.isNotEmpty) {
          lyricPath = await _write(lyrics, id, utf8.encode(text));
          if (lyricPath != null) withLyric++;
        }
      }

      // 标签不全时用文件名/目录推断（和网盘导入同一套规则）
      final g = TrackGuesser.guess(fileName: p.basename(path), path: path, tag: tag);
      int size = 0;
      try {
        size = await file.length();
      } catch (_) {}

      out.add(Track(
        id: id,
        title: g.title,
        artist: g.artist ?? '未知歌手',
        albumName: g.album ?? '未知专辑',
        albumId: Album.idOf(g.album ?? '未知专辑'),
        year: g.year,
        duration: tag.duration ?? Duration.zero,
        format: tag.format ?? fmt,
        quality: tag.qualityText(),
        hiRes: tag.hiRes,
        hasTags: tag.hasCoreTags,
        url: Uri.file(path).toString(),
        sourceId: 'local',
        path: path,
        coverPath: coverPath,
        lyricPath: lyricPath,
        sizeBytes: size,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        // 本地文件的修改时间当作创建时间
        createdAt: await _mtime(file),
      ));
      onTrackScanned?.call(out.last);
    }

    return LocalScanResult(
      tracks: out,
      scanned: files.length,
      withCover: withCover,
      withLyric: withLyric,
    );
  }

  // ---------------------------------------------------------------
  /// 可访问的存储根目录（Android: /storage/emulated/0 + SD 卡；桌面: ~/Music 等）
  Future<List<String>> storageRoots() async {
    final roots = <String>[];
    if (Platform.isAndroid) {
      const primary = '/storage/emulated/0';
      if (await Directory(primary).exists()) roots.add(primary);
      // 有的机器音乐在 SD 卡
      try {
        final storage = Directory('/storage');
        if (await storage.exists()) {
          await for (final e in storage.list(followLinks: false)) {
            if (e is Directory && e.path != primary && !e.path.contains('self')) {
              final name = p.basename(e.path);
              if (name.length > 3 && !name.startsWith('.')) roots.add(e.path);
            }
          }
        }
      } catch (_) {}
    } else {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        for (final sub in ['Music', 'Downloads', 'Documents']) {
          final d = p.join(home, sub);
          if (await Directory(d).exists()) roots.add(d);
        }
      }
    }
    return roots;
  }

  /// 文件修改时间（毫秒）；读不到就给 0
  static Future<int> _mtime(File f) async {
    try {
      return (await f.lastModified()).millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }

  /// 同目录里的封面文件：cover.jpg / folder.png / front.jpeg …
  Future<Uint8List?> _siblingCover(
      Map<String, Uint8List?> cache, String filePath) async {
    final dir = p.dirname(filePath);
    if (cache.containsKey(dir)) return cache[dir];

    Uint8List? found;
    try {
      final d = Directory(dir);
      if (await d.exists()) {
        final names = <String>[];
        await for (final e in d.list(followLinks: false)) {
          if (e is! File) continue;
          final base = p.basenameWithoutExtension(e.path).toLowerCase();
          final ext = p.extension(e.path).replaceFirst('.', '').toLowerCase();
          if (!_coverNames.contains(base)) continue;
          if (!_coverExts.contains(ext)) continue;
          names.add(e.path);
        }
        // cover.jpg 优先于 thumb.png 之类
        names.sort((a, b) => a.length.compareTo(b.length));
        for (final path in names) {
          final f = File(path);
          final size = await f.length();
          if (size <= 0 || size > _maxArt) continue;
          found = await f.readAsBytes();
          break;
        }
      }
    } catch (_) {}
    cache[dir] = found;
    return found;
  }

  /// 封面落盘：按内容哈希命名，同一张专辑的封面只存一份
  final Map<int, String> _coverByHash = {};

  Future<String?> _writeCover(Directory dir, Uint8List raw) async {
    if (raw.isEmpty || raw.length > _maxArt) return null;
    // 15MB 的封面原样存下来太夸张，先缩到 1200px
    final bytes = await CoverCodec.shrink(raw);
    final h = _hash32(bytes);
    final hit = _coverByHash[h];
    if (hit != null) return hit;
    final path = await _write(dir, 'h$h.${TagReader.imageExt(bytes)}', bytes);
    if (path != null) _coverByHash[h] = path;
    return path;
  }

  /// 快速内容哈希（采样，几 MB 的图也不卡）
  static int _hash32(Uint8List b) {
    var h = 0x811C9DC5;
    final step = b.length > 65536 ? b.length ~/ 65536 : 1;
    for (var i = 0; i < b.length; i += step) {
      h ^= b[i];
      h = (h * 0x01000193) & 0x7FFFFFFF;
    }
    return (h ^ b.length) & 0x7FFFFFFF;
  }

  /// 列某个目录下的子目录（按名字排序，跳过系统/缓存目录与隐藏目录）
  static Future<List<String>> listDirs(String path) async {
    final out = <String>[];
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return out;
      await for (final e in dir.list(followLinks: false)) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue;
        if (_skipDirs.contains(name.toLowerCase())) continue;
        out.add(e.path);
      }
    } catch (_) {}
    out.sort();
    return out;
  }

  Future<void> _walkDirectory(Directory dir, List<File> out, {required int depth}) async {
    if (depth > 8 || out.length >= _maxFiles) return;
    final name = p.basename(dir.path).toLowerCase();
    if (_skipDirs.contains(name)) return;

    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      return; // 没权限的目录直接跳过
    }

    for (final e in entries) {
      if (out.length >= _maxFiles) return;
      if (e is Directory) {
        await _walkDirectory(e, out, depth: depth + 1);
      } else if (e is File) {
        final lower = e.path.toLowerCase();
        if (_ringtoneDirs.any((d) => lower.contains('/$d/'))) continue;
        final ext = p.extension(lower).replaceFirst('.', '');
        if (MusicFormatX.fromExtension(ext) != null) out.add(e);
      }
    }
  }

  /// 读单个文件的标签（供「重新读取标签」复用）
  static Future<TagData> readFileTags(File f) => LocalScanner()._readTags(f);

  /// 取同目录的封面文件（cover.jpg / folder.png …），补全封面时用
  static Future<Uint8List?> siblingCoverFor(String filePath) =>
      LocalScanner()._siblingCover(<String, Uint8List?>{}, filePath);

  /// 读标签：内嵌封面大时，ID3/元数据块会超出常规窗口，这里按需要放大。
  Future<TagData> _readTags(File f) async {
    final len = await f.length();
    final fmt = MusicFormatX.fromExtension(p.extension(f.path).replaceFirst('.', ''));

    Future<Uint8List> read(int n) async {
      final raf = await f.open();
      try {
        return await raf.read(n);
      } finally {
        await raf.close();
      }
    }

    var head = await read(len < _headSize ? len : _headSize);

    // MP3：按 ID3v2 头部声明的长度补齐
    if (head.length >= 10 && head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) {
      var want = TagReader.syncSafe(head, 6, 4) + 10;
      if (want > _maxTag) want = _maxTag;
      if (want > len) want = len;
      if (want > head.length) head = await read(want);
    }

    Uint8List? tail;
    if ((fmt == MusicFormat.m4a || fmt == MusicFormat.ape) && len > _tailSize) {
      final raf = await f.open();
      try {
        await raf.setPosition(len - _tailSize);
        tail = await raf.read(_tailSize);
      } finally {
        await raf.close();
      }
    }

    var tag = TagReader.parse(head, tail: tail, fileSize: len);

    // FLAC：歌词块被大封面挤出窗口时，按块头声明的长度精确补读
    if (fmt == MusicFormat.flac && tag.lyrics == null) {
      final need = TagReader.flacCommentEnd(head);
      if (need != null &&
          need > head.length &&
          need <= 4 * 1024 * 1024 &&
          need <= len) {
        try {
          final full = await read(need);
          tag = TagReader.parse(full, tail: tail, fileSize: len);
        } catch (_) {}
      }
    }

    // 还没读到封面（FLAC 的 PICTURE 块常排在 256KB 之后）→ 放大窗口重读
    if (tag.artwork == null && fmt != MusicFormat.mp3 && len > _headSize) {
      final bigger = await read(len < _bigHead ? len : _bigHead);
      tag = TagReader.parse(bigger, tail: tail, fileSize: len);
    }

    // 封面块本身比窗口还长（FLAC 内嵌 5~6MB 的图就是这样）：
    // TagReader 记下了「需要读到第几字节」，按它补读，最多试 3 次。
    var artTries = 0;
    while (tag.artwork == null &&
        tag.needBytes > head.length &&
        artTries < 3) {
      var want = tag.needBytes;
      if (want > _maxArt) want = _maxArt;
      if (want <= head.length || want > len) break;
      artTries++;
      try {
        final full = await read(want);
        if (full.length <= head.length) break;
        head = full;
        tag = TagReader.parse(head, tail: tail, fileSize: len);
      } catch (_) {
        break;
      }
    }

    // 仍没读到文字标签 → 放大窗口再试一次
    if (!tag.hasCoreTags && fmt != MusicFormat.mp3 && len > _headSize) {
      final bigger = await read(len < _bigHead ? len : _bigHead);
      tag = TagReader.parse(bigger, tail: tail, fileSize: len);
    }

    // DSF：ID3v2 在文件中段，偏移写在文件头 20..27 字节里，按指针去读
    if (fmt == MusicFormat.dsf && tag.lyrics == null) {
      final off = TagReader.dsfId3Offset(head);
      if (off != null && off > 0 && off < len) {
        var want = off + _maxTag;
        if (want > len) want = len;
        final raf = await f.open();
        try {
          await raf.setPosition(off);
          final id3 = await raf.read(want - off);
          TagReader.mergeInto(tag, TagReader.parse(id3));
        } finally {
          await raf.close();
        }
      }
    }
    return tag;
  }

  Future<Directory> _subDir(String name) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String?> _write(Directory dir, String id, List<int> bytes) async {
    try {
      final f = File(p.join(dir.path, id));
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}
