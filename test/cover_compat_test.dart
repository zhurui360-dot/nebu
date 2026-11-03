import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudtune/services/tags/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一个 ID3v2.3 标签
Uint8List id3(List<List<int>> frames) {
  final body = <int>[];
  for (final f in frames) {
    body.addAll(f);
  }
  final n = body.length;
  return Uint8List.fromList([
    ...'ID3'.codeUnits,
    3, 0, 0, // v2.3, flags 0
    (n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F,
    ...body,
  ]);
}

List<int> frame(String id, List<int> payload) => [
      ...utf8.encode(id),
      (payload.length >> 24) & 0xFF,
      (payload.length >> 16) & 0xFF,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
      0, 0,
      ...payload,
    ];

List<int> textFrame(String id, String v) => frame(id, [0x03, ...utf8.encode(v)]);

/// 一段「像真图」的 JPEG：SOI + 填充 + EOI
List<int> jpeg(int padding) => [
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      ...List<int>.filled(padding, 0x41),
      0xFF, 0xD9,
    ];

void main() {
  group('封面兼容性', () {
    test('标准 APIC 能读到', () {
      final apic = <int>[
        0x00, ...utf8.encode('image/jpeg'), 0x00, 0x03, 0x00, ...jpeg(64),
      ];
      final b = id3([frame('APIC', apic), textFrame('TIT2', '晴天')]);
      final t = TagReader.parse(b);
      expect(t.artwork, isNotNull);
      expect(t.artwork!.sublist(0, 2), [0xFF, 0xD8]);
      expect(t.artwork!.sublist(t.artwork!.length - 2), [0xFF, 0xD9]);
    });

    test('APIC 头部写错（UTF-16 描述其实单字节结束）也能靠找图救回', () {
      // enc=1（宣称 UTF-16），描述其实是单字节 0 结束 → 标准解析会错位
      final apic = <int>[
        0x01, ...utf8.encode('image/jpeg'), 0x00, 0x03,
        0x41, 0x42, 0x00, // 描述：AB + 单字节 0
        ...jpeg(48),
      ];
      final b = id3([frame('APIC', apic)]);
      final t = TagReader.parse(b);
      expect(t.artwork, isNotNull, reason: '应以魔数为准把头切掉');
      expect(t.artwork!.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('图片前后有垃圾字节时会切干净', () {
      final apic = <int>[
        0x00, ...utf8.encode('image/jpeg'), 0x00, 0x03, 0x00,
        0x00, 0x00, // 前导填充
        ...jpeg(32),
        0x00, 0x00, 0x00, // 尾部垃圾
      ];
      final t = TagReader.parse(id3([frame('APIC', apic)]));
      expect(t.artwork, isNotNull);
      expect(t.artwork!.sublist(0, 2), [0xFF, 0xD8]);
      expect(t.artwork!.sublist(t.artwork!.length - 2), [0xFF, 0xD9]);
    });

    test('多张 APIC 时取最大的那张（第一张常是 1x1 占位）', () {
      final small = <int>[0x00, ...utf8.encode('image/jpeg'), 0x00, 0x03, 0x00, ...jpeg(8)];
      final big = <int>[0x00, ...utf8.encode('image/jpeg'), 0x00, 0x03, 0x00, ...jpeg(600)];
      final t = TagReader.parse(id3([
        frame('APIC', small),
        textFrame('TIT2', 'x'),
        frame('APIC', big),
      ]));
      expect(t.artwork, isNotNull);
      expect(t.artwork!.length, greaterThan(500));
    });

    test('前面有坏帧时能重同步到后面的 APIC', () {
      final broken = [
        ...utf8.encode('TIT2'),
        0x0F, 0xFF, 0xFF, 0xFF, // 长度离谱，越界
        0, 0,
        0x41, 0x41, 0x41,
      ];
      final apic = <int>[0x00, ...utf8.encode('image/jpeg'), 0x00, 0x03, 0x00, ...jpeg(40)];
      final t = TagReader.parse(id3([broken, frame('APIC', apic)]));
      expect(t.artwork, isNotNull, reason: '坏帧不应让后面的封面全部丢失');
    });

    test('ID3v2.2 的 PIC 帧也能读到', () {
      final pic = <int>[0x00, ...utf8.encode('JPG'), 0x03, 0x00, ...jpeg(40)];
      // v2.2 帧头：3 字节帧名 + 3 字节长度
      List<int> oldFrame(String id, List<int> payload) => [
            ...utf8.encode(id),
            (payload.length >> 16) & 0xFF,
            (payload.length >> 8) & 0xFF,
            payload.length & 0xFF,
            ...payload,
          ];
      final body = <int>[...oldFrame('PIC', pic), ...oldFrame('TT2', [0x03, ...utf8.encode('晴天')])];
      final n = body.length;
      final b = Uint8List.fromList([
        ...'ID3'.codeUnits, 2, 0, 0,
        (n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F,
        ...body,
      ]);
      final t = TagReader.parse(b);
      expect(t.artwork, isNotNull);
      expect(t.title, '晴天');
    });

    test('标签里没有 APIC、但字节流里有图片时兜底能捡到', () {
      // 只在标签外面塞一张 6KB 的图（模拟某些软件的怪写法）
      final head = <int>[
        ...id3([textFrame('TIT2', '晴天'), textFrame('TPE1', '周杰伦')]),
        ...jpeg(6144),
      ];
      final t = TagReader.parse(Uint8List.fromList(head));
      expect(t.artwork, isNotNull);
      expect(t.artwork!.length, greaterThan(4096));
    });

    test('太小的偶然字节不会当成封面', () {
      final head = <int>[
        ...id3([textFrame('TIT2', '晴天')]),
        ...jpeg(20), // 只有 30 字节，不够 4KB
      ];
      final t = TagReader.parse(Uint8List.fromList(head));
      expect(t.artwork, isNull);
    });

    test('扩展名按真实格式给出', () {
      expect(TagReader.imageExt(Uint8List.fromList(jpeg(10))), 'jpg');
      // PNG 魔数
      expect(
        TagReader.imageExt(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0])),
        'png',
      );
    });
  });

  _bigCoverTests();
}

/// 造一个带 PICTURE 块的 FLAC 头（picture 可以大到几 MB）
Uint8List flacWithBigPicture(int picBytes, {List<int>? comment}) {
  List<int> block(int type, List<int> body, {bool last = false}) => [
        (last ? 0x80 : 0) | type,
        (body.length >> 16) & 0xFF,
        (body.length >> 8) & 0xFF,
        body.length & 0xFF,
        ...body,
      ];

  final streamInfo = List<int>.filled(34, 0);
  final img = jpeg(picBytes);

  // PICTURE: 图片类型(4) mimeLen(4) mime 描述长度(4) 描述 w/h/depth/colors(16) dataLen(4) data
  final picBody = <int>[
    0, 0, 0, 3,
    0, 0, 0, 10, ...utf8.encode('image/jpeg'),
    0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    (img.length >> 24) & 0xFF, (img.length >> 16) & 0xFF,
    (img.length >> 8) & 0xFF, img.length & 0xFF,
    ...img,
  ];

  return Uint8List.fromList([
    ...'fLaC'.codeUnits,
    ...block(0, streamInfo),
    if (comment != null) ...block(4, comment),
    ...block(6, picBody, last: true),
  ]);
}

void _bigCoverTests() {
  group('超大内嵌封面（5MB 级）', () {
    test('窗口不够时记录 needBytes，补读后能拿到封面', () {
      final full = flacWithBigPicture(5 * 1024 * 1024);
      final window = Uint8List.sublistView(full, 0, 256 * 1024);

      final small = TagReader.parse(window);
      expect(small.artwork, isNull, reason: '窗口里放不下整张图');
      expect(small.needBytes, greaterThan(5 * 1024 * 1024), reason: '要告诉调用方补读到哪');

      final big = TagReader.parse(full);
      expect(big.artwork, isNotNull);
      expect(big.artwork!.length, greaterThan(5 * 1024 * 1024));
      expect(big.artwork!.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('窗口里偶然出现 BM 字节时不会被当成封面（真实缺陷回归）', () {
      // 复刻用户那个文件：VORBIS 注释里恰好有 0x42 0x4D，
      // 曾经被误判成 BMP 封面，占住位置导致真封面读不出来
      final comment = List<int>.filled(2000, 0x41);
      comment[100] = 0x42;
      comment[101] = 0x4D;
      final full = flacWithBigPicture(290 * 1024, comment: comment);
      final win = Uint8List.sublistView(full, 0, 256 * 1024);

      final small = TagReader.parse(win);
      expect(small.artwork, isNull, reason: '不能把标签里的 BM 当封面');
      expect(small.needBytes, greaterThan(256 * 1024));

      final big = TagReader.parse(full);
      expect(big.artwork, isNotNull);
      expect(big.artwork!.sublist(0, 2), [0xFF, 0xD8]);
      expect(TagReader.imageExt(big.artwork!), 'jpg');
    });

    test('isImageHeader 能挡住不是图片的文件', () {
      expect(TagReader.isImageHeader(Uint8List.fromList(jpeg(20))), isTrue);
      expect(
        TagReader.isImageHeader(
            Uint8List.fromList([0x42, 0x4D, 0x41, 0x41, 0x41, 0x41, 0x01, 0x02, 0, 0])),
        isFalse,
      );
      expect(TagReader.isImageHeader(Uint8List.fromList(List.filled(32, 0x41))), isFalse);
    });

    test('flacPictureEnd 给出补读终点', () {
      final full = flacWithBigPicture(1024);
      final end = TagReader.flacPictureEnd(Uint8List.sublistView(full, 0, 512));
      expect(end, isNotNull);
      expect(end! <= full.length, isTrue);
    });
  });
}
