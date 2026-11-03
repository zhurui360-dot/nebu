import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 离线缓存：把网盘/本地音频缓存到应用私有目录，断网也能播。
///
/// 目录：{appSupport}/audio_cache/{trackId}
/// 没有任何元数据文件——以文件是否存在为准，清理即删目录。
class OfflineCache {
  /// 缓存大小上限（MB，0 = 不限制）：由 AppState 在启动 / 改设置时同步进来
  static int limitMb = 5120;

  /// 正在播放的曲目 id：清理旧缓存时跳过，别把正在读的文件删掉
  static String? playingTrackId;

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'audio_cache'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 缓存文件路径（不保证已下载）
  static Future<String> pathFor(String trackId) async {
    final d = await _dir();
    return p.join(d.path, trackId);
  }

  static Future<bool> isCached(String trackId) async {
    final f = File(await pathFor(trackId));
    if (!await f.exists()) return false;
    return (await f.length()) > 1024; // 小于 1KB 视为没下完
  }

  static Future<String?> cachedPath(String trackId) async {
    if (!await isCached(trackId)) return null;
    return pathFor(trackId);
  }

  /// 下载并缓存；已缓存则直接返回路径。
  /// [url] 为空（本地文件）时不做缓存，直接返回 null。
  static Future<String?> ensure(
    String trackId,
    String? url,
    Map<String, String>? headers, {
    void Function(double progress)? onProgress,
  }) async {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('file://')) return null; // 本地文件本来就在本机

    final existing = await cachedPath(trackId);
    if (existing != null) return existing;

    // 写入前先按上限腾空间，避免缓存无限长大
    await _trimToLimit(trackId);

    final target = File(await pathFor(trackId));
    final tmp = File('${target.path}.part');

    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse(url))
            ..headers.addAll(headers ?? const {}))
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200 && res.statusCode != 206) {
        throw Exception('缓存失败（HTTP ${res.statusCode}）');
      }
      final total = res.contentLength ?? 0;
      final sink = tmp.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress?.call((received / total).clamp(0, 1));
      }
      await sink.flush();
      await sink.close();

      if (received < 1024) {
        await tmp.delete();
        throw Exception('缓存到的文件不完整');
      }
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      return target.path;
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 按上限清理：超出 [limitMb] 时按文件 mtime 从旧到新删，直到不超限。
  /// 跳过正在写入的目标曲目、正在播放的曲目，以及未下完的 .part 文件。
  static Future<void> _trimToLimit(String targetId) async {
    final limit = limitMb;
    if (limit <= 0) return; // 不限制
    final maxBytes = limit * 1024 * 1024;

    final d = await _dir();
    final entries = <({File file, DateTime mtime, int size})>[];
    var total = 0;
    try {
      await for (final e in d.list(followLinks: false)) {
        if (e is! File || e.path.endsWith('.part')) continue;
        final name = p.basename(e.path);
        if (name == targetId || name == playingTrackId) continue;
        final st = await e.stat();
        total += st.size;
        entries.add((file: e, mtime: st.modified, size: st.size));
      }
    } catch (_) {
      return;
    }
    if (total <= maxBytes) return;

    entries.sort((a, b) => a.mtime.compareTo(b.mtime)); // 最旧的先删
    for (final e in entries) {
      if (total <= maxBytes) break;
      try {
        await e.file.delete();
        total -= e.size;
      } catch (_) {}
    }
  }

  /// 已缓存的曲目 id 集合（启动时一次性读出来给列表用）
  static Future<Set<String>> cachedSet() async {
    final d = await _dir();
    final out = <String>{};
    try {
      await for (final e in d.list(followLinks: false)) {
        if (e is File && !e.path.endsWith('.part')) {
          out.add(p.basename(e.path));
        }
      }
    } catch (_) {}
    return out;
  }

  static Future<void> remove(String trackId) async {
    try {
      final f = File(await pathFor(trackId));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 缓存总大小（字节）
  static Future<int> totalSize() async {
    final d = await _dir();
    var total = 0;
    try {
      await for (final e in d.list(followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  static Future<int> count() async {
    final d = await _dir();
    var n = 0;
    try {
      await for (final e in d.list(followLinks: false)) {
        if (e is File && !e.path.endsWith('.part')) n++;
      }
    } catch (_) {}
    return n;
  }

  /// 清理全部缓存
  static Future<void> clear() async {
    final d = await _dir();
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    await _dir(); // 重建空目录
  }

  static String human(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }
}
