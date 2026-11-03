import 'dart:convert';
import 'dart:typed_data';

import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/services/tags/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// —— 造各种「内嵌歌词」的真实字节 ——

/// MP4 ilst 里的一个 data 原子：[size]['©nam'等]['data'原子]
List<int> mp4DataItem(String key, String value, {int typeCode = 1}) {
  final payload = utf8.encode(value);
  final dataSize = 16 + payload.length; // 4 size + 4 'data' + 4 type + 4 locale + payload
  final keyBytes = latin1.encode(key);
  final atomSize = 8 + keyBytes.length + dataSize;
  return [
    ..._be32(atomSize),
    ...keyBytes,
    ..._be32(dataSize),
    ...latin1.encode('data'),
    ..._be32(typeCode),
    0, 0, 0, 0, // locale
    ...payload,
  ];
}

List<int> _be32(int v) => [
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ];

Uint8List buildM4a({String? title, String? artist, String? lyrics}) {
  final items = <int>[
    if (title != null) ...mp4DataItem('©nam', title),
    if (artist != null) ...mp4DataItem('©ART', artist),
    if (lyrics != null) ...mp4DataItem('©lyr', lyrics),
  ];
  final head = <int>[0, 0, 0, 0, ...latin1.encode('ftyp'), ...latin1.encode('M4A '), 0, 0];
  return Uint8List.fromList([...head, ...items]);
}

/// APEv2 尾部标签
Uint8List buildApeTag(Map<String, String> items) {
  final body = BytesBuilder();
  var count = 0;
  items.forEach((key, value) {
    final v = utf8.encode(value);
    final size = key.length + 1 + v.length;
    body.add(_le32(size));
    body.add(_le32(0)); // flags
    body.add(latin1.encode(key));
    body.add([0x00]);
    body.add(v);
    count++;
  });
  final payload = body.toBytes();
  final tagSize = 32 + payload.length;
  final header = <int>[
    ...latin1.encode('APETAGEX'),
    ..._le32(2000), // version
    ..._le32(tagSize),
    ..._le32(count),
    ..._le32(0), // flags
    0, 0, 0, 0, 0, 0, 0, 0, // reserved
  ];
  return Uint8List.fromList([...header, ...payload]);
}

List<int> _le32(int v) => [
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ];

/// DSF 头：'DSD ' 块（4 id + 8 chunksize + 8 文件大小 + 8 ID3指针）+ fmt 块
/// 指针按规范落在 20..27 字节
Uint8List buildDsfHead(int id3Offset) {
  final b = BytesBuilder();
  b.add(latin1.encode('DSD '));
  b.add(_le64(28)); // DSD 块自身大小
  b.add(_le64(1024 * 1024)); // 文件总大小（示意）
  b.add(_le64(id3Offset)); // ID3v2 指针 → 20..27
  b.add(latin1.encode('fmt '));
  b.add(_le64(52));
  return b.toBytes();
}

List<int> _le64(int v) => [
      for (var i = 0; i < 8; i++) (v >> (8 * i)) & 0xFF,
    ];

/// FLAC：STREAMINFO + 大 PICTURE 块 + VORBIS_COMMENT，整块截到 cutAt
Uint8List buildFlacWithBigPicture(int cutAt) {
  final out = BytesBuilder();
  out.add(latin1.encode('fLaC'));
  // STREAMINFO (type 0)
  out.add(Uint8List.fromList([0x00, 0, 0, 34]));
  out.add(Uint8List(34));
  // PICTURE (type 6) 大块：把歌词块挤出 256KB 窗口
  const picLen = 800 * 1024;
  out.add(Uint8List.fromList([0x06, (picLen >> 16) & 0xFF, (picLen >> 8) & 0xFF, picLen & 0xFF]));
  out.add(Uint8List(picLen));
  // VORBIS_COMMENT (type 4，最后一个块)：vendor长度(0) + 条目数(1) + 条目
  final payload = <int>[
    ..._le32(0), // vendor 长度
    ..._le32(1), // 条目数
    ..._le32(utf8.encode('LYRICS=[00:01.00]内嵌歌词测试').length),
    ...utf8.encode('LYRICS=[00:01.00]内嵌歌词测试'),
  ];
  out.add(Uint8List.fromList([
    0x84,
    (payload.length >> 16) & 0xFF,
    (payload.length >> 8) & 0xFF,
    payload.length & 0xFF,
  ]));
  out.add(payload);
  final all = out.toBytes();
  return Uint8List.sublistView(all, 0, cutAt.clamp(0, all.length));
}

