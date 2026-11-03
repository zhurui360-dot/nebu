import 'dart:typed_data';

import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/services/tags/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个最小的 ID3v2.3 头（后面接若干帧）
Uint8List _id3(List<int> frames) {
  final size = frames.length;
  final out = <int>[
    0x49, 0x44, 0x33, // 'ID3'
    3, 0, // 版本 2.3
    0, // flags
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
    ...frames,
  ];
  return Uint8List.fromList(out);
}

/// TLEN 帧：时长（毫秒）
List<int> _tlen(int ms) {
  final text = '$ms'.codeUnits;
  final body = 1 + text.length; // 编码字节 + 正文
  return [
    0x54, 0x4C, 0x45, 0x4E, // 'TLEN'
    (body >> 24) & 0xFF,
    (body >> 16) & 0xFF,
    (body >> 8) & 0xFF,
    body & 0xFF,
    0, 0, // 帧标志
    0, // ISO-8859-1
    ...text,
  ];
}

/// MPEG1 Layer III / 44.1kHz / 128kbps / 立体声 / 无 CRC 的帧头
const _frameHeader = [0xFF, 0xFB, 0x90, 0x00];

void main() {
  test('TLEN 帧里的时长直接取用', () {
    final data = Uint8List.fromList([
      ..._id3(_tlen(185000)),
      ..._frameHeader,
      ...List<int>.filled(300, 0),
    ]);
    final t = TagReader.parse(data, fileSize: data.length);
    expect(t.format, MusicFormat.mp3);
    expect(t.duration, const Duration(milliseconds: 185000));
  });

  test('Xing 头：按总帧数算时长（VBR 也准）', () {
    // 帧头后 36 字节是 Xing（MPEG1 + 立体声 + 无 CRC）
    final d = Uint8List(300);
    d.setRange(0, 4, _frameHeader);
    d.setRange(36, 40, const [0x58, 0x69, 0x6E, 0x67]); // 'Xing'
    d[40] = 0;
    d[41] = 0;
    d[42] = 0;
    d[43] = 1; // flags：有总帧数
    d[44] = 0;
    d[45] = 0;
    d[46] = 0x03;
    d[47] = 0xE8; // 1000 帧

    final t = TagReader.parse(d, fileSize: d.length);
    // 1000 帧 × 1152 采样 ÷ 44100Hz ≈ 26.122 秒
    expect(t.duration, const Duration(milliseconds: 26122));
    expect(t.sampleRate, 44100);
    expect(t.bitrateKbps, 128);
  });

  test('没有 Xing 时按码率 × 文件大小估算（CBR）', () {
    final d = Uint8List.fromList([..._frameHeader, ...List<int>.filled(300, 0)]);
    // 整个文件 1,000,000 字节、128kbps → 1e6 × 8 / 128 = 62500 毫秒
    final t = TagReader.parse(d, fileSize: 1000000);
    expect(t.duration, const Duration(milliseconds: 62500));
  });

  test('ID3 之后才是音频帧：从标签结束处开始找', () {
    final d = Uint8List.fromList([
      ..._id3([]),
      ..._frameHeader,
      ...List<int>.filled(300, 0),
    ]);
    // 音频从第 10 字节开始，大小 1,000,000 → (1e6 - 10) × 8 / 128 = 62499
    final t = TagReader.parse(d, fileSize: 1000000);
    expect(t.duration, const Duration(milliseconds: 62499));
  });

  test('VBRI 头也能算（Fraunhofer 编码器）', () {
    final d = Uint8List(400);
    d.setRange(0, 4, _frameHeader);
    const v = 4 + 32; // VBRI 固定在帧头后 32 字节
    d.setRange(v, v + 4, const [0x56, 0x42, 0x52, 0x49]); // 'VBRI'
    d[v + 14] = 0;
    d[v + 15] = 0;
    d[v + 16] = 0x01;
    d[v + 17] = 0xF4; // 500 帧

    final t = TagReader.parse(d, fileSize: d.length);
    // 500 × 1152 ÷ 44100 ≈ 13.061 秒
    expect(t.duration, const Duration(milliseconds: 13061));
  });

  test('给不出文件大小也没有 Xing：时长留空而不是乱猜', () {
    final d = Uint8List.fromList([..._frameHeader, ...List<int>.filled(300, 0)]);
    final t = TagReader.parse(d);
    expect(t.format, MusicFormat.mp3);
    expect(t.duration, isNull);
  });
}
