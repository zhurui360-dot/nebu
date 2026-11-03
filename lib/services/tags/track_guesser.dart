import 'tag_reader.dart';

class TrackGuess {
  const TrackGuess({
    required this.title,
    this.artist,
    this.album,
    this.trackNo,
    this.year,
  });

  final String title;
  final String? artist;
  final String? album;
  final int? trackNo;
  final int? year;
}

/// 根据「文件名 + 所在目录」智能识别歌名、歌手、专辑。
///
/// 优先级：内嵌标签 > 文件名 > 目录结构。
/// 真实音乐库里的脏命名都要能吃：
///   01. 周杰伦 - 晴天.flac
///   周杰伦 - 叶惠美 - 01 - 晴天.mp3
///   网易云音乐 - 晴天 - 周杰伦.mp3
///   周杰伦_晴天.mp3
///   周杰伦《叶惠美》晴天.mp3
///   晴天 - 周杰伦 (Live版).mp3
class TrackGuesser {
  /// 用户自定义的文件名模板，例如 `{artist} - {title}`。
  ///
  /// 空字符串 = 智能识别（默认，按目录/文件名/平台前后缀打分）。
  /// AppState 启动时把持久化的值塞进来，扫描时直接用。
  static String pattern = '';

  /// 模板里能用的占位符
  static const tokens = ['artist', 'title', 'album', 'track'];

  /// 用户自定义的「间隔符号」集合（默认横线/下划线/间隔号）。
  /// 模板里写这些字符时，匹配会放宽成「这一组里任意一个都算」，
  /// 例如模板 `{artist} - {title}` 能同时吃 `周杰伦-晴天`、`周杰伦_晴天`。
  static String separators = '-–—_·';

  /// 这些目录名不当作歌手/专辑
  static const _noiseDirs = {
    '音乐', 'music', 'musics', '歌曲', '我的音乐', 'audio', 'audios',
    '下载', 'downloads', 'download', '未分类', '未知', '其他', '其它',
    'ost', '原声', 'soundtrack', 'albums', 'album', '新建文件夹', 'temp',
    '手机', '本地', 'local',
  };

  /// 方括号/圆括号里出现这些词，是格式标记而非歌名
  static const _formatTags = {
    'flac', 'ape', 'wav', 'mp3', 'aac', 'm4a', 'ogg', 'dsf', 'dff', 'alac',
    'hi-res', 'hires', 'hq', 'sq', '无损', '高音质', '24bit', '16bit',
    'dsd', 'dsd64', 'dsd128', '320k', '128k', '192k', '256k', '320kbps',
    'cue', 'web', 'cd', 'vinyl', 'mqms2', 'wqdy', 'kg', 'kw', 'ne',
  };

  /// 各大平台下载文件时加的前后缀
  static const _siteTags = {
    '网易云音乐', '酷狗音乐', 'qq音乐', '酷我音乐', '咪咕音乐', '虾米音乐',
    'music', 'qqmusic', 'kugou', 'kuwo', 'netease', 'xiami',
  };

  static TrackGuess guess({
    required String fileName,
    required String path,
    TagData? tag,
  }) {
    final dirs = _dirsOf(path);

    // ---------- 1. 清洗文件名 ----------
    final prepared = _prepare(fileName);
    var base = prepared.base;

    // ---------- 2. 用户模板优先（给了模板就按模板切） ----------
    final custom = _fromPattern(prepared);

    // ---------- 3. 没给模板/没匹配上：走智能识别 ----------
    String? bookAlbum;
    var picked = (title: null, artist: null, album: null) as ({String? title, String? artist, String? album});
    if (custom == null) {
      final bm = RegExp('《([^》]+)》').firstMatch(base);
      if (bm != null) {
        bookAlbum = _clean(bm.group(1));
        base = base.replaceAll(bm.group(0)!, ' - ');
      }
      base = base.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

      final segs = _splitSegments(base);
      picked = _classify(segs, dirs, tag?.artist);
    }

    // ---------- 4. 目录兜底 ----------
    String? dirAlbum;
    String? dirArtist;
    if (dirs.isNotEmpty) {
      final last = dirs.last;
      if (!_isNoise(last)) dirAlbum = last;
      if (dirs.length >= 2) {
        final prev = dirs[dirs.length - 2];
        if (!_isNoise(prev) && prev != dirAlbum) dirArtist = prev;
      }
    }

    final title = _clean(tag?.title) ??
        custom?.title ??
        picked.title ??
        _clean(base) ??
        '未知歌曲';
    var artist =
        _clean(tag?.artist) ?? custom?.artist ?? picked.artist ?? dirArtist;
    var album = _clean(tag?.album) ??
        custom?.album ??
        picked.album ??
        bookAlbum ??
        dirAlbum;

    if (artist != null && album != null && artist == album) {
      artist = picked.artist ?? custom?.artist ?? dirArtist;
    }
    if (artist != null && artist == title) {
      artist = dirArtist ?? picked.artist ?? custom?.artist;
    }

    return TrackGuess(
      title: title,
      artist: _cleanArtist(artist),
      album: album,
      trackNo: custom?.trackNo ?? tag?.trackNo ?? prepared.trackNo,
      year: tag?.year,
    );
  }

