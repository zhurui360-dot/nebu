import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudtune/services/tags/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一个最小可识别的 JPEG 头 + 尾巴（解析器只看魔数，不看图像内容）
Uint8List fakeJpeg(int payloadBytes) => Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      ...List<int>.filled(payloadBytes, 0x11),
      0xFF, 0xD9,
    ]);

Uint8List fakePng(int payloadBytes) => Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ...List<int>.filled(payloadBytes, 0x22),
    ]);

/// ID3v2.3 帧
List<int> id3Frame(String id, List<int> payload, {int flags = 0}) {
  final n = payload.length;
  return [
    ...utf8.encode(id),
    (n >> 24) & 0xFF,
    (n >> 16) & 0xFF,
    (n >> 8) & 0xFF,
    n & 0xFF,
    (flags >> 8) & 0xFF,
    flags & 0xFF,
    ...payload,
  ];
}

/// APIC 帧正文：编码 + mime + 0 + 图片类型 + 描述 + 0 + 图片字节
List<int> apicBody(Uint8List image, {String mime = 'image/jpeg'}) => [
      0x03, // UTF-8
      ...utf8.encode(mime),
      0x00,
      0x03, // front cover
      0x00, // 空描述
      ...image,
    ];

Uint8List id3File(List<int> frames, {int version = 3, int flags = 0}) {
  final size = frames.length;
  return Uint8List.fromList([
    0x49, 0x44, 0x33, version, 0x00, flags,
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
    ...frames,
  ]);
}

/// FLAC PICTURE 元数据块（type 6）
List<int> flacPictureBlock(Uint8List image, {String mime = 'image/jpeg'}) {
  final mimeBytes = utf8.encode(mime);
  final body = <int>[
    0x00, 0x00, 0x00, 0x03, // picture type = front cover
    (mimeBytes.length >> 24) & 0xFF,
    (mimeBytes.length >> 16) & 0xFF,
    (mimeBytes.length >> 8) & 0xFF,
    mimeBytes.length & 0xFF,
    ...mimeBytes,
    0x00, 0x00, 0x00, 0x00, // description 长度 0
    0x00, 0x00, 0x02, 0x58, // width 600
    0x00, 0x00, 0x02, 0x58, // height 600
    0x00, 0x00, 0x00, 0x18, // depth 24
    0x00, 0x00, 0x00, 0x00, // colors
    (image.length >> 24) & 0xFF,
    (image.length >> 16) & 0xFF,
    (image.length >> 8) & 0xFF,
    image.length & 0xFF,
    ...image,
  ];
  return body;
}

/// 合成 FLAC 头：fLaC + STREAMINFO + VORBIS_COMMENT(可选) + PICTURE(可选)
Uint8List flacFile({
  List<int>? pictureBlock,
  Map<String, String> comments = const {},
}) {
  final blocks = <List<int>>[];

  // STREAMINFO（34 字节，采样率等填 0 也无妨）
  blocks.add([0x00, 0x00, 0x00, 34, ...List<int>.filled(34, 0)]);

  if (comments.isNotEmpty) {
    final body = <int>[];
    final vendor = utf8.encode('test');
    body.addAll([
      vendor.length & 0xFF, 0, 0, 0,
      ...vendor,
      comments.length & 0xFF, 0, 0, 0,
    ]);
    comments.forEach((k, v) {
      final entry = utf8.encode('$k=$v');
      body.addAll([
        entry.length & 0xFF, (entry.length >> 8) & 0xFF,
        (entry.length >> 16) & 0xFF, (entry.length >> 24) & 0xFF,
        ...entry,
      ]);
    });
    blocks.add([
      0x04,
      (body.length >> 16) & 0xFF,
      (body.length >> 8) & 0xFF,
      body.length & 0xFF,
      ...body,
    ]);
  }

  if (pictureBlock != null) {
    blocks.add([
      0x06,
      (pictureBlock.length >> 16) & 0xFF,
      (pictureBlock.length >> 8) & 0xFF,
      pictureBlock.length & 0xFF,
      ...pictureBlock,
    ]);
  }

  // 最后一个块要打上 last-block 标记
  final out = <int>[...utf8.encode('fLaC')];
  for (var i = 0; i < blocks.length; i++) {
    final b = List<int>.from(blocks[i]);
    if (i == blocks.length - 1) b[0] |= 0x80;
    out.addAll(b);
  }
  return Uint8List.fromList(out);
}

