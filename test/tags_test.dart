import 'dart:typed_data';

import 'package:cloudtune/models/models.dart';
import 'mock_provider.dart';
import 'package:cloudtune/services/tags/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这组测试验证「真的在解析字节」：
/// MockProvider 会拼一个合法的 FLAC 文件头（含 VORBIS_COMMENT），
/// TagReader 从里面把标题 / 歌手 / 专辑 / 采样率解析出来。
void main() {
  final provider = MockProvider(sourceId: 'mock', displayName: '演示');

  test('FLAC：解析 STREAMINFO 参数', () async {
    final bytes = await provider.fetchRange('/音乐/测试歌手/不存在的情人.flac', 0, 262143);
    final tag = TagReader.parse(bytes, fileSize: bytes.length);

    expect(tag.format, MusicFormat.flac);
    expect(tag.sampleRate, 96000);
    expect(tag.bitsPerSample, 24);
    expect(tag.channels, 2);
    expect(tag.duration?.inSeconds, 246);
    expect(tag.hiRes, isTrue);
  });

  test('FLAC：解析 VORBIS_COMMENT 文本标签', () async {
    final bytes = await provider.fetchRange('/音乐/测试歌手/不存在的情人.flac', 0, 262143);
    final tag = TagReader.parse(bytes);

    expect(tag.title, '不存在的情人');
    expect(tag.artist, '测试歌手');
    expect(tag.album, '学不会');
    expect(tag.year, 2011);
    expect(tag.hasCoreTags, isTrue);
    expect(tag.qualityText(), '24bit/96kHz');
  });

  test('没有 VORBIS_COMMENT 的文件：标签为空，交给文件名兜底', () async {
    final bytes = await provider.fetchRange('/音乐/测试歌手/未知曲目 03.mp3', 0, 262143);
    final tag = TagReader.parse(bytes);

    expect(tag.format, MusicFormat.flac); // 靠魔数识别，不信任扩展名
    expect(tag.hasCoreTags, isFalse);
    expect(tag.title, isNull);
  });

  test('坏数据不抛异常', () {
    final tag = TagReader.parse(Uint8List.fromList(List.generate(12, (i) => i)));
    expect(tag.format, isNull);
    expect(tag.hasCoreTags, isFalse);
  });

  test('格式识别靠扩展名兜底', () {
    expect(MusicFormatX.fromExtension('flac'), MusicFormat.flac);
    expect(MusicFormatX.fromExtension('M4A'), MusicFormat.m4a);
    expect(MusicFormatX.fromExtension('txt'), isNull);
  });
}
