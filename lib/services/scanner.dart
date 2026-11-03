import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'cloud/cloud_provider.dart';
import 'tags/lrc_parser.dart';
import 'tags/tag_reader.dart';
import 'tags/track_guesser.dart';

class ScanResult {
  ScanResult({
    required this.tracks,
    required this.scanned,
    required this.tagged,
    required this.untagged,
    required this.skipped,
  });

  /// 真正要入库的曲目（已去重）
  final List<Track> tracks;
  final int scanned;
  final int tagged;
  final int untagged;

  /// 库里已有、本次跳过的数量
  final int skipped;

  int get added => tracks.length;
}

/// 扫描器：目录 → 音频文件 → 读文件头 → 解析标签 → 生成曲目
///
/// 关键点：**只下文件头**（默认 256KB），不整首下载，
/// 这样即使目录里有几百首 FLAC，导入也很快。
class MediaScanner {
  MediaScanner(this.provider);

  final CloudProvider provider;

  static const headSize = 256 * 1024;
  static const bigHeadSize = 2 * 1024 * 1024;
  static const tailSize = 128 * 1024;

  Future<ScanResult> scan(
    List<String> folders, {
    Set<String> existingIds = const {},
    bool includeSubDirs = false,
    void Function(int done, int total)? onProgress,

    /// 某个顶级目录的扫描进度（done/total 按该目录下的文件数计）
    void Function(String folder, int done, int total)? onFolderProgress,

    /// 每解析出一首歌就回调一次 → 曲库实时可见，不用等整体扫完
    void Function(Track track, String folder)? onTrackScanned,
  }) async {
    // ---------- 1. 列出所有音频文件 ----------
    final files = <CloudEntry>[];
    final lrcByBase = <String, CloudEntry>{};

    /// 文件路径 → 所属顶级目录（来源页按目录显示进度用）
    final folderOf = <String, String>{};
    String? currentTop;

    void collect(List<CloudEntry> entries) {
      for (final e in entries) {
        if (e.isDir) continue;
        final lower = e.name.toLowerCase();
        if (lower.endsWith('.lrc')) {
          lrcByBase[_baseName(e.name)] = e;
        } else if (_isAudio(e.name)) {
          files.add(e);
          if (currentTop != null) folderOf[e.path] = currentTop;
        }
      }
    }

    // 深度遍历（可选）；文件数上限防止把整个网盘扫穿
    const maxDepth = 6;
    const maxFiles = 5000;

    Future<void> walk(String dir, int depth) async {
      if (files.length >= maxFiles) return;
      final entries = await provider.list(dir);
      collect(entries.where((e) => !e.isDir).toList());
      if (!includeSubDirs || depth >= maxDepth) return;
      for (final e in entries.where((e) => e.isDir)) {
        if (files.length >= maxFiles) return;
        try {
          await walk(e.path, depth + 1);
        } on CloudException {
          // 某个子目录没权限就跳过，不影响其它目录
        }
      }
    }

    for (final folder in folders) {
      currentTop = folder;
      await walk(folder, 0);
    }

    // 封面 / 歌词落盘目录
    final coverDir = await _subDir('covers');
    final lyricDir = await _subDir('lyrics');

    // ---------- 2. 逐个读头解析 ----------
    final result = <Track>[];
    var tagged = 0, untagged = 0, skipped = 0;
    final seen = <String>{};

    // 按顶级目录统计总量，用于来源页的目录级进度
    final folderTotal = <String, int>{};
    final folderDone = <String, int>{};
    for (final f in files) {
      final top = folderOf[f.path];
      if (top != null) folderTotal[top] = (folderTotal[top] ?? 0) + 1;
    }

    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      onProgress?.call(i + 1, files.length);

      final top = folderOf[f.path];
      void bumpFolder() {
        if (top == null) return;
        folderDone[top] = (folderDone[top] ?? 0) + 1;
        onFolderProgress?.call(top, folderDone[top]!, folderTotal[top] ?? 0);
      }

      final id = Track.idOf(provider.sourceId, f.path);
      if (existingIds.contains(id) || seen.contains(id)) {
        skipped++;
        bumpFolder();
        continue;
      }
      seen.add(id);

      TagData tag;
      try {
        tag = await _readTags(f);
      } catch (_) {
        tag = TagData();
      }

      // 内嵌封面写盘（有才写）
      String? coverPath;
      if (tag.artwork != null && tag.artwork!.isNotEmpty) {
        coverPath = await _writeFile(
          coverDir,
          '$id.${TagReader.imageExt(tag.artwork!)}', // 用真实格式做扩展名
          tag.artwork!,
        );
      }

      // 歌词：先看同目录的 .lrc，没有就用文件里内嵌的
      String? lyricPath;
      final lrc = lrcByBase[_baseName(f.name)];
      if (lrc != null) {
        lyricPath = await _fetchLrc(lrc, lyricDir, id);
      }
      if (lyricPath == null && tag.lyrics != null) {
        final text = LrcParser.toLrc(tag.lyrics!);
        if (text.isNotEmpty) {
          lyricPath = await _writeFile(lyricDir, id, utf8.encode(text));
        }
      }

      // 真实播放地址：WebDAV 直链（带认证头交给播放器），没有就留空走模拟
      String? url;
      try {
        final u = await provider.directUrl(f.path);
        if (u.trim().isNotEmpty) url = u;
      } catch (_) {}

      final track = _buildTrack(
        f,
        tag,
        id,
        coverPath: coverPath,
        lyricPath: lyricPath,
        url: url,
      );
      result.add(track);
      track.hasTags ? tagged++ : untagged++;
      onTrackScanned?.call(track, top ?? '');
      bumpFolder();
    }

