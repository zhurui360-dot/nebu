import 'dart:typed_data';

/// 网盘里的一个条目（文件或目录）
class CloudEntry {
  const CloudEntry({
    required this.path,
    required this.name,
    required this.isDir,
    this.size = 0,
    this.modified,
  });

  /// 相对路径（不含 baseUrl），以 / 开头
  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? modified;
}

class CloudException implements Exception {
  CloudException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => 'CloudException($status): $message';
}

/// 网盘统一抽象。
///
/// 夸克 / 百度 / 联通各自实现一套（OAuth + 开放平台接口），
/// 但上层只认这三个方法：列目录、取一段字节（读标签）、拿播放直链。
abstract class CloudProvider {
  String get sourceId;
  String get displayName;

  /// 列出某个目录下的内容（默认根目录）
  Future<List<CloudEntry>> list(String path);

  /// 取文件的 [start, end] 字节。读标签只要头部 256KB，不要整首下载。
  Future<Uint8List> fetchRange(String path, int start, int end);

  /// 播放直链。WebDAV 直接返回 http(s) 地址；
  /// 夸克/百度需要先换临时直链，过期时间通常几分钟。
  Future<String> directUrl(String path);

  /// 播放时需要的请求头（WebDAV 的 Basic 认证走这里）
  Map<String, String> get playbackHeaders => const {};

  Future<void> close() async {}
}