void main() {
  group('M4A 内嵌', () {
    test('©lyr 歌词能读出来（顺带验证歌名歌手不再丢失）', () {
      final tag = TagReader.parse(buildM4a(
        title: '测试歌曲',
        artist: '测试歌手',
        lyrics: '[00:01.00]第一句\n[00:05.00]第二句',
      ));
      expect(tag.format, MusicFormat.m4a);
      expect(tag.title, '测试歌曲');
      expect(tag.artist, '测试歌手');
      expect(tag.lyrics, contains('第一句'));
    });

    test('moov 在尾部（tail 传入）也能读到', () {
      final tail = buildM4a(title: '尾部的歌', lyrics: '纯文本歌词');
      final tag = TagReader.parse(buildM4a(), tail: tail);
      expect(tag.title, '尾部的歌');
      expect(tag.lyrics, '纯文本歌词');
    });
  });

  group('APEv2 内嵌', () {
    test('APE 文件尾部标签：歌名/歌手/歌词', () {
      final tail = buildApeTag({
        'Title': 'APE歌曲',
        'Artist': 'APE歌手',
        'Lyrics': '[00:02.00]APE内嵌歌词',
      });
      final head = Uint8List.fromList([...latin1.encode('MAC '), ...List.filled(20, 0)]);
      final tag = TagReader.parse(head, tail: tail);
      expect(tag.format, MusicFormat.ape);
      expect(tag.title, 'APE歌曲');
      expect(tag.artist, 'APE歌手');
      expect(tag.lyrics, contains('APE内嵌歌词'));
    });
  });

  group('DSF 内嵌', () {
    test('dsfId3Offset 读出文件头里的指针', () {
      const off = 1024 * 512;
      final head = buildDsfHead(off);
      expect(TagReader.dsfId3Offset(head), off);
      expect(TagReader.dsfId3Offset(Uint8List(10)), isNull);
    });
  });

  group('FLAC 大封面挤占窗口', () {
    // 块布局：4(fLaC) + 4+34(STREAMINFO) + 4+800KB(PICTURE) = 819246 处是歌词块头
    const picStart = 4 + 4 + 34;
    const picLen = 800 * 1024;
    const commentHeader = picStart + 4 + picLen;

    test('窗口截在歌词块内部 → flacCommentEnd 算出完整所需字节数', () {
      final head = buildFlacWithBigPicture(commentHeader + 16); // 头可见、正文被截
      final need = TagReader.flacCommentEnd(head);
      expect(need, isNotNull);
      expect(need! > head.length, isTrue);
    });

    test('窗口截在大封面中间（256KB 常规读取）→ 返回 null，交给放大窗口兜底', () {
      final head = buildFlacWithBigPicture(256 * 1024);
      expect(TagReader.flacCommentEnd(head), isNull);
      final broken = TagReader.parse(head);
      expect(broken.lyrics, isNull); // 修复前的现象
    });

    test('补齐到歌词块结束就能读到内嵌歌词', () {
      final probe = buildFlacWithBigPicture(commentHeader + 4);
      final need = TagReader.flacCommentEnd(probe)!;
      final fixed = TagReader.parse(buildFlacWithBigPicture(need));
      expect(fixed.lyrics, contains('内嵌歌词测试'));
    });
  });
}
