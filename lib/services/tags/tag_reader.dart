import 'dart:convert';
import 'dart:typed_data';

import '../../models/models.dart';

/// 解析出来的标签
class TagData {
  TagData({
    this.format,
    this.title,
    this.artist,
    this.album,
    this.year,
    this.duration,
    this.sampleRate,
    this.bitsPerSample,
    this.channels,
    this.bitrateKbps,
    this.artwork,
    this.lyrics,
  });

  MusicFormat? format;
  String? title;
  String? artist;
  String? album;
  int? year;
  int? trackNo;
  Duration? duration;
  int? sampleRate;
  int? bitsPerSample;
  int? channels;
  int? bitrateKbps;

  /// 内嵌封面（APIC / METADATA_BLOCK_PICTURE / covr）
  Uint8List? artwork;

  /// 解析时遇到「块比读到的字节还长」时记下需要读到哪里（0 = 够用）。
  ///
  /// 典型场景：FLAC 内嵌一张 5~6MB 的封面图，读取窗口只有 256KB/2MB，
  /// 以前直接 break 掉了，于是这类文件永远没有封面。
  /// 调用方按这个值补读一次就能拿到。
  int needBytes = 0;

  /// 内嵌歌词（ID3v2 USLT / Vorbis LYRICS、UNSYNCEDLYRICS）
  String? lyrics;

  bool get hasCoreTags =>
      (title != null && title!.trim().isNotEmpty) &&
      (artist != null && artist!.trim().isNotEmpty);

  bool get hiRes =>
      (bitsPerSample != null && bitsPerSample! >= 24) ||
      (sampleRate != null && sampleRate! > 48000) ||
      format == MusicFormat.dsf;

  /// 生成界面用的规格文案
  String qualityText() {
    if (format == MusicFormat.dsf) return 'DSD64';
    if (bitsPerSample != null && sampleRate != null) {
      final khz = (sampleRate! / 1000).toStringAsFixed(sampleRate! % 1000 == 0 ? 0 : 1);
      return '${bitsPerSample}bit/${khz}kHz';
    }
    if (bitrateKbps != null) return '$bitrateKbps' 'kbps';
    return format?.lossless == true ? '无损' : '';
  }
}

/// 纯 Dart 标签解析：只吃文件头（以及必要时尾部）字节，不依赖原生库。
///
/// 覆盖：FLAC / MP3(ID3v2) / OGG(Vorbis) / M4A(MP4 atom) / WAV(RIFF INFO)
/// APE / DSF 的标签在文件尾，V1 只识别格式与基础参数。
class TagReader {
  /// [head] 文件前 N 字节；[tail] 可选的文件尾部字节（M4A 的 moov 常在尾部）
  static TagData parse(Uint8List head, {Uint8List? tail, int? fileSize}) {
    final t = TagData();
    try {
      if (head.length < 12) return t;

      if (_startsWith(head, 'fLaC')) {
        t.format = MusicFormat.flac;
        _parseFlac(head, t);
      } else if (_startsWith(head, 'ID3')) {
        t.format = MusicFormat.mp3;
        _parseId3v2(head, t);
      } else if (_startsWith(head, 'OggS')) {
        t.format = MusicFormat.ogg;
        _parseOgg(head, t);
      } else if (_startsWith(head, 'RIFF')) {
        t.format = MusicFormat.wav;
        _parseWav(head, t);
      } else if (_startsWith(head, 'MAC ')) {
        t.format = MusicFormat.ape;
        if (tail != null) _parseApe(tail, t);
      } else if (_startsWith(head, 'DSD ')) {
        t.format = MusicFormat.dsf;
      } else if (_isMp4(head)) {
        t.format = MusicFormat.m4a;
        _parseMp4(head, t);
        if (tail != null && (t.title == null || t.album == null)) _parseMp4(tail, t);
      } else if (head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
        t.format = MusicFormat.mp3;
      }

      // MP3 的时长不写在标签里，要从音频帧算：
      // TLEN 帧 → 第一帧的 Xing/Info/VBRI（总帧数）→ 码率 × 文件大小兜底
      if (t.format == MusicFormat.mp3 && t.duration == null) {
        _parseMp3Audio(head, t, fileSize);
      }

      // APE / DSF 等格式标签在尾部，兜底再试一次（没有 APETAGEX 时无副作用）
      if (t.lyrics == null && tail != null && t.format != MusicFormat.m4a) {
        _parseApe(tail, t);
      }

      // 最后一道兜底：结构化解析没拿到封面时，直接在头部字节里找图片。
      // 各种国产软件的畸形 APIC（长度字段算错、mime 缺失、描述没对齐）
      // 都靠这一步救回来。
      //
      // 但 needBytes > 0 表示「块头明确说了真封面在窗口外面」——
      // 这时候在窗口里翻出来的任何东西都是别的字节（曾经把 VORBIS 注释里
      // 偶然出现的 BM 当成 BMP 封面，结果占住位置、真封面反而读不到），
      // 必须交给调用方补读后用结构化解析拿。
      if (t.artwork == null && t.needBytes == 0) {
        t.artwork = _rawArtwork(head);
      }

      // 码率：整首文件的估算（MP3 常用）
      if (t.bitrateKbps == null &&
          fileSize != null &&
          t.duration != null &&
          t.duration!.inMilliseconds > 0) {
        t.bitrateKbps = (fileSize * 8 / t.duration!.inMilliseconds).round();
      }
    } catch (_) {
      // 标签解析永远不能把导入流程带崩，坏文件就当没有标签
    }
    return t;
  }

