import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用内更新：下载 APK 到本地，再拉起系统安装器（不跳浏览器）
class UpdateInstaller {
  static const _fileName = 'cloudtune-update.apk';

  /// 下载并回报进度 0..1，返回本地文件路径
  static Future<String> download(
    String url, {
    void Function(double progress, int received, int total)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final target = File(p.join(dir.path, _fileName));
    if (await target.exists()) await target.delete();

    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        throw Exception('下载失败（HTTP ${res.statusCode}）');
      }
      final total = res.contentLength ?? 0;
      final sink = target.openWrite();
      var received = 0;

      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(total > 0 ? (received / total).clamp(0, 1) : 0, received, total);
      }
      await sink.flush();
      await sink.close();

      if (received < 1024) {
        throw Exception('下载到的文件不完整');
      }
      return target.path;
    } finally {
      client.close();
    }
  }

  /// 拉起系统安装界面（Android）
  static Future<String> install(String apkPath) async {
    final result = await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );
    return result.message;
  }

  /// 清理已下载的包
  static Future<void> clean() async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, _fileName));
    if (await f.exists()) await f.delete();
  }
}