void main() {
  group('FLAC 内嵌封面', () {
    test('能读出 PICTURE 块（这是之前完全没解析的路径）', () {
      final image = fakeJpeg(500);
      final tag = TagReader.parse(flacFile(pictureBlock: flacPictureBlock(image)));
      expect(tag.artwork, isNotNull);
      expect(tag.artwork!.length, image.length);
      expect(TagReader.imageExt(tag.artwork!), 'jpg');
    });

    test('PICTURE 块在 256KB 之后也能读到（大封面）', () {
      final image = fakeJpeg(400 * 1024); // 400KB 封面
      final file = flacFile(pictureBlock: flacPictureBlock(image));
      // 模拟只读前 256KB：应读不到
      final head = Uint8List.sublistView(file, 0, 256 * 1024);
      expect(TagReader.parse(head).artwork, isNull);
      // 读全文件：能读到
      expect(TagReader.parse(file).artwork, isNotNull);
    });

    test('VORBIS_COMMENT 里的 METADATA_BLOCK_PICTURE（base64）也能读', () {
      final image = fakePng(300);
      final b64 = base64.encode(flacPictureBlock(image, mime: 'image/png'));
      final tag = TagReader.parse(flacFile(comments: {
        'TITLE': '测试曲目',
        'METADATA_BLOCK_PICTURE': b64,
      }));
      expect(tag.title, '测试曲目');
      expect(tag.artwork, isNotNull);
      expect(TagReader.imageExt(tag.artwork!), 'png');
    });
  });

  group('MP3 ID3v2 内嵌封面', () {
    test('ID3v2.3 APIC 正常解析', () {
      final image = fakeJpeg(1000);
      final file = id3File([
        ...id3Frame('TIT2', [0x03, ...utf8.encode('星河入海')]),
        ...id3Frame('APIC', apicBody(image)),
      ]);
      final tag = TagReader.parse(file);
      expect(tag.title, '星河入海');
      expect(tag.artwork, isNotNull);
      expect(TagReader.imageExt(tag.artwork!), 'jpg');
    });

    test('大封面（800KB）不被窗口截断时能完整读出', () {
      final image = fakeJpeg(800 * 1024);
      final file = id3File([
        ...id3Frame('APIC', apicBody(image)),
      ]);
      final tag = TagReader.parse(file);
      expect(tag.artwork, isNotNull);
      expect(tag.artwork!.length, image.length);
    });

    test('整体去同步（header flag 0x80）后封面仍正确', () {
      final image = fakeJpeg(200);
      // 手工构造一个带 0x80 flag 的标签：正文里把 FF 后面插 00
      final frames = <int>[
        ...id3Frame('APIC', apicBody(image)),
      ];
      // 先去同步化，得到"文件里真实存放"的字节
      final fileBody = <int>[];
      for (var i = 0; i < frames.length; i++) {
        fileBody.add(frames[i]);
        if (frames[i] == 0xFF) fileBody.add(0x00);
      }
      final size = fileBody.length;
      final file = Uint8List.fromList([
        0x49, 0x44, 0x33, 0x03, 0x00, 0x80, // flags=0x80 → unsynchronised
        (size >> 21) & 0x7F,
        (size >> 14) & 0x7F,
        (size >> 7) & 0x7F,
        size & 0x7F,
        ...fileBody,
      ]);
      final tag = TagReader.parse(file);
      expect(tag.artwork, isNotNull, reason: '去同步后应能还原出封面');
      expect(TagReader.imageExt(tag.artwork!), 'jpg');
    });

    test('帧带 data-length-indicator（v2.4）时跳过长度字段', () {
      final image = fakeJpeg(300);
      final body = apicBody(image);
      final n = body.length;
      final withDli = [
        (n >> 21) & 0x7F,
        (n >> 14) & 0x7F,
        (n >> 7) & 0x7F,
        n & 0x7F,
        ...body,
      ];
      final file = id3File([
        ...id3Frame('APIC', withDli, flags: 0x0001),
      ], version: 4);
      final tag = TagReader.parse(file);
      expect(tag.artwork, isNotNull);
      expect(TagReader.imageExt(tag.artwork!), 'jpg');
    });

    test('不是图片的字节不会被当成封面（避免灰块）', () {
      final notImage = Uint8List.fromList(List<int>.filled(500, 0x33));
      final file = id3File([
        ...id3Frame('APIC', apicBody(notImage)),
      ]);
      expect(TagReader.parse(file).artwork, isNull);
    });
  });

  test('imageExt 按真实魔数判断格式', () {
    expect(TagReader.imageExt(fakeJpeg(10)), 'jpg');
    expect(TagReader.imageExt(fakePng(10)), 'png');
    expect(
      TagReader.imageExt(Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 1, 2,
      ])),
      'webp',
    );
  });
}