  /// 设置页的实时预览：文件名 → 按当前模板切出来的结果（没匹配返回 null）
  static TrackGuess? preview(String fileName) {
    final prepared = _prepare(fileName);
    final c = _fromPattern(prepared);
    if (c == null) return null;
    return TrackGuess(
      title: _clean(c.title) ?? '未知歌曲',
      artist: _cleanArtist(c.artist),
      album: _clean(c.album),
      trackNo: c.trackNo,
    );
  }

  /// 去掉扩展名 / 平台前后缀 / 格式标记 / 开头序号
  static ({String raw, String base, int? trackNo}) _prepare(String fileName) {
    var raw = _stripExtension(fileName);
    raw = _stripSiteAffixes(raw);
    raw = _stripFormatTags(raw);
    final no = _leadingTrackNo(raw);
    final base = no != null ? _stripLeadingTrackNo(raw) : raw;
    return (raw: raw.trim(), base: base.trim(), trackNo: no);
  }

  /// 把 `{artist} - {title}` 这样的模板编译成正则去切文件名。
  ///
  /// 分隔符放宽：模板里写 ` - ` 时，`-`、`–`、`—`、`_`、`·` 都算命中，
  /// 空格可有可无——真实文件里的写法从来不会完全一致。
  static ({String? title, String? artist, String? album, int? trackNo})?
      _fromPattern(({String raw, String base, int? trackNo}) prepared) {
    final tpl = pattern.trim();
    if (tpl.isEmpty) return null;
    // 模板里写了 {track} → 先用带序号的原文匹配，否则用去掉序号的版本
    if (tpl.contains('{track}')) {
      return _match(tpl, prepared.raw) ?? _match(tpl, prepared.base);
    }
    return _match(tpl, prepared.base) ?? _match(tpl, prepared.raw);
  }

  /// 用指定的模板去切（设置页做实时预览用，不影响全局 pattern）
  static TrackGuess? previewWith(String tpl, String fileName) {
    final prepared = _prepare(fileName);
    final c = tpl.contains('{track}')
        ? (_match(tpl, prepared.raw) ?? _match(tpl, prepared.base))
        : (_match(tpl, prepared.base) ?? _match(tpl, prepared.raw));
    if (c == null) return null;
    return TrackGuess(
      title: _clean(c.title) ?? '未知歌曲',
      artist: _cleanArtist(c.artist),
      album: _clean(c.album),
      trackNo: c.trackNo,
    );
  }

