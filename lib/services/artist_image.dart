import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 歌手照片：从公开目录（iTunes Search API）取该歌手的专辑封面当作头像，
/// 取到后落盘缓存，下次直接读本地文件，不再联网。
///
/// 为什么用专辑封面当歌手照：公开的歌手头像接口基本都要 API Key，
/// 而 iTunes 搜索接口无需鉴权、中文歌手也能命中，作为兜底最稳。
class ArtistImage {
  static final Map<String, String?> _memory = {};
  static final Map<String, Future<String?>> _inflight = {};

  // 并发闸门：歌手页一屏会同时问几十个歌手，全部一起发请求会打满连接池、
  // 让本来就慢的页面更慢。这里限制同时最多 3 个，其余排队。
  static const _maxConcurrent = 3;
  static int _running = 0;
  static final List<Completer<void>> _pending = [];

  static Future<void> _acquire() {
    if (_running < _maxConcurrent) {
      _running++;
      return Future.value();
    }
    final c = Completer<void>();
    _pending.add(c);
    return c.future;
  }

  static void _release() {
    if (_pending.isNotEmpty) {
      _pending.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  /// 返回本地文件路径；找不到或失败返回 null（调用方显示首字母兜底）
  static Future<String?> lookup(String artist) {
    final key = artist.trim();
    if (key.isEmpty || key == '未知歌手') return Future.value(null);
    if (_memory.containsKey(key)) return Future.value(_memory[key]);
    return _inflight[key] ??=
        _load(key).whenComplete(() => _inflight.remove(key));
  }

  static Future<String?> _load(String artist) async {
    await _acquire();
    try {
      final dir = Directory(
          p.join((await getApplicationSupportDirectory()).path, 'artists'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${_hash(artist)}.jpg'));

      // 本地已有缓存
      if (await file.exists() && await file.length() > 1024) {
        _memory[artist] = file.path;
        return file.path;
      }

      // 1) 搜索该歌手的专辑，拿专辑封面
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': artist,
        'entity': 'album',
        'limit': '3',
        'country': 'CN',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        _memory[artist] = null;
        return null;
      }
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final results = (json['results'] as List?) ?? const [];
      String? art;
      for (final r in results) {
        final a = (r as Map)['artworkUrl100'] as String?;
        if (a != null && a.isNotEmpty) {
          art = a;
          break;
        }
      }
      if (art == null) {
        _memory[artist] = null;
        return null;
      }

      // 2) 换大图并下载
      final url = art
          .replaceAll('100x100bb', '600x600bb')
          .replaceAll('100x100', '600x600');
      final img = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (img.statusCode != 200 || img.bodyBytes.length < 1024) {
        _memory[artist] = null;
        return null;
      }
      await file.writeAsBytes(img.bodyBytes, flush: true);
      _memory[artist] = file.path;
      return file.path;
    } catch (_) {
      _memory[artist] = null;
      return null;
    } finally {
      _release();
    }
  }

  /// 清空磁盘缓存（在「清除缓存数据」里调用）
  static Future<void> clearCache() async {
    _memory.clear();
    try {
      final dir = Directory(
          p.join((await getApplicationSupportDirectory()).path, 'artists'));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static String _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }
}
