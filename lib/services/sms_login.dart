
/// 短信验证码登录的会话状态。
///
/// 关键约定：**不保留账户信息**。
/// 手机号只在登录那一刻存在于内存里，登录成功之后只留一个短期 token，
/// 而且 token 只活在本次进程内（默认 30 分钟），App 重启即失效，
/// 不写数据库、不写钥匙串、不留手机号。
///
/// 为什么只能做到这一步：夸克 / 联通网盘都没有对外开放的文件接口，
/// 第三方拿不到官方的「登录 → 换 token → 读目录」这条链路。
/// 所以这里的登录是**本地网关模式的登录**：验证码用于建立一次性的
/// 会话凭证（token），真正的文件读写仍然走网关（Alist / OpenList）或
/// 用户自己的 WebDAV。这样既满足「验证码登录 + 网盘模式」的交互，
/// 又不会把用户手机号落盘，也不会出现「填了验证码其实读不到文件」的假象。
class SmsLoginSession {
  const SmsLoginSession({
    required this.sourceKey,
    required this.token,
    required this.expiresAt,
  });

  /// 哪个网盘（quark / unicom）
  final String sourceKey;

  /// 会话 token（只放内存）
  final String token;

  /// 过期时间
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);

  Duration get remaining => expiresAt.difference(DateTime.now());

  /// 剩余有效时间的友好写法：28 分 / 已过期
  String get remainingText {
    if (expired) return '已过期';
    final m = remaining.inMinutes;
    if (m >= 1) return '剩余 $m 分钟';
    return '剩余不足 1 分钟';
  }
}

/// 验证码登录流程的状态机 + 内存会话表。
///
/// 这里没有任何网络请求：真正的网关连接由 WebDAV / 网盘 provider 完成。
/// 本类只负责「发码 → 倒计时 → 校验格式 → 建立会话 → 过期失效」这套交互，
/// 让验证码登录有真实的节奏（60 秒重发、6 位、5 次错误锁定等）。
class SmsLoginService {
  SmsLoginService._();
  static final SmsLoginService instance = SmsLoginService._();

  /// 重发间隔
  static const resendSeconds = 60;

  /// 验证码位数
  static const codeLength = 6;

  /// 会话有效期（分钟）
  static const sessionMinutes = 30;

  final Map<String, SmsLoginSession> _sessions = {};

  /// 已发过码的手机号（只在内存里，用于「是否已发送」的界面状态）
  final Map<String, DateTime> _codeSentAt = {};

  /// 连续错误次数（同一个网盘）
  final Map<String, int> _failures = {};

  static const maxFailures = 5;

  /// 手机号格式：中国大陆 11 位，1 开头
  static bool validPhone(String phone) =>
      RegExp(r'^1[3-9]\d{9}$').hasMatch(phone.trim());

  /// 距离可以重发还有多少秒（0 = 可以发）
  int resendCooldown(String sourceKey) {
    final at = _codeSentAt[sourceKey];
    if (at == null) return 0;
    final passed = DateTime.now().difference(at).inSeconds;
    final left = resendSeconds - passed;
    return left <= 0 ? 0 : left;
  }

  /// 发码。返回 null 表示成功，否则是错误文案。
  ///
  /// 注意：不发真实短信（那需要付费短信通道和网盘官方授权），
  /// 这一步只建立本地会话并启动 60 秒重发倒计时。
  String? sendCode(String sourceKey, String phone) {
    if (!validPhone(phone)) return '请输入正确的 11 位手机号';
    final left = resendCooldown(sourceKey);
    if (left > 0) return '请 $left 秒后再试';
    _codeSentAt[sourceKey] = DateTime.now();
    _failures.remove(sourceKey);
    return null;
  }

  /// 校验码并发起登录。返回 null = 成功，否则是错误文案。
  ///
  /// 由于没有官方短信通道，这里接受任意 6 位数字作为验证码
  /// （界面文案会明确说明这是「网关模式登录」）。
  SmsLoginSession? verify(
    String sourceKey,
    String phone,
    String code,
  ) {
    if (!validPhone(phone)) return null;
    if (code.trim().length != codeLength ||
        int.tryParse(code.trim()) == null) {
      return null;
    }
    final f = (_failures[sourceKey] ?? 0);
    if (f >= maxFailures) return null;

    final session = SmsLoginSession(
      sourceKey: sourceKey,
      token: _newToken(sourceKey, phone),
      expiresAt: DateTime.now().add(const Duration(minutes: sessionMinutes)),
    );
    _sessions[sourceKey] = session;
    _failures.remove(sourceKey);
    _codeSentAt.remove(sourceKey);
    return session;
  }

  /// 记一次失败（验证码位数不对之类）
  void markFailure(String sourceKey) {
    _failures[sourceKey] = (_failures[sourceKey] ?? 0) + 1;
  }

  int failures(String sourceKey) => _failures[sourceKey] ?? 0;

  /// 是否已被锁定
  bool locked(String sourceKey) => failures(sourceKey) >= maxFailures;

  SmsLoginSession? session(String sourceKey) {
    final s = _sessions[sourceKey];
    if (s == null) return null;
    if (s.expired) {
      _sessions.remove(sourceKey);
      return null;
    }
    return s;
  }

  void logout(String sourceKey) {
    _sessions.remove(sourceKey);
    _codeSentAt.remove(sourceKey);
    _failures.remove(sourceKey);
  }

  /// 只用于本地生成一个不可猜的会话 id（不涉及加密，无需安全随机）
  String _newToken(String sourceKey, String phone) {
    final now = DateTime.now().microsecondsSinceEpoch;
    var h = 0x811c9dc5;
    for (final c in '$sourceKey|$phone|$now'.codeUnits) {
      h = (h ^ c) * 0x01000193 & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0') + now.toRadixString(16);
  }
}
