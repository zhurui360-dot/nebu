import '../../models/models.dart';

/// LRC 歌词解析：支持 [mm:ss.xx] / [mm:ss.xxx] / 一行多时间戳。
class LrcParser {
  static final _tag = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  static List<LyricLine> parse(String raw) {
    final out = <LyricLine>[];
    for (final line in raw.split('\n')) {
      final matches = _tag.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.replaceAll(_tag, '').trim();
      if (text.isEmpty) continue;

      for (final m in matches) {
        final min = int.tryParse(m.group(1) ?? '') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '') ?? 0;
        final fracRaw = m.group(3) ?? '0';
        // 两位是百分秒，三位是毫秒
        final ms = fracRaw.length == 3
            ? int.tryParse(fracRaw) ?? 0
            : (int.tryParse(fracRaw) ?? 0) * 10;
        final time = Duration(minutes: min, seconds: sec, milliseconds: ms);

        // 双语 LRC：同一时间戳出现两次 → 第二行是第一行的翻译。
        // 允许 30ms 内的抖动（有些编辑器逐行打轴会有细微偏差）。
        final last = out.isEmpty ? null : out.last;
        if (last != null &&
            last.trans == null &&
            (time - last.time).abs() <= const Duration(milliseconds: 30)) {
          out[out.length - 1] = LyricLine(last.time, last.text, text);
        } else {
          out.add(LyricLine(time, text));
        }
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// 把任意歌词文本整理成 LRC：
  /// 本来就有时间轴就原样返回；纯文本则按每行 6 秒生成时间轴，至少能滚动。
  static String toLrc(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('<')) return ''; // 多半是错误页
    if (_tag.hasMatch(text)) return text;
    final lines = text.split('\n').where((e) => e.trim().isNotEmpty).toList();
    final out = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final sec = i * 6;
      final mm = (sec ~/ 60).toString().padLeft(2, '0');
      final ss = (sec % 60).toString().padLeft(2, '0');
      out.writeln('[$mm:$ss.00]${lines[i].trim()}');
    }
    return out.toString();
  }

  /// 判断是不是一个「有内容」的 LRC（避免把 HTML 错误页当歌词）
  static bool looksLikeLrc(String raw) {
    if (raw.trim().isEmpty) return false;
    if (raw.trimLeft().startsWith('<')) return false;
    return _tag.hasMatch(raw);
  }
}
