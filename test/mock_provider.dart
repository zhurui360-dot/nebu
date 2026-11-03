import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/services/cloud/cloud_provider.dart';

import 'fixtures.dart';

/// 测试用网盘：不需要账号，返回一整套"真实字节"。
///
/// 它吐给扫描器的是**真的 FLAC 文件头**（含 VORBIS_COMMENT），
/// 所以测试里的「读标签」是真的在解析字节，不是假进度。
/// 只存在于 test/ 目录，不参与打包。
class MockProvider implements CloudProvider {
  MockProvider({required this.sourceId, required this.displayName});

  @override
  final String sourceId;
  @override
  final String displayName;

  /// 目录结构（扁平模拟：一个根目录 + 四个子目录）
  static const _folders = ['/音乐/测试歌手', '/音乐/华语流行', '/音乐/OST 原声', '/Music/Chill'];

  @override
  Future<List<CloudEntry>> list(String path) async {
    if (path.isEmpty || path == '/') {
      return [
        for (final f in _folders)
          CloudEntry(path: f, name: f.split('/').last, isDir: true),
      ];
    }
    if (path == '/音乐/测试歌手') {
      // 与 Fixtures 同路径 → 再次导入不会重复（去重逻辑可验证）
      return [
        for (final t in Fixtures.seedTracks())
          CloudEntry(
            path: t.path ?? '',
            name: (t.path ?? '').split('/').last,
            isDir: false,
            size: t.sizeBytes,
            modified: DateTime.now(),
          ),
        // 三个新文件：两个带标签、一个故意没有标签（用来验证在线补全那一步）
        const CloudEntry(
            path: '/音乐/测试歌手/冻结.flac',
            name: '冻结.flac',
            isDir: false,
            size: 30 * 1024 * 1024),
        const CloudEntry(
            path: '/音乐/测试歌手/当你.flac',
            name: '当你.flac',
            isDir: false,
            size: 28 * 1024 * 1024),
        const CloudEntry(
            path: '/音乐/测试歌手/未知曲目 03.mp3',
            name: '未知曲目 03.mp3',
            isDir: false,
            size: 8 * 1024 * 1024),
      ];
    }
    // 其他目录给几条占位文件
    return [
      for (var i = 0; i < 3; i++)
        CloudEntry(
          path: '$path/示例曲目${i + 1}.flac',
          name: '示例曲目${i + 1}.flac',
          isDir: false,
          size: 30 * 1024 * 1024,
        ),
    ];
  }

  @override
  Future<Uint8List> fetchRange(String path, int start, int end) async {
    final base = path.split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
    final seeded = Fixtures.seedTracks().where((t) {
      final baseName = (t.path ?? '').split('/').last.replaceAll(RegExp(r'\.\w+$'), '');
      return baseName == base;
    }).toList();
    final track = seeded.isEmpty ? null : seeded.first;

    // 标了 hasTags=false 的，故意不写 VORBIS_COMMENT
    final withTags = base.startsWith('未知曲目') ? false : (track?.hasTags ?? true);
    return buildFlac(
      title: track?.title ?? base,
      artist: track?.artist ?? '未知歌手',
      album: track?.albumName ?? '未知专辑',
      year: track?.year,
      seconds: track?.duration.inSeconds ?? 240,
      sampleRate: 96000,
      bits: 24,
      channels: 2,
      withTags: withTags,
    );
  }

  @override
  Future<String> directUrl(String path) async => '';

  @override
  Map<String, String> get playbackHeaders => const {};

  @override
  Future<void> close() async {}

  // ------------------------------------------------------------------
  /// 手工拼一个合法的 FLAC 头：fLaC + STREAMINFO + (可选)VORBIS_COMMENT
  static Uint8List buildFlac({
    required String title,
    required String artist,
    required String album,
    int? year,
    required int seconds,
    required int sampleRate,
    required int bits,
    required int channels,
    required bool withTags,
  }) {
    final out = BytesBuilder();
    out.add(ascii.encode('fLaC'));

    // ---- STREAMINFO (type 0) ----
    final streamInfo = Uint8List(34);
    final totalSamples = sampleRate * seconds;
    streamInfo[10] = (sampleRate >> 12) & 0xFF;
    streamInfo[11] = (sampleRate >> 4) & 0xFF;
    streamInfo[12] = ((sampleRate & 0x0F) << 4) | (((channels - 1) & 0x07) << 1) | (((bits - 1) >> 4) & 0x01);
    streamInfo[13] = (((bits - 1) & 0x0F) << 4) | ((totalSamples >> 32) & 0x0F);
    streamInfo[14] = (totalSamples >> 24) & 0xFF;
    streamInfo[15] = (totalSamples >> 16) & 0xFF;
    streamInfo[16] = (totalSamples >> 8) & 0xFF;
    streamInfo[17] = totalSamples & 0xFF;

    if (!withTags) {
      out.add(Uint8List.fromList([0x80, 0, 0, 34])); // 最后一个 block，无注释
      out.add(streamInfo);
      return out.toBytes();
    }

    out.add(Uint8List.fromList([0x00, 0, 0, 34])); // 还有后续 block
    out.add(streamInfo);

    // ---- VORBIS_COMMENT (type 4) ----
    final comments = <String>[
      'TITLE=$title',
      'ARTIST=$artist',
      'ALBUM=$album',
      if (year != null) 'DATE=$year',
    ];
    final vendor = utf8.encode('cloudtune-mock');
    final body = BytesBuilder();
    body.add(_le32(vendor.length));
    body.add(vendor);
    body.add(_le32(comments.length));
    for (final c in comments) {
      final bytes = utf8.encode(c);
      body.add(_le32(bytes.length));
      body.add(bytes);
    }
    final payload = body.toBytes();

    out.add(Uint8List.fromList([
      0x84, // 最后一个 block + type 4
      (payload.length >> 16) & 0xFF,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
    ]));
    out.add(payload);
    return out.toBytes();
  }

  static Uint8List _le32(int v) =>
      Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  static MusicFormat? formatOf(CloudEntry e) =>
      MusicFormatX.fromExtension(e.name.split('.').last);
}