    return ScanResult(
      tracks: result,
      scanned: files.length,
      tagged: tagged,
      untagged: untagged,
      skipped: skipped,
    );
  }

  /// 读标签：头 256KB + （M4A/APE 时）尾 128KB
  /// 内嵌封面大时 ID3/元数据块会超出常规窗口，这里按需放大。
  Future<TagData> _readTags(CloudEntry f) async {
    final size = f.size;
    final fmt = MusicFormatX.fromExtension(f.name.split('.').last);

    Future<Uint8List> read(int end) => provider.fetchRange(f.path, 0, end);

    var headEnd = size > 0 && size < headSize ? size - 1 : headSize - 1;
    var head = await read(headEnd);

    // MP3：ID3v2 头部声明了标签总长，按它补齐（避免封面把文字帧挤出窗口）
    head = await _completeId3(head, (int end) => read(end), size);

    Uint8List? tail;
    if ((fmt == MusicFormat.m4a || fmt == MusicFormat.ape) && size > tailSize) {
      tail = await provider.fetchRange(f.path, size - tailSize, size - 1);
    }

    var tag = TagReader.parse(head, tail: tail, fileSize: size > 0 ? size : null);

    // FLAC：歌词块(VORBIS_COMMENT)被大封面挤出窗口时，按块头声明的长度精确补读
    if (fmt == MusicFormat.flac && tag.lyrics == null) {
      final need = TagReader.flacCommentEnd(head);
      if (need != null &&
          need > head.length &&
          need <= 4 * 1024 * 1024 &&
          (size <= 0 || need <= size)) {
        try {
          final full = await read(need - 1);
          tag = TagReader.parse(full, tail: tail, fileSize: size > 0 ? size : null);
        } catch (_) {}
      }
    }

    // 还没读到封面（FLAC 的 PICTURE 块常在 256KB 之后）→ 放大窗口重读一次
    if (tag.artwork == null && fmt != MusicFormat.mp3 && size > headSize) {
      final end = size < bigHeadSize ? size - 1 : bigHeadSize - 1;
      try {
        final bigger = await read(end);
        tag = TagReader.parse(bigger, tail: tail, fileSize: size);
      } catch (_) {}
    }

    // 封面块本身比窗口还长（内嵌 5~6MB 的大图）：按解析器记下的长度补读
    var artTries = 0;
    while (tag.artwork == null &&
        tag.needBytes > head.length &&
        artTries < 3 &&
        (size <= 0 || tag.needBytes <= size) &&
        tag.needBytes <= 24 * 1024 * 1024) {
      artTries++;
      try {
        final full = await read(tag.needBytes - 1);
        if (full.length <= head.length) break;
        tag = TagReader.parse(full, tail: tail, fileSize: size > 0 ? size : null);
      } catch (_) {
        break;
      }
    }

    // 还是没读到文字标签（例如 FLAC 的图片块把注释块挤出窗口）→ 放大到 1MB 再试一次
    if (!tag.hasCoreTags && fmt != MusicFormat.mp3 && size > headSize) {
      final end = size < bigHeadSize ? size - 1 : bigHeadSize - 1;
      try {
        final bigger = await read(end);
        tag = TagReader.parse(bigger, tail: tail, fileSize: size);
      } catch (_) {}
    }

    // DSF：ID3v2 在文件中段，偏移写在文件头 20..27 字节里，按指针去读
    if (fmt == MusicFormat.dsf && tag.lyrics == null) {
      final off = TagReader.dsfId3Offset(head);
      if (off != null && off > 0 && (size <= 0 || off < size)) {
        var end = off + 2 * 1024 * 1024;
        if (size > 0 && end > size) end = size;
        try {
          final id3 = await provider.fetchRange(f.path, off, end - 1);
          TagReader.mergeInto(tag, TagReader.parse(id3));
        } catch (_) {}
      }
    }
    return tag;
  }

  /// ID3v2：把标签读完整（上限 6MB，高分辨率内嵌封面常见 2-4MB）
  Future<Uint8List> _completeId3(
    Uint8List head,
    Future<Uint8List> Function(int end) read,
    int size,
  ) async {
    if (head.length < 10) return head;
    if (!(head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33)) return head; // 'ID3'
    final declared = TagReader.syncSafe(head, 6, 4) + 10;
    var want = declared;
    const cap = 6 * 1024 * 1024;
    if (want > cap) want = cap;
    if (want <= head.length) return head;
    var end = want - 1;
    if (size > 0 && end > size - 1) end = size - 1;
    if (end <= head.length) return head;
    try {
      return await read(end);
    } catch (_) {
      return head;
    }
  }

  Track _buildTrack(
    CloudEntry f,
    TagData tag,
    String id, {
    String? coverPath,
    String? lyricPath,
    String? url,
  }) {
    // 识别链：内嵌标签 > 文件名 > 目录结构
    final g = TrackGuesser.guess(fileName: f.name, path: f.path, tag: tag);
    final title = g.title;
    final artist = g.artist ?? '未知歌手';
    final album = g.album ?? '未知专辑';

    final fmt = tag.format ?? MusicFormatX.fromExtension(f.name.split('.').last) ?? MusicFormat.mp3;

    return Track(
      id: id,
      title: title,
      artist: artist,
      albumName: album,
      albumId: Album.idOf(album),
      year: tag.year,
      duration: tag.duration ?? Duration.zero,
      format: fmt,
      quality: tag.qualityText(),
      hiRes: tag.hiRes,
      hasTags: tag.hasCoreTags,
      sourceId: provider.sourceId,
      path: f.path,
      coverPath: coverPath,
      lyricPath: lyricPath,
      url: url,
      sizeBytes: f.size,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      // 网盘目录列表里的 getlastmodified
      createdAt: f.modified?.millisecondsSinceEpoch ?? 0,
    );
  }

  static String _baseName(String fileName) =>
      fileName.replaceAll(RegExp(r'\.\w+$'), '').toLowerCase();

  Future<Directory> _subDir(String name) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String?> _writeFile(Directory dir, String id, List<int> bytes) async {
    try {
      final f = File(p.join(dir.path, id));
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// 下载 .lrc 并校验，是歌词才落盘
  Future<String?> _fetchLrc(CloudEntry lrc, Directory dir, String id) async {
    try {
      final size = lrc.size > 0 && lrc.size < 512 * 1024 ? lrc.size : 512 * 1024;
      final bytes = await provider.fetchRange(lrc.path, 0, size - 1);
      if (bytes.isEmpty) return null;
      // 绝大多数 lrc 是 UTF-8；GBK 的会带乱码，但不影响时间轴
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!LrcParser.looksLikeLrc(text)) return null;
      return await _writeFile(dir, id, utf8.encode(text));
    } catch (_) {
      return null;
    }
  }

  static bool _isAudio(String name) {
    final ext = name.contains('.') ? name.split('.').last : '';
    return MusicFormatX.fromExtension(ext) != null;
  }
}
