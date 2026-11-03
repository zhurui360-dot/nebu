import '../models/models.dart';

/// 正式版可用的音乐来源清单。
///
/// 这里只放「来源本身的元信息」（名字、图标配色、支持的协议），
/// 不含任何曲目/专辑示例数据 —— 曲库只能来自用户真实导入。
class SourceCatalog {
  /// WebDAV：群晖 / 坚果云 / Nextcloud / Alist 等
  static const webdav = CloudSource(
    id: 'webdav',
    name: 'WebDAV',
    kind: SourceKind.webdav,
    subtitle: '群晖 / 坚果云 / Nextcloud / Alist',
    connected: false,
    gradient: [0xFF2E3A52, 0xFF5A6B8C],
    badge: '通用',
  );

  /// 目前正式开放的来源（本地音乐单独做成卡片，不在这里）
  static const sources = <CloudSource>[webdav];

  /// 后续版本规划（界面只做提示，不可点击）。
  /// 夸克 / 联通暂时移到这一档（v0.0.65 下线验证码登录入口，
  /// 等有正式开放接口再回「添加音乐来源」），百度 / 天翼本来就还没接。
  static const upcoming = <String>['夸克网盘', '联通网盘', '百度网盘', '天翼云盘'];

  static CloudSource byId(String id) => sources.firstWhere(
        (s) => s.id == id,
        orElse: () => webdav,
      );

  /// 扫描时支持的扩展名汇总
  static List<String> get allExtensions =>
      MusicFormat.values.expand((f) => f.extensions).toList();
}
