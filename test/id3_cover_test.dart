import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloudtune/services/local_scanner.dart';
import 'package:cloudtune/services/tags/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 造一个 ID3v2.3 标签：故意把大封面放在标题帧前面，
/// 让文字帧被挤出常规读取窗口，验证「按标签长度补齐」能读到。
Uint8List buildId3({
  required String title,
  required String artist,
  required String album,
  required int coverSize,
}) {
  List<int> textFrame(String id, String value) {
    final payload = <int>[0x03]..addAll(utf8.encode(value)); // 0x03 = UTF-8
    final size = payload.length;
    return [
      ...utf8.encode(id),
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
      0,
      0,
      ...payload,
    ];
  }

  final mime = utf8.encode('image/jpeg');
  final apicPayload = <int>[
    0x00,
    ...mime,
    0x00,
    0x03, // 封面正面
    0x00, // 描述为空
    // 真实 JPEG 魔数 + 填充：解析器会校验魔数，假字节会被正确拒绝
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
    ...List<int>.filled(coverSize, 0x41),
    0xFF, 0xD9,
  ];

  final frames = <int>[
    ...'APIC'.codeUnits,
    (apicPayload.length >> 24) & 0xFF,
    (apicPayload.length >> 16) & 0xFF,
    (apicPayload.length >> 8) & 0xFF,
    apicPayload.length & 0xFF,
    0,
    0,
    ...apicPayload,
    ...textFrame('TIT2', title),
    ...textFrame('TPE1', artist),
    ...textFrame('TALB', album),
  ];

  // 标签头：'ID3' + 版本 + 标志 + 同步安全长度（每字节只用低 7 位）
  final size = frames.length;
  final header = <int>[
    0x49, 0x44, 0x33, // ID3
    0x03, 0x00, // v2.3
    0x00,
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
  ];
  return Uint8List.fromList([...header, ...frames]);
}

void main() {
  test('大封面在标题帧之前时，仍要读到标签', () async {
    final dir = await Directory.systemTemp.createTemp('cloudtune_id3');
    final file = File(p.join(dir.path, 'x.mp3'));

    final tag = buildId3(
      title: '被封面挡住的歌名',
      artist: '测试歌手',
      album: '测试专辑',
      coverSize: 600 * 1024, // 600KB 封面，把文字帧推到 256KB 之后
    );
    // 标签 + 一段假的音频数据
    await file.writeAsBytes([...tag, ...List<int>.filled(1024, 0)]);

    // 只吃前 256KB 时读不到（这正是之前的问题）
    final head = await file.open();
    final partial = await head.read(256 * 1024);
    await head.close();
    expect(TagReader.parse(partial).title, isNull);
    expect(TagReader.parse(tag).title, '被封面挡住的歌名');

    // 走真实的读取逻辑（会自动按 ID3 长度补齐）
    final parsed = await LocalScanner.readFileTags(file);
    expect(parsed.title, '被封面挡住的歌名');
    expect(parsed.artist, '测试歌手');
    expect(parsed.album, '测试专辑');
    expect(parsed.artwork, isNotNull);

    await dir.delete(recursive: true);
  });

  test('小文件不会产生越界读取', () async {
    final dir = await Directory.systemTemp.createTemp('cloudtune_id3_small');
    final file = File(p.join(dir.path, 'y.mp3'));
    await file.writeAsBytes(List<int>.filled(200, 0));
    final parsed = await LocalScanner.readFileTags(file);
    expect(parsed.title, isNull);

    await dir.delete(recursive: true);
  });
}
