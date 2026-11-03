import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一次更新检查的结果
class UpdateResult {
  const UpdateResult({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    this.sizeBytes = 0,
  });

  final String version;
  final List<String> notes;
  final String downloadUrl;
  final int sizeBytes;

  String get sizeText =>
      sizeBytes <= 0 ? '' : '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 真实更新检查：GET 一个 version.json，比对版本号。
///
/// 服务端只需要放一个静态文件，例如放在你的网盘/对象存储/GitHub Pages：
/// ```json
/// {
///   "version": "1.1.0",
///   "versionCode": 2,
///   "url": "https://example.com/cloudtune-1.1.0.apk",
///   "size": 53446519,
///   "notes": ["新增 xxx", "修复 yyy"]
/// }
/// ```
class UpdateService {
  /// 返回 null 表示已是最新
  static Future<UpdateResult?> check(
    String endpoint, {
    required int currentVersionCode,
  }) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || !uri.hasScheme) {
      throw UpdateException('更新地址不是一个有效链接');
    }

    late final http.Response res;
    try {
      res = await http
          .get(uri, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw UpdateException('连不上更新服务器，请检查网络或地址');
    }

    if (res.statusCode != 200) {
      throw UpdateException('更新地址返回 ${res.statusCode}');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw UpdateException('更新信息格式不对（需要 JSON）');
    }

    final remoteCode = (json['versionCode'] as num?)?.toInt() ?? 0;
    final version = (json['version'] as String?)?.trim() ?? '';
    final url = (json['url'] as String?)?.trim() ?? '';
    if (version.isEmpty) throw UpdateException('更新信息里缺少 version 字段');

    // 优先比 versionCode，没有就按语义化版本比较
    final bool newer = remoteCode > 0
        ? remoteCode > currentVersionCode
        : _compare(version, currentVersionCode);

    if (!newer) return null;

    return UpdateResult(
      version: version,
      notes: (json['notes'] as List?)?.map((e) => '$e').toList() ?? const [],
      downloadUrl: url,
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// 无 versionCode 时的兜底：把 x.y.z 逐段比较
  static bool _compare(String remote, int currentCode) {
    final r = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    // 本地版本号形如 1.0.0 → 也拆成三段；这里用 currentCode 仅作兜底
    final local = currentCode <= 1 ? [1, 0, 0] : [currentCode, 0, 0];
    for (var i = 0; i < 3; i++) {
      final a = i < r.length ? r[i] : 0;
      final b = i < local.length ? local[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }
}