  // ---------------------------------------------------------------- FLAC
  static void _parseFlac(Uint8List b, TagData t) {
    var i = 4;
    while (i + 4 <= b.length) {
      final header = b[i];
      final isLast = (header & 0x80) != 0;
      final type = header & 0x7F;
      final len = (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      final start = i + 4;
      if (start + len > b.length) {
        // 只对 PICTURE 记录补读长度（大封面被窗口截断是封面丢失的主因）
        if (type == 6) t.needBytes = start + len;
        break;
      }

      if (type == 0 && len >= 18) {
        // STREAMINFO: sampleRate(20bit) channels(3bit) bps(5bit) 从第 10 字节起
        final x = _u32be(b, start + 10);
        t.sampleRate = (x >> 12) & 0xFFFFF;
        t.channels = ((x >> 9) & 0x7) + 1;
        t.bitsPerSample = ((x >> 4) & 0x1F) + 1;
        final totalSamples = ((x & 0xF) << 32) | _u32be(b, start + 14);
        if (t.sampleRate != null && t.sampleRate! > 0 && totalSamples > 0) {
          t.duration = Duration(seconds: (totalSamples / t.sampleRate!).round());
        }
      } else if (type == 4) {
        _parseVorbisComment(b.sublist(start, start + len), t);
      } else if (type == 6 && len > 32) {
        // PICTURE 块：FLAC 内嵌封面，之前完全没解析 —— 这是 FLAC 无封面的主因
        final pic = _flacPicture(b, start, start + len);
        if (pic != null && t.artwork == null) t.artwork = pic;
      }
      if (isLast) break;
      i = start + len;
    }
  }

  /// FLAC PICTURE 块（也用于 Vorbis 的 METADATA_BLOCK_PICTURE）：
  /// type(4) mimeLen(4) mime pictureType(4) descLen(4) desc w h depth colors dataLen(4) data
  static Uint8List? _flacPicture(Uint8List b, int start, int end) {
    try {
      var p = start;
      int u32() {
        if (p + 4 > end) throw const FormatException('eof');
        final v = (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
        p += 4;
        return v;
      }

      u32(); // picture type（0=其他 3=封面正面）
      final mimeLen = u32();
      if (mimeLen < 0 || p + mimeLen > end) return null;
      p += mimeLen; // mime 字符串
      u32(); // description 长度
      final descLen = (b[p - 4] << 24) | (b[p - 3] << 16) | (b[p - 2] << 8) | b[p - 1];
      if (descLen < 0 || p + descLen > end) return null;
      p += descLen;
      if (p + 16 > end) return null;
      p += 16; // width / height / depth / colors
      final dataLen = (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
      p += 4;
      if (dataLen <= 0 || p + dataLen > end) return null;
      final bytes = Uint8List.sublistView(b, p, p + dataLen);
      return _asImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 校验并**切出**真正的图片字节。
  ///
  /// 以前只认「第 0 字节就是魔数」，现实里大量文件的 APIC / covr 里
  /// 前面有填充 0、长度字段没对齐、或者一张图后面还跟着垃圾，
  /// 于是明明有封面却判成没有。现在改成：先在字节里找图片起点，
  /// 再按格式找到结束位置切出来。
  static Uint8List? _asImage(Uint8List d) => _sliceImage(d);

  static Uint8List? _sliceImage(Uint8List d) {
    if (d.length < 12) return null;

    var start = -1;
    var kind = '';

    final jpeg = _findMagic(d, const [0xFF, 0xD8, 0xFF]);
    final png = _findMagic(d, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final gif = _findMagic(d, const [0x47, 0x49, 0x46, 0x38]);
    final webp = _findMagicRiff(d);
    // BMP 的魔数只有两个字节（42 4D），在任意二进制里都极常见，
    // 必须校验文件头字段，否则会把标签里的普通字节当成封面。
    final bmp = _findBmp(d);

    void pick(int idx, String k) {
      if (idx < 0) return;
      if (start < 0 || idx < start) {
        start = idx;
        kind = k;
      }
    }

    pick(jpeg, 'jpg');
    pick(png, 'png');
    pick(gif, 'gif');
    pick(bmp, 'bmp');
    pick(webp, 'webp');

    if (start < 0) return null;

    var end = d.length;
    switch (kind) {
      case 'jpg':
        // 从尾部往前找 EOI，截掉后面的垃圾（很多文件末尾有多余 0）
        for (var i = d.length - 2; i > start; i--) {
          if (d[i] == 0xFF && d[i + 1] == 0xD9) {
            end = i + 2;
            break;
          }
        }
      case 'png':
        final iend = _findMagic(d, const [0x49, 0x45, 0x4E, 0x44], from: start);
        if (iend > 0 && iend + 8 <= d.length) end = iend + 8;
      case 'webp':
        final riff = _u32le(d, start + 4);
        if (riff > 0 && start + 8 + riff <= d.length) end = start + 8 + riff;
      case 'gif':
        for (var i = d.length - 1; i > start; i--) {
          if (d[i] == 0x3B) {
            end = i + 1;
            break;
          }
        }
    }

    if (end <= start + 12) end = d.length;
    return Uint8List.sublistView(d, start, end);
  }

  static int _findMagic(Uint8List d, List<int> magic, {int from = 0}) {
    final max = d.length - magic.length;
    for (var i = from < 0 ? 0 : from; i <= max; i++) {
      var ok = true;
      for (var k = 0; k < magic.length; k++) {
        if (d[i + k] != magic[k]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  /// RIFF....WEBP
  /// 找 BMP：要求保留字段为 0、文件大小/像素偏移自洽
  static int _findBmp(Uint8List d) {
    for (var i = 0; i + 18 <= d.length; i++) {
      if (d[i] != 0x42 || d[i + 1] != 0x4D) continue;
      if (d[i + 6] != 0 || d[i + 7] != 0 || d[i + 8] != 0 || d[i + 9] != 0) continue;
      final size = d[i + 2] | (d[i + 3] << 8) | (d[i + 4] << 16) | (d[i + 5] << 24);
      if (size != d.length - i) continue; // 大小对不上就不是一张完整的图
      final off = d[i + 10] | (d[i + 11] << 8) | (d[i + 12] << 16) | (d[i + 13] << 24);
      if (off < 14 || off >= size) continue;
      return i;
    }
    return -1;
  }

  static int _findMagicRiff(Uint8List d) {
    for (var i = 0; i + 12 <= d.length; i++) {
      if (d[i] == 0x52 && d[i + 1] == 0x49 && d[i + 2] == 0x46 && d[i + 3] == 0x46 &&
          d[i + 8] == 0x57 && d[i + 9] == 0x45 && d[i + 10] == 0x42 && d[i + 11] == 0x50) {
        return i;
      }
    }
    return -1;
  }

  static int _u32le(Uint8List b, int p) =>
      (p + 4 <= b.length) ? (b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)) : 0;

  /// 判断一段字节的开头是不是真正的图片（用来校验已落盘的封面文件）
  static bool isImageHeader(Uint8List d) {
    if (d.length < 4) return false;
    if (d[0] == 0xFF && d[1] == 0xD8) return true; // JPEG
    if (d[0] == 0x89 && d[1] == 0x50 && d[2] == 0x4E && d[3] == 0x47) return true; // PNG
    if (d[0] == 0x47 && d[1] == 0x49 && d[2] == 0x46) return true; // GIF
    if (d.length > 12 && d[8] == 0x57 && d[9] == 0x45 && d[10] == 0x42) {
      return true; // WEBP
    }
    if (d.length >= 14 && d[0] == 0x42 && d[1] == 0x4D) {
      // BMP：保留位必须为 0、大小字段要合理，避免把垃圾当封面
      if (d[6] != 0 || d[7] != 0 || d[8] != 0 || d[9] != 0) return false;
      final size = d[2] | (d[3] << 8) | (d[4] << 16) | (d[5] << 24);
      return size > 1000;
    }
    return false;
  }

  /// 封面图片的扩展名（写缓存文件时用真实格式，避免解码器按文件名猜错）
  static String imageExt(Uint8List d) {
    if (d.length < 12) return 'img';
    if (d[0] == 0xFF && d[1] == 0xD8) return 'jpg';
    if (d[0] == 0x89 && d[1] == 0x50) return 'png';
    if (d[0] == 0x47 && d[1] == 0x49) return 'gif';
    if (d[0] == 0x42 && d[1] == 0x4D) return 'bmp';
    if (d.length > 12 && d[8] == 0x57 && d[9] == 0x45 && d[10] == 0x42) return 'webp';
    return 'img';
  }

  // ----------------------------------------------------------- Vorbis 注释
  static void _parseVorbisComment(Uint8List b, TagData t) {
    var p = 0;
    int u32() {
      final v = b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24);
      p += 4;
      return v;
    }

    try {
      final vendorLen = u32();
      p += vendorLen;
      final count = u32();
      for (var i = 0; i < count && p + 4 <= b.length; i++) {
        final len = u32();
        if (p + len > b.length) break;
        final s = utf8.decode(b.sublist(p, p + len), allowMalformed: true);
        p += len;
        final eq = s.indexOf('=');
        if (eq <= 0) continue;
        final k = s.substring(0, eq).toUpperCase();
        final v = s.substring(eq + 1).trim();
        switch (k) {
          case 'TITLE':
            t.title ??= v;
          case 'ARTIST':
            t.artist ??= v;
          case 'ALBUM':
            t.album ??= v;
          case 'DATE':
            t.year ??= int.tryParse(v.length >= 4 ? v.substring(0, 4) : v);
          case 'TRACKNUMBER':
            t.trackNo ??= int.tryParse(v.split('/').first.trim());
          case 'LYRICS':
          case 'UNSYNCEDLYRICS':
            t.lyrics ??= v;
          case 'METADATA_BLOCK_PICTURE':
            // OGG / FLAC(VORBIS_COMMENT 里的) 封面：整块做 base64
            if (t.artwork == null) {
              try {
                final raw = base64.decode(v.replaceAll(RegExp(r'\s'), ''));
                t.artwork = _flacPicture(raw, 0, raw.length);
              } catch (_) {}
            }
          case 'COVERART':
            // 老式 COVERART：直接是 base64 图片字节
            if (t.artwork == null) {
              try {
                t.artwork = _asImage(base64.decode(v.replaceAll(RegExp(r'\s'), '')));
              } catch (_) {}
            }
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- ID3v2
  static void _parseId3v2(Uint8List b, TagData t) {
    final ver = b[3];
    final flags = b[5];
    final size = _syncSafe(b, 6, 4);
    // 标签比读到的字节还长（大封面常见）→ 告诉调用方要读到哪
    if (10 + size > b.length) t.needBytes = 10 + size;

    // 整体去同步（ID3v2.2/2.3 的 flag 0x80）：FF 00 → FF。
    // 不去掉的话帧长度与实际字节错位，封面和文字都会解析成乱码/损坏。
    if ((flags & 0x80) != 0 && size > 0) {
      final end = (10 + size).clamp(0, b.length);
      final out = <int>[];
      for (var i = 10; i < end; i++) {
        out.add(b[i]);
        if (b[i] == 0xFF && i + 1 < end && b[i + 1] == 0x00) i++;
      }
      final clean = Uint8List.fromList(out);
      final wrapped = Uint8List(10 + clean.length)
        ..setRange(0, 10, b)
        ..setRange(10, 10 + clean.length, clean);
      _parseId3v2Frames(wrapped, ver, 0, clean.length, t);
      return;
    }
    _parseId3v2Frames(b, ver, flags, size, t);
  }

  static void _parseId3v2Frames(
      Uint8List b, int ver, int flags, int size, TagData t) {
    var p = 10;
    if ((flags & 0x40) != 0) {
      // 扩展头：v2.4 的 size 含自身；v2.3 的 size 不含自身（前面还有 4 字节）
      if (ver >= 4) {
        p += _syncSafe(b, p, 4);
      } else {
        p += 4 + _u32be(b, p);
      }
    }
    final end = (10 + size).clamp(0, b.length);

    if (ver <= 2) {
      _parseId3v2Old(b, p, end, t);
      return;
    }

    Uint8List? bestArt;

    while (p + 10 <= end) {
      final id = latin1.decode(b.sublist(p, p + 4));
      if (id.trim().isEmpty || !RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) {
        // 帧头坏了：往后找下一个认识的帧，而不是直接放弃后面所有帧
        final next = _nextFrame(b, p + 1, end, ver);
        if (next < 0) break;
        p = next;
        continue;
      }
      final frameSize = ver >= 4 ? _syncSafe(b, p + 4, 4) : _u32be(b, p + 4);
      if (frameSize <= 0 || p + 10 + frameSize > end) {
        final next = _nextFrame(b, p + 1, end, ver);
        if (next < 0) break;
        p = next;
        continue;
      }
      var bodyStart = p + 10;
      var bodyLen = frameSize;
      // v2.3/2.4 帧头后 2 字节是标志位：压缩 0x0080/0x0009、加密 0x0040/0x0004、
      // data-length-indicator 0x0001（v2.4）。带 DLI 时正文前多 4 字节长度要跳过，
      // 否则 APIC 会从长度字段开始解析，封面直接坏掉。
      if (ver >= 3 && frameSize > 4) {
        final f2 = (b[p + 8] << 8) | b[p + 9];
        final dli = ver >= 4 ? (f2 & 0x0001) != 0 : (f2 & 0x0080) != 0;
        final encrypted = ver >= 4 ? (f2 & 0x0004) != 0 : (f2 & 0x0040) != 0;
        if (encrypted) {
          p += 10 + frameSize;
          continue;
        }
        if (dli) {
          bodyStart += 4;
          bodyLen -= 4;
        }
      }
      if (bodyLen <= 0 || bodyStart + bodyLen > end) {
        p += 10 + frameSize;
        continue;
      }
      final body = b.sublist(bodyStart, bodyStart + bodyLen);

      switch (id) {
        case 'TIT2':
          t.title ??= _id3Text(body);
        case 'TPE1':
          t.artist ??= _id3Text(body);
        case 'TALB':
          t.album ??= _id3Text(body);
        case 'TYER':
          t.year ??= int.tryParse(_id3Text(body));
        case 'TRCK':
          t.trackNo ??= int.tryParse(_id3Text(body).split('/').first.trim());
        case 'USLT':
          t.lyrics ??= _id3Lyrics(body);
        case 'TDRC':
          final s = _id3Text(body);
          t.year ??= int.tryParse(s.length >= 4 ? s.substring(0, 4) : s);
        case 'TLEN':
          // 时长（毫秒）：MP3 头里没有总时长，有这帧最省事
          final v = int.tryParse(_id3Text(body));
          if (v != null && v > 0) {
            t.duration ??= Duration(milliseconds: v);
          }
        case 'APIC':
          // 多张封面时保留最大的那张（很多文件第一张是 1x1 占位图）
          final pic = _id3Artwork(body);
          if (pic != null && (bestArt == null || pic.length > bestArt.length)) {
            bestArt = pic;
          }
      }
      p += 10 + frameSize;
    }
    if (bestArt != null && t.artwork == null) t.artwork = bestArt;
  }

  /// 已知的 ID3 帧名：用于坏帧之后重新对齐
  static const _knownFrames = {
    'TIT2', 'TPE1', 'TPE2', 'TALB', 'TYER', 'TDRC', 'TRCK', 'TPOS', 'TCON',
    'APIC', 'USLT', 'COMM', 'TCOM', 'TLEN', 'TSRC', 'TPUB', 'TBPM', 'TXXX',
  };

  static int _nextFrame(Uint8List b, int from, int end, int ver) {
    for (var i = from; i + 10 <= end; i++) {
      final id = latin1.decode(b.sublist(i, i + 4));
      if (!_knownFrames.contains(id)) continue;
      final size = ver >= 4 ? _syncSafe(b, i + 4, 4) : _u32be(b, i + 4);
      if (size > 0 && i + 10 + size <= end) return i;
    }
    return -1;
  }

  /// ID3v2.2（老格式）：3 字节帧名 + 3 字节帧长
  static void _parseId3v2Old(Uint8List b, int p, int end, TagData t) {
    while (p + 6 <= end) {
      final id = latin1.decode(b.sublist(p, p + 3));
      if (!RegExp(r'^[A-Z0-9]{3}$').hasMatch(id)) break;
      final frameSize = (b[p + 3] << 16) | (b[p + 4] << 8) | b[p + 5];
      if (frameSize <= 0 || p + 6 + frameSize > end) break;
      final body = b.sublist(p + 6, p + 6 + frameSize);

      switch (id) {
        case 'TT2':
          t.title ??= _id3Text(body);
        case 'TP1':
          t.artist ??= _id3Text(body);
        case 'TAL':
          t.album ??= _id3Text(body);
        case 'TYE':
          t.year ??= int.tryParse(_id3Text(body));
        case 'TRK':
          t.trackNo ??= int.tryParse(_id3Text(body).split('/').first.trim());
        case 'ULT':
          t.lyrics ??= _id3Lyrics(body);
        case 'TLE':
          // ID3v2.2 的时长帧，同样是毫秒
          final v = int.tryParse(_id3Text(body));
          if (v != null && v > 0) {
            t.duration ??= Duration(milliseconds: v);
          }
        case 'PIC':
          // v2.2 也有内嵌封面，之前完全没解析
          final pic = _id3v22Artwork(body);
          if (pic != null && t.artwork == null) t.artwork = pic;
      }
      p += 6 + frameSize;
    }
  }

  /// USLT：编码 + 语言(3) + 描述(以 0 结束) + 歌词正文
  static String? _id3Lyrics(Uint8List body) {
    if (body.length < 5) return null;
    final enc = body[0];
    var i = 4;
    if (enc == 1 || enc == 2) {
      while (i + 1 < body.length) {
        if (body[i] == 0 && body[i + 1] == 0) {
          i += 2;
          break;
        }
        i += 2;
      }
    } else {
      while (i < body.length && body[i] != 0) {
        i++;
      }
      i++;
    }
    if (i >= body.length) return null;
    final data = body.sublist(i);
    try {
      final text = switch (enc) {
        1 => _decodeUtf16(data),
        2 => _decodeUtf16(data, bigEndian: true),
        3 => utf8.decode(data, allowMalformed: true),
        _ => latin1.decode(data),
      };
      final v = text.replaceAll('\x00', '').trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static String _id3Text(Uint8List body) {
    if (body.isEmpty) return '';
    final enc = body[0];
    final data = body.sublist(1);
    try {
      switch (enc) {
        case 1: // UTF-16 with BOM
          return _decodeUtf16(data);
        case 2: // UTF-16BE
          return _decodeUtf16(data, bigEndian: true);
        case 3: // UTF-8
          return utf8.decode(data, allowMalformed: true).replaceAll('\x00', '');
        default: // ISO-8859-1
          return latin1.decode(data).replaceAll('\x00', '');
      }
    } catch (_) {
      return '';
    }
  }

  static String _decodeUtf16(Uint8List data, {bool bigEndian = false}) {
    var d = data;
    if (d.length >= 2) {
      if (d[0] == 0xFE && d[1] == 0xFF) {
        bigEndian = true;
        d = d.sublist(2);
      } else if (d[0] == 0xFF && d[1] == 0xFE) {
        bigEndian = false;
        d = d.sublist(2);
      }
    }
    final units = <int>[];
    for (var i = 0; i + 1 < d.length; i += 2) {
      units.add(bigEndian ? (d[i] << 8) | d[i + 1] : d[i] | (d[i + 1] << 8));
    }
    return String.fromCharCodes(units).replaceAll('\x00', '');
  }

  /// APIC：编码(1) + mime(0 结尾) + 图片类型(1) + 描述(按编码 0 结尾) + 图片数据
  ///
  /// 标准解析拿不到就退化成「整段找图片魔数」——现实里很多文件
  /// mime 长度、描述结束符都是错的，之前这些封面全被判成没有。
  static Uint8List? _id3Artwork(Uint8List body) {
    if (body.isEmpty) return null;
    try {
      final enc = body[0];
      var i = 1;
      while (i < body.length && body[i] != 0) {
        i++;
      }
      i++; // 跳过 mime 的 0
      i++; // picture type
      if (enc == 1 || enc == 2) {
        while (i + 1 < body.length && !(body[i] == 0 && body[i + 1] == 0)) {
          i += 2;
        }
        i += 2;
      } else {
        while (i < body.length && body[i] != 0) {
          i++;
        }
        i++;
      }
      if (i < body.length) {
        final img = _asImage(Uint8List.sublistView(body, i));
        if (img != null) return img;
      }
    } catch (_) {}
    return _sliceImage(body.length > 1 ? Uint8List.sublistView(body, 1) : body);
  }

  /// ID3v2.2 的 PIC 帧：编码(1) + 图片格式(3，如 JPG/PNG) + 类型(1) + 描述 + 数据
  static Uint8List? _id3v22Artwork(Uint8List body) {
    if (body.length < 6) return null;
    try {
      final enc = body[0];
      var i = 5; // enc + 3 字节格式 + 类型
      if (enc == 1 || enc == 2) {
        while (i + 1 < body.length && !(body[i] == 0 && body[i + 1] == 0)) {
          i += 2;
        }
        i += 2;
      } else {
        while (i < body.length && body[i] != 0) {
          i++;
        }
        i++;
      }
      if (i < body.length) {
        final img = _asImage(Uint8List.sublistView(body, i));
        if (img != null) return img;
      }
    } catch (_) {}
    return _sliceImage(body.length > 4 ? Uint8List.sublistView(body, 4) : body);
  }

  /// 整段字节里找图（要求 >= 4KB，且必须是**完整**的图）。
  ///
  /// 「完整」这条很关键：只读到窗口里的前半张图时，写进缓存只会显示成灰块，
  /// 还不如当作没有封面，交给后续的放大窗口重读去处理。
  static Uint8List? _rawArtwork(Uint8List b) {
    final img = _sliceImage(b);
    if (img == null || img.length < 4096) return null;

    if (img[0] == 0xFF && img[1] == 0xD8) {
      // JPEG 必须有 EOI 收尾
      final ok = img.length > 2 &&
          img[img.length - 2] == 0xFF &&
          img[img.length - 1] == 0xD9;
      return ok ? img : null;
    }
    if (img[0] == 0x89 && img[1] == 0x50) {
      // PNG 必须有 IEND
      final ok = _findMagic(img, const [0x49, 0x45, 0x4E, 0x44]) > 0;
      return ok ? img : null;
    }
    // 其余格式（BMP / GIF）不做「盲找」：在标签字节里太容易误命中
    return null;
  }

  // ---------------------------------------------------------------- MP3
  /// MP3 的文件头里没有「总时长」字段，只能从音频帧反推。
  /// 以前完全没做这一步，所以 MP3 一律显示不出时长。
  ///
  /// 三级取值：
  /// 1) ID3 的 TLEN 帧（毫秒）—— 最省事，已被上面解析过；
  /// 2) 第一帧里的 Xing / Info / VBRI 头，直接给了总帧数，VBR 也准；
  /// 3) 都没有就按「音频字节数 ÷ 首帧码率」估算（CBR 足够准）。
  static void _parseMp3Audio(Uint8List b, TagData t, int? fileSize) {
    var start = 0;
    if (_startsWith(b, 'ID3') && b.length >= 10) {
      final skip = _syncSafe(b, 6, 4) + 10;
      if (skip > 0 && skip < b.length) start = skip;
    }

    // 从标签结束处往后找第一个合法帧头（ID3 后面通常就是第一帧）
    final limit = b.length < start + 512 * 1024 ? b.length : start + 512 * 1024;
    for (var i = start; i + 4 <= limit; i++) {
      if (b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) continue;
      if (_readMp3Frame(b, i, t, fileSize)) return;
    }
  }

  /// 把 [i] 处当一个 MPEG 音频帧头来读；读成了就把时长 / 码率写进 [t]
  static bool _readMp3Frame(Uint8List b, int i, TagData t, int? fileSize) {
    final verBits = (b[i + 1] >> 3) & 0x03;
    final layerBits = (b[i + 1] >> 1) & 0x03;
    if (verBits == 1 || layerBits == 0) return false; // 保留值，不是帧头

    final mpeg1 = verBits == 3;
    final layer = 4 - layerBits; // 3→Layer1  2→Layer2  1→Layer3
    final brIdx = (b[i + 2] >> 4) & 0x0F;
    final srIdx = (b[i + 2] >> 2) & 0x03;
    if (brIdx == 0 || brIdx == 15 || srIdx == 3) return false;

    final kbps = _mp3Bitrate(mpeg1, layer, brIdx);
    final hz = _mp3SampleRate(verBits, srIdx);
    if (kbps == null || hz == null) return false;
    final spf = _mp3SamplesPerFrame(mpeg1, layer);

    final mono = ((b[i + 3] >> 6) & 0x03) == 3;
    // 保护位为 0 时，帧头后面还跟着 2 字节 CRC
    final crcBytes = (b[i + 1] & 0x01) == 0 ? 2 : 0;

    t.sampleRate ??= hz;
    t.bitrateKbps ??= kbps;
    t.channels ??= mono ? 1 : 2;

    // ---- Xing / Info：常见 VBR/CBR 头，含总帧数或总字节数 ----
    final xoff =
        i + 4 + crcBytes + (mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17));
    if (xoff + 16 <= b.length &&
        (_startsAt(b, xoff, 'Xing') || _startsAt(b, xoff, 'Info'))) {
      final flags = _u32be(b, xoff + 4);
      if ((flags & 0x01) != 0) {
        final frames = _u32be(b, xoff + 8);
        if (frames > 0) {
          t.duration ??=
              Duration(milliseconds: (frames * spf * 1000 / hz).round());
          return true;
        }
      }
      if ((flags & 0x02) != 0) {
        final bytes = _u32be(b, xoff + 12);
        if (bytes > 0) {
          // bytes × 8 = 总比特数，÷ kbps 直接得毫秒
          t.duration ??= Duration(milliseconds: (bytes * 8 / kbps).round());
          return true;
        }
      }
    }

    // ---- VBRI：Fraunhofer 编码器的 VBR 头，位置固定在帧头后 32 字节 ----
    final voff = i + 4 + 32;
    if (voff + 18 <= b.length && _startsAt(b, voff, 'VBRI')) {
      final frames = _u32be(b, voff + 14);
      if (frames > 0) {
        t.duration ??=
            Duration(milliseconds: (frames * spf * 1000 / hz).round());
        return true;
      }
    }

    // ---- 兜底：CBR 估算（音频字节 ÷ 首帧码率）----
    if (fileSize != null && fileSize > i && kbps > 0) {
      t.duration ??= Duration(milliseconds: ((fileSize - i) * 8 / kbps).round());
      return true;
    }
    return false;
  }

  static int? _mp3Bitrate(bool mpeg1, int layer, int idx) {
    const m1l1 = [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448];
    const m1l2 = [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384];
    const m1l3 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
    const m2l1 = [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256];
    const m2l23 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
    final list = mpeg1
        ? (layer == 1 ? m1l1 : layer == 2 ? m1l2 : m1l3)
        : (layer == 1 ? m2l1 : m2l23);
    if (idx < 0 || idx >= list.length) return null;
    return list[idx];
  }

  static int? _mp3SampleRate(int verBits, int idx) {
    const m1 = [44100, 48000, 32000];
    const m2 = [22050, 24000, 16000];
    const m25 = [11025, 12000, 8000]; // MPEG2.5
    final list = verBits == 3 ? m1 : verBits == 2 ? m2 : m25;
    if (idx < 0 || idx >= list.length) return null;
    return list[idx];
  }

  static int _mp3SamplesPerFrame(bool mpeg1, int layer) {
    if (layer == 1) return 384;
    if (layer == 2) return 1152;
    return mpeg1 ? 1152 : 576; // Layer III
  }

  // ------------------------------------------------------------------ OGG
  static void _parseOgg(Uint8List b, TagData t) {
    final text = latin1.decode(b);
    final vi = text.indexOf('\x01vorbis');
    if (vi >= 0 && vi + 16 < b.length) {
      t.channels = b[vi + 11];
      t.sampleRate = b[vi + 12] | (b[vi + 13] << 8) | (b[vi + 14] << 16) | (b[vi + 15] << 24);
    }
    final ci = text.indexOf('\x03vorbis');
    if (ci >= 0) {
      final start = ci + 7;
      if (start < b.length) _parseVorbisComment(Uint8List.sublistView(b, start), t);
    }
  }

  // ------------------------------------------------------------------ WAV
  static void _parseWav(Uint8List b, TagData t) {
    var i = 12;
    while (i + 8 <= b.length) {
      final id = latin1.decode(b.sublist(i, i + 4));
      final len = b[i + 4] | (b[i + 5] << 8) | (b[i + 6] << 16) | (b[i + 7] << 24);
      final start = i + 8;
      if (len < 0 || start + len > b.length) break;

      if (id == 'fmt ' && len >= 16) {
        t.channels = b[start + 2] | (b[start + 3] << 8);
        t.sampleRate = b[start + 4] | (b[start + 5] << 8) | (b[start + 6] << 16) | (b[start + 7] << 24);
        t.bitsPerSample = b[start + 14] | (b[start + 15] << 8);
      } else if (id == 'LIST') {
        final chunk = latin1.decode(b.sublist(start, start + len));
        t.title ??= _riffField(chunk, 'INAM');
        t.artist ??= _riffField(chunk, 'IART');
        t.album ??= _riffField(chunk, 'IPRD');
      }
      i = start + len + (len.isOdd ? 1 : 0);
    }
  }

  static String? _riffField(String chunk, String key) {
    final i = chunk.indexOf(key);
    if (i < 0 || i + 8 > chunk.length) return null;
    final len = chunk.codeUnitAt(i + 4) |
        (chunk.codeUnitAt(i + 5) << 8) |
        (chunk.codeUnitAt(i + 6) << 16) |
        (chunk.codeUnitAt(i + 7) << 24);
    if (len <= 0 || i + 8 + len > chunk.length) return null;
    return chunk.substring(i + 8, i + 8 + len).trim();
  }

  // ------------------------------------------------------------------ MP4
  static bool _isMp4(Uint8List b) =>
      b.length > 12 && latin1.decode(b.sublist(4, 8)) == 'ftyp';

  static void _parseMp4(Uint8List b, TagData t) {
    for (var i = 0; i + 8 <= b.length; i++) {
      final atom = latin1.decode(b.sublist(i, i + 4));
      if (atom != '©nam' &&
          atom != '©ART' &&
          atom != '©alb' &&
          atom != '©day' &&
          atom != '©lyr' &&
          atom != 'covr') {
        continue;
      }
      // atom 结构：[4字节atom大小]['©nam']['data'原子：4大小 + 'data' + 4类型 + 4locale + 内容]
      final di = _indexOf(b, 'data', i + 4, limit: 48);
      if (di < 0) continue;
      final dataSize = _u32be(b, di - 4); // data 原子的 size 字段在 'data' 前面
      if (dataSize < 16 || di - 4 + dataSize > b.length) continue;
      final typeCode = _u32be(b, di + 4);
      final start = di + 12;
      final end = di - 4 + dataSize;

      if (atom == 'covr') {
        // 封面：typeCode 名义上 13=JPEG / 14=PNG，但不少编码器写 0 或 BMP，
        // 所以按字节特征判断真实格式，避免误判导致封面丢失
        if (t.artwork == null && end > start) {
          t.artwork = _asImage(Uint8List.sublistView(b, start, end));
        }
        continue;
      }
      // 文本：typeCode 1 = UTF-8，2 = UTF-16
      String value;
      try {
        value = typeCode == 2
            ? _decodeUtf16(Uint8List.sublistView(b, start, end))
            : utf8.decode(Uint8List.sublistView(b, start, end), allowMalformed: true);
      } catch (_) {
        continue;
      }
      value = value.trim();
      if (value.isEmpty) continue;
      switch (atom) {
        case '©nam':
          t.title ??= value;
        case '©ART':
          t.artist ??= value;
        case '©alb':
          t.album ??= value;
        case '©day':
          t.year ??= int.tryParse(value.length >= 4 ? value.substring(0, 4) : value);
        case '©lyr':
          t.lyrics ??= value;
      }
    }
  }

  // ------------------------------------------------------------------ APEv2
  /// APE 标签在文件尾（MAC 必有，个别 MP3 也有）：'APETAGEX' 头 + 若干条目
  static void _parseApe(Uint8List b, TagData t) {
    final h = _indexOf(b, 'APETAGEX', 0, limit: b.length);
    if (h < 0 || h + 32 > b.length) return;
    final count = b[h + 12] | (b[h + 13] << 8) | (b[h + 14] << 16) | (b[h + 15] << 24);
    var p = h + 32;
    for (var i = 0; i < count && p + 8 <= b.length; i++) {
      final size = b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24);
      if (size <= 0 || p + 8 + size > b.length) break;
      final raw = b.sublist(p + 8, p + 8 + size);
      final z = raw.indexOf(0);
      if (z <= 0) break;
      final key = latin1.decode(raw.sublist(0, z)).toUpperCase();
      final value = utf8.decode(raw.sublist(z + 1), allowMalformed: true).trim();
      switch (key) {
        case 'TITLE':
          t.title ??= value;
        case 'ARTIST':
          t.artist ??= value;
        case 'ALBUM':
          t.album ??= value;
        case 'YEAR':
          t.year ??= int.tryParse(value.length >= 4 ? value.substring(0, 4) : value);
        case 'TRACK':
          t.trackNo ??= int.tryParse(value.split('/').first.trim());
        case 'LYRICS':
        case 'UNSYNCEDLYRICS':
          t.lyrics ??= value;
      }
      p += 8 + size;
    }
  }

  /// DSF：文件头 20..27 字节是 ID3v2 块的文件内偏移（u64LE）
  static int? dsfId3Offset(Uint8List head) {
    if (head.length < 28 || !_startsWith(head, 'DSD ')) return null;
    var off = 0;
    for (var i = 27; i >= 20; i--) {
      off = (off << 8) | head[i];
    }
    return off <= 0 ? null : off;
  }

  /// FLAC：VORBIS_COMMENT 块（type 4）是否被窗口截断。
  /// 截断时返回「完整读到该块需要的字节数」，完整或没找到返回 null。
  /// FLAC 里第一个 PICTURE 块的结束偏移（块被窗口截断时用来补读）
  static int? flacPictureEnd(Uint8List b) {
    var i = 4;
    while (i + 4 <= b.length) {
      final header = b[i];
      final type = header & 0x7F;
      final len = (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      final start = i + 4;
      if (type == 6) return start + len;
      if ((header & 0x80) != 0) return null;
      if (start + len > b.length) return null;
      i = start + len;
    }
    return null;
  }

  static int? flacCommentEnd(Uint8List b) {
    var i = 4;
    while (i + 4 <= b.length) {
      final header = b[i];
      final type = header & 0x7F;
      final len = (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      final start = i + 4;
      if (type == 4) return start + len; // 是不是被截断由调用方判断
      if ((header & 0x80) != 0) return null;
      i = start + len;
    }
    return null;
  }

  /// 用第二份解析结果补齐第一份里缺失的字段（DSF 分段读取等场景）
  static void mergeInto(TagData base, TagData extra) {
    base.format ??= extra.format;
    base.title ??= extra.title;
    base.artist ??= extra.artist;
    base.album ??= extra.album;
    base.year ??= extra.year;
    base.trackNo ??= extra.trackNo;
    base.duration ??= extra.duration;
    base.sampleRate ??= extra.sampleRate;
    base.bitsPerSample ??= extra.bitsPerSample;
    base.channels ??= extra.channels;
    base.bitrateKbps ??= extra.bitrateKbps;
    base.artwork ??= extra.artwork;
    base.lyrics ??= extra.lyrics;
  }

  // ---------------------------------------------------------------- 工具
  /// 在 [from, from+limit) 范围内找 needle，找不到返回 -1
  static int _indexOf(Uint8List b, String needle, int from, {int limit = 4096}) {
    final end = (from + limit).clamp(0, b.length - needle.length);
    for (var i = from; i <= end; i++) {
      var ok = true;
      for (var k = 0; k < needle.length; k++) {
        if (b[i + k] != needle.codeUnitAt(k)) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  static bool _startsWith(Uint8List b, String s) {
    if (b.length < s.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (b[i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// 从 [at] 开始是不是 s（_startsWith 只允许从 0 开始）
  static bool _startsAt(Uint8List b, int at, String s) {
    if (at < 0 || at + s.length > b.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (b[at + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _u32be(Uint8List b, int i) {
    if (i + 4 > b.length) return 0;
    return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  }

  /// ID3v2 用的 7 位同步安全整数
  static int syncSafe(Uint8List b, int i, int n) {
    var v = 0;
    for (var k = 0; k < n; k++) {
      v = (v << 7) | (b[i + k] & 0x7F);
    }
    return v;
  }

  static int _syncSafe(Uint8List b, int i, int n) => syncSafe(b, i, n);
}
