/// 版本信息：与 pubspec.yaml 的 version 保持一致
/// （改版本时两处一起改，更新检查用它和服务器比对）
class AppMeta {
  static const version = '0.0.002';

  /// versionCode 自动从版本号推导（0.0.XX → XX），
  /// 与 version.json 里的 versionCode 同一规则，避免手改漏同步导致误报更新。
  static final int versionCode = _codeFromVersion(version);
  static final int buildNumber = versionCode;

  /// 默认更新检查地址：jsDelivr 镜像仓库里的 version.json
  /// （GitHub 直连在国内移动网络常超时，CDN 镜像更快；
  ///   APK 本身仍从 GitHub Releases 下载，发版后需 purge 一次 CDN 缓存）
  static const defaultUpdateUrl =
      'https://cdn.jsdelivr.net/gh/zhurui360-dot/nebu@main/version.json';
  static const appName = 'Nebu';

  static int _codeFromVersion(String v) {
    final parts = v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[2];
  }
}
