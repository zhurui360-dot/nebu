import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// 音乐保存目录的三种选择。
///
/// 公共目录（Music / Download）在任何播放器里都能看到，但 Android 11+
/// 需要「所有文件访问」权限；应用专属目录不需要权限，卸载时一起删掉。
enum DownloadDir {
  /// /storage/emulated/0/Music/Nebu
  publicMusic('dir.publicMusic', 'Music'),

  /// /storage/emulated/0/Download/Nebu
  publicDownload('dir.publicDownload', 'Download'),

  /// .../Android/data/<包名>/files/Music
  appPrivate('dir.app', 'Music');

  const DownloadDir(this.labelKey, this.folderName);

  /// 对应 l10n 里的标题 key
  final String labelKey;

  /// 建在系统目录下的子文件夹名（统一叫 Nebu）
  final String folderName;

  bool get isPublic => this != DownloadDir.appPrivate;

  static DownloadDir fromIndex(int i) =>
      i >= 0 && i < DownloadDir.values.length ? DownloadDir.values[i] : DownloadDir.publicMusic;
}

/// 写入公共目录被系统拒绝
class DownloadPermissionException implements Exception {
  const DownloadPermissionException();
}

/// 「下载到本地」的落盘逻辑：只负责把字节写到用户选的目录里。
///
/// 和离线缓存（OfflineCache）刻意分开：
///  - 缓存是内部私有目录，按上限滚动清理，用户看不见
///  - 下载是用户可见的音乐文件，永不自动清理
class DownloadService {
  static const _rootFolder = 'Nebu';

  /// 外部存储根目录（/storage/emulated/0）。
  /// 拿不到（模拟器/异常）时退化为应用专属目录。
  static Future<Directory?> _externalRoot() async {
    try {
      final appExt = await getExternalStorageDirectory();
      if (appExt == null) return null;
      final path = appExt.path;
      final i = path.indexOf('/Android/');
      if (i <= 0) return null;
      return Directory(path.substring(0, i));
    } catch (_) {
      return null;
    }
  }

  /// 目标目录（不存在就创建）
  static Future<Directory> resolve(DownloadDir kind) async {
    Directory dir;
    if (kind == DownloadDir.appPrivate) {
      final base = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(base.path, kind.folderName, _rootFolder));
    } else {
      final root = await _externalRoot();
      if (root == null) {
        final base = await getApplicationDocumentsDirectory();
        dir = Directory(p.join(base.path, kind.folderName, _rootFolder));
      } else {
        dir = Directory(p.join(root.path, kind.folderName, _rootFolder));
      }
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 目录的可读展示路径（设置页用）
  static Future<String> displayPath(DownloadDir kind) async {
    try {
      return (await resolve(kind)).path;
    } catch (_) {
      return kind.folderName;
    }
  }

  /// 公共目录要「所有文件访问」权限；没给就别硬写，交给调用方降级。
  static Future<bool> ensurePermission(DownloadDir kind) async {
    if (!kind.isPublic) return true;
    if (!Platform.isAndroid) return true;
    try {
      if (await Permission.manageExternalStorage.isGranted) return true;
      // Android 10 及以下：manageExternalStorage 不存在，走老的存储权限
      if (await Permission.storage.isGranted) return true;
      final manage = await Permission.manageExternalStorage.request();
      if (manage.isGranted) return true;
      final legacy = await Permission.storage.request();
      return legacy.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// 网络下载（网盘曲目）：边下边写，返回落盘路径
  static Future<String> downloadUrl({
    required String url,
    Map<String, String>? headers,
    required String fileName,
    required DownloadDir kind,
    void Function(double)? onProgress,
  }) async {
    final dir = await resolve(kind);
    final target = File(p.join(dir.path, fileName));
    if (await target.exists() && await target.length() > 1024) {
      onProgress?.call(1);
      return target.path; // 已经下过就不再重复下载
    }
    final tmp = File('${target.path}.part');

    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse(url))
            ..headers.addAll(headers ?? const {}))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final total = res.contentLength ?? 0;
      final sink = tmp.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      if (received < 1024) {
        await tmp.delete();
        throw Exception('文件不完整');
      }
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      onProgress?.call(1);
      return target.path;
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 复制本地文件（本地曲目「另存一份」到音乐目录）
  static Future<String> copyLocal({
    required String sourcePath,
    required String fileName,
    required DownloadDir kind,
    void Function(double)? onProgress,
  }) async {
    final src = File(sourcePath);
    if (!await src.exists()) throw Exception('源文件不存在');
    final dir = await resolve(kind);
    final target = File(p.join(dir.path, fileName));
    if (await target.exists() && await target.length() > 1024) {
      onProgress?.call(1);
      return target.path;
    }
    final total = await src.length();
    final sink = target.openWrite();
    var done = 0;
    await for (final chunk in src.openRead()) {
      sink.add(chunk);
      done += chunk.length;
      if (total > 0) onProgress?.call((done / total).clamp(0.0, 1.0));
    }
    await sink.flush();
    await sink.close();
    onProgress?.call(1);
    return target.path;
  }

  /// 文件名安全化：去掉路径分隔符与系统不允许的字符
  static String safeName(String raw, {int max = 90}) {
    var s = raw.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) s = 'Nebu';
    if (s.length > max) s = s.substring(0, max).trim();
    return s;
  }

  /// 保存目录里已有的文件数（设置页给个直观反馈）
  static Future<int> countFiles(DownloadDir kind) async {
    try {
      final dir = await resolve(kind);
      var n = 0;
      await for (final e in dir.list(followLinks: false)) {
        if (e is File && !e.path.endsWith('.part')) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }
}