  static ({String? title, String? artist, String? album, int? trackNo})?
      _match(String tpl0, String base) {
    final tpl = tpl0.trim();
    if (tpl.isEmpty) return null;

    final rx = RegExp(r'\{(\w+)\}');
    final matches = rx.allMatches(tpl).toList();
    if (matches.isEmpty) return null;

    final buf = StringBuffer('^');
    final order = <String>[];
    var i = 0;
    for (final m in matches) {
      buf.write(_literalToRegex(tpl.substring(i, m.start)));
      final key = m.group(1)!.toLowerCase();
      order.add(key);
      buf.write(key == 'track' ? r'(\d{1,3})' : r'(.+?)');
      i = m.end;
    }
    buf.write(_literalToRegex(tpl.substring(i)));
    buf.write(r'$');

    final m = RegExp(buf.toString(), caseSensitive: false).firstMatch(base.trim());
    if (m == null) return null;

    String? pick(String key) {
      final idx = order.indexOf(key);
      if (idx < 0) return null;
      return _clean(m.group(idx + 1));
    }

    final trackRaw = order.contains('track')
        ? int.tryParse(m.group(order.indexOf('track') + 1) ?? '')
        : null;

    final artist = pick('artist');
    final title = pick('title');
    // 只写了 {artist} 一个占位符的话，剩下的整段就是歌名
    if (title == null && artist != null && base.trim() != artist) {
      final rest = base.trim().replaceFirst(RegExp(RegExp.escape(artist)), '').trim();
      final cleaned = _clean(rest.replaceAll(RegExp(r'^[-–—_·\s]+'), ''));
      if (cleaned != null) {
        return (
          title: cleaned,
          artist: artist,
          album: pick('album'),
          trackNo: trackRaw,
        );
      }
    }

    if (artist == null && title == null && pick('album') == null) return null;
    return (
      title: title,
      artist: artist,
      album: pick('album'),
      trackNo: trackRaw,
    );
  }

