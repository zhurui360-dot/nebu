import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudtune/services/tags/lrc_parser.dart';
import 'package:cloudtune/services/tags/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> frame(String id, List<int> payload) {
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

/// 造一个带内嵌歌词（USLT）的 ID3v2.3
Uint8List buildId3WithLyrics(String lyrics) {
  final body = <int>[
    0x03, // UTF-8
    ...utf8.encode('eng'),
    0x00, // 空描述
    ...utf8.encode(lyrics),
  ];
  final frames = <int>[
    ...frame('TIT2', [0x03, ...utf8.encode('晴天')]),
    ...frame('TPE1', [0x03, ...utf8.encode('周杰伦')]),
    ...frame('USLT', body),
  ];
  final size = frames.length;
  return Uint8List.fromList([
    0x49, 0x44, 0x33, 0x03, 0x00, 0x00,
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
    ...frames,
  ]);
}

void main() {
  test('能读出 ID3v2 里内嵌的歌词（USLT）', () {
    final lrc = '[00:12.50]故事的小黄花\n[00:20.00]从出生那年就飘着';
    final tag = TagReader.parse(buildId3WithLyrics(lrc));
    expect(tag.title, '晴天');
    expect(tag.artist, '周杰伦');
    expect(tag.lyrics, isNotNull);
    expect(tag.lyrics, contains('故事的小黄花'));
  });

  test('纯文本歌词会被整理成可滚动的 LRC', () {
    final text = '第一行\n第二行\n第三行';
    final lrc = LrcParser.toLrc(text);
    expect(lrc, contains('[00:00.00]第一行'));
    expect(lrc, contains('[00:06.00]第二行'));
    // 整理后必须能被解析回时间轴
    final lines = LrcParser.parse(lrc);
    expect(lines.length, 3);
    expect(lines.first.time, Duration.zero);
  });

  test('本身就是 LRC 时不重复加时间轴', () {
    final lrc = '[01:02.00]晴天';
    expect(LrcParser.toLrc(lrc), lrc);
  });

  test('HTML 之类的内容不会被当歌词', () {
    expect(LrcParser.toLrc('<html><body>404</body></html>'), '');
  });

  test('双语 LRC：同一时间戳的第二行并入翻译', () {
    final lrc = '[00:10.00]All of the scars\n'
        '[00:10.00]所有我无法抹去的伤痕\n'
        '[00:16.00]Quiet is stronger\n'
        '[00:16.02]沉默的力量\n'
        '[00:24.00]下一句原文';
    final lines = LrcParser.parse(lrc);

    expect(lines.length, 3);
    expect(lines[0].text, 'All of the scars');
    expect(lines[0].trans, '所有我无法抹去的伤痕');
    expect(lines[1].text, 'Quiet is stronger');
    expect(lines[1].trans, '沉默的力量'); // 30ms 内的抖动也算翻译行
    expect(lines[2].text, '下一句原文');
    expect(lines[2].trans, isNull);
  });

  test('不同时间戳不合并（副歌重复不受影响）', () {
    final lrc = '[00:10.00]副歌\n[00:40.00]副歌';
    final lines = LrcParser.parse(lrc);
    expect(lines.length, 2);
    expect(lines[0].trans, isNull);
    expect(lines[1].trans, isNull);
  });
}