  /// 模板里的普通文字 → 宽松正则
  static String _literalToRegex(String lit) {
    if (lit.isEmpty) return '';
    // 间隔符号字符集：用户可以在设置里自定义（比如加上 . / +）
    final seps = separators.isEmpty ? '-–—_·' : separators;
    final sepClass = '[${RegExp.escape(seps)}]';
    final sb = StringBuffer();
    for (final ch in lit.split('')) {
      if (seps.contains(ch)) {
        // 模板里出现任意一个间隔符号 → 这一组任意符号都算命中
        sb.write('\\s*$sepClass\\s*');
      } else if (ch == ' ' || ch == '\t') {
        sb.write(r'\s*');
      } else if (RegExp(r'[.\\+*?\[\]^$(){}|]').hasMatch(ch)) {
        sb.write('\\$ch');
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  // ------------------------------------------------------------------
  static ({String? title, String? artist, String? album}) _classify(
    List<String> segs,
    List<String> dirs,
    String? tagArtist,
  ) {
    // 去掉噪声段：纯序号、站点名、格式词
    final usable = segs.where((s) {
      final t = s.trim();
      if (t.isEmpty) return false;
      if (RegExp(r'^\d{1,3}$').hasMatch(t)) return false;
      if (_isSiteTag(t)) return false;
      return true;
    }).toList();

    if (usable.isEmpty) return (title: null, artist: null, album: null);
    if (usable.length == 1) return (title: usable.first, artist: null, album: null);

    // 打分选歌手：命中目录 > 命中标签歌手 > 更像人名（短）
    var bestIdx = 0;
    var bestScore = -999;
    for (var i = 0; i < usable.length; i++) {
      final s = usable[i];
      var score = 0;
      for (final d in dirs) {
        if (d.isEmpty || _isNoise(d)) continue;
        if (s == d) score += 20;
        if (d.length >= 2 && s.contains(d)) score += 10;
      }
      if (tagArtist != null && tagArtist.isNotEmpty && s.contains(tagArtist)) score += 30;
      if (s.length <= 6) score += 3;
      if (i == 0) score += 1;
      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }

    final artist = usable[bestIdx];

    // 歌名取剩下的最长一段；专辑取命中专辑目录的那段
    String? title;
    String? album;
    var titleLen = -1;
    for (var i = 0; i < usable.length; i++) {
      if (i == bestIdx) continue;
      final s = usable[i];
      final isAlbumDir = dirs.any((d) => d.isNotEmpty && !_isNoise(d) && d == s);
      if (isAlbumDir && album == null) {
        album = s;
        continue;
      }
      if (s.length > titleLen) {
        titleLen = s.length;
        title = s;
      }
    }
    if (title == null && usable.length >= 2) {
      title = usable.firstWhere((s) => s != artist, orElse: () => usable.last);
    }

    return (title: title, artist: artist, album: album);
  }

  // ---------- 工具 ----------
  static List<String> _dirsOf(String path) {
    final segs = path.split('/').where((s) => s.trim().isNotEmpty).toList();
    if (segs.isEmpty) return const [];
    segs.removeLast();
    return segs;
  }

  static bool _isNoise(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    return v.isEmpty || _noiseDirs.contains(v);
  }

  static bool _isSiteTag(String s) {
    return _siteTags.contains(s.trim().toLowerCase());
  }

  static String? _clean(String? s) {
    final v = s?.trim();
    if (v == null || v.isEmpty) return null;
    final l = v.toLowerCase();
    if (l == 'unknown' || l == '<unknown>' || v == '未知' || v == '未知歌手') return null;
    return v;
  }

  /// 歌手名去掉 (Live版) 这类尾巴
  static String? _cleanArtist(String? s) {
    if (s == null) return null;
    var v = s.trim();
    v = v.replaceAll(RegExp(r'[（(][^）)]{0,12}[）)]\s*$'), '').trim();
    return _clean(v);
  }

  static String _stripExtension(String name) =>
      name.replaceAll(RegExp(r'\.\w{1,5}$'), '');

  /// 去掉平台前后缀：`网易云音乐 - xx`、`xx - 网易云音乐`、`xx-320k`
  static String _stripSiteAffixes(String s) {
    var out = s.trim();
    for (final site in _siteTags) {
      if (out.length <= site.length) break;
      out = out.replaceFirst(RegExp('^\\s*$site\\s*[-_—–·]+\\s*', caseSensitive: false), '');
      out = out.replaceFirst(RegExp('\\s*[-_—–·]+\\s*$site\\s*\$', caseSensitive: false), '');
    }
    out = out.replaceFirst(RegExp(r'[-_\s]+\d{2,3}\s*k(bps)?\s*$', caseSensitive: false), '');
    return out.trim();
  }

  static String _stripFormatTags(String s) {
    return s
        .replaceAllMapped(RegExp(r'[\[\(【（]\s*([^\]\)】）]{1,16})\s*[\]\)】）]'), (m) {
      final inner = (m.group(1) ?? '').trim().toLowerCase();
      if (_formatTags.contains(inner)) return '';
      if (RegExp(r'\d{2,3}\s*k(bps)?').hasMatch(inner)) return '';
      if (inner.contains('无损') || inner.contains('hi-res')) return '';
      return m.group(0)!;
    })
        .replaceAll(RegExp(r'[-_\s]+\d{2,3}\s*k(bps)?\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  static int? _leadingTrackNo(String s) {
    final m = RegExp(r'^\s*[\[\(]?(\d{1,3})[\]\)]?\s*[\.\-、_]?\s+').firstMatch(s) ??
        RegExp(r'^\s*[\[\(]?(\d{1,3})[\]\)]?[\.\-、]').firstMatch(s);
    if (m == null) return null;
    final n = int.tryParse(m.group(1) ?? '');
    if (n == null || n > 999) return null;
    return n;
  }

  static String _stripLeadingTrackNo(String s) {
    var out = s.replaceFirst(RegExp(r'^\s*[\[\(]?\d{1,3}[\]\)]?\s*[\.\-、_]?\s+'), '');
    if (out == s) {
      out = s.replaceFirst(RegExp(r'^\s*[\[\(]?\d{1,3}[\]\)]?[\.\-、]'), '');
    }
    return out.trim();
  }

  /// 切成多段：` - `、`–`、`—`、`_`、`／`、` · `，以及中文里的无空格连字符
  static List<String> _splitSegments(String s) {
    final out = <String>[];
    final re = RegExp(r'\s+[-–—]\s+|\s*[_／]\s*|\s+·\s+');
    for (final p in s.split(re)) {
      final t = p.trim();
      if (t.isEmpty) continue;
      if (!t.contains(' ') && t.contains('-') && !RegExp(r'[a-zA-Z]').hasMatch(t)) {
        out.addAll(t.split('-').map((e) => e.trim()).where((e) => e.isNotEmpty));
      } else {
        out.add(t);
      }
    }
    return out;
  }
}
