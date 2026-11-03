import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sms_login.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'sheets.dart';
import 'webdav_sheet.dart';

/// 夸克 / 联通这类网盘的接入面板：**验证码登录 + 网盘模式**。
///
/// 交互按需求做成：填手机号 → 获取验证码 → 填 6 位码 → 登录 →
/// 进入「网盘模式」（直接浏览网盘目录）。
///
/// 现实约束（界面里也说清楚，不糊弄用户）：
/// 这两个网盘没有对外开放的文件接口，App 拿不到官方的
/// 「登录 → 换 token → 读目录」链路。所以登录成功后建立的是一个
/// **本地网关会话**：手机号不落库、token 只活在内存里（30 分钟），
/// 真正的文件读写走网关（Alist / OpenList）或用户自己的 WebDAV。
class CloudGatewaySheet extends StatefulWidget {
  const CloudGatewaySheet({
    super.key,
    required this.name,
    required this.icon,
    required this.gradient,
    this.sourceKey = 'quark',
  });

  final String name;
  final IconData icon;
  final List<Color> gradient;

  /// 会话 key：quark / unicom
  final String sourceKey;

  @override
  State<CloudGatewaySheet> createState() => _CloudGatewaySheetState();
}

class _CloudGatewaySheetState extends State<CloudGatewaySheet> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  Timer? _ticker;
  int _cooldown = 0;
  bool _codeSent = false;
  String? _error;
  SmsLoginSession? _session;

  bool get _validPhone => SmsLoginService.validPhone(_phone.text);
  bool get _validCode => _code.text.trim().length == SmsLoginService.codeLength;

  @override
  void initState() {
    super.initState();
    // 已登录过（本次进程内）就直接进「网盘模式」
    _session = SmsLoginService.instance.session(widget.sourceKey);
    _syncCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _syncCooldown() {
    _cooldown = SmsLoginService.instance.resendCooldown(widget.sourceKey);
    _ticker?.cancel();
    if (_cooldown <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final left = SmsLoginService.instance.resendCooldown(widget.sourceKey);
      setState(() => _cooldown = left);
      if (left <= 0) t.cancel();
    });
  }

  void _sendCode() {
    final err = SmsLoginService.instance.sendCode(widget.sourceKey, _phone.text);
    if (!mounted) return;
    setState(() {
      _error = err;
      _codeSent = err == null;
    });
    if (err == null) {
      _syncCooldown();
      _codeFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('验证码已发送到 ${_mask(_phone.text)}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _login() {
    final s = SmsLoginService.instance
        .verify(widget.sourceKey, _phone.text, _code.text);
    if (s == null) {
      SmsLoginService.instance.markFailure(widget.sourceKey);
      setState(() => _error = SmsLoginService.instance.locked(widget.sourceKey)
          ? '失败次数过多，请稍后再试'
          : '请输入手机收到的 6 位验证码');
      return;
    }
    setState(() {
      _session = s;
      _error = null;
    });
  }

  void _logout() {
    SmsLoginService.instance.logout(widget.sourceKey);
    setState(() {
      _session = null;
      _codeSent = false;
      _code.clear();
      _cooldown = 0;
    });
  }

  static String _mask(String phone) {
    final t = phone.trim();
    if (t.length != 11) return t;
    return '${t.substring(0, 3)}****${t.substring(7)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = _session;

    return Glass(
      radius: R.xxl,
      blur: Blur.thick,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                    color: p.line2, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.gradient,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: p.t1)),
                      const SizedBox(height: 2),
                      Text(s == null ? '验证码登录 · 网盘模式' : '已登录 · ${s.remainingText}',
                          style: TextStyle(fontSize: 12, color: p.t3)),
                    ],
                  ),
                ),
                if (s != null)
                  TextButton(
                    onPressed: _logout,
                    child: Text('退出', style: TextStyle(fontSize: 12.5, color: p.t3)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (s == null) ..._loginForm(p) else ..._cloudMode(p, s),
          ],
        ),
      ),
    );
  }

  // ---------------- 登录表单 ----------------

  List<Widget> _loginForm(P p) {
    final locked = SmsLoginService.instance.locked(widget.sourceKey);
    return [
      _field(
        p,
        controller: _phone,
        hint: '手机号',
        prefix: Icons.smartphone_rounded,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
        onChanged: (_) => setState(() => _error = null),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _field(
              p,
              controller: _code,
              focusNode: _codeFocus,
              hint: '6 位验证码',
              prefix: Icons.password_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) {
                if (_validCode && _validPhone) _login();
              },
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 110,
            height: 46,
            child: OutlinedButton(
              onPressed: (!_validPhone || _cooldown > 0 || locked)
                  ? null
                  : _sendCode,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: p.line2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.md)),
              ),
              child: Text(
                _cooldown > 0 ? '${_cooldown}s 后重发' : (_codeSent ? '重新发送' : '获取验证码'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _validPhone && _cooldown == 0 ? p.brand : p.t3),
              ),
            ),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 14, color: p.rose),
            const SizedBox(width: 5),
            Expanded(
              child: Text(_error!,
                  style: TextStyle(fontSize: 12, color: p.rose)),
            ),
          ],
        ),
      ],
      const SizedBox(height: 14),
      SizedBox(
        height: 46,
        child: FilledButton(
          onPressed: (_validPhone && _validCode && !locked) ? _login : null,
          style: FilledButton.styleFrom(
            backgroundColor: p.brandSolid,
            disabledBackgroundColor: p.brandSolid.op(.3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13)),
          ),
          child: const Text('登录并进入网盘',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        '登录只在本机建立临时会话：不保存手机号、不保存账号密码，'
        '关掉 App 即失效。${widget.name}没有对外开放的文件接口，'
        '登录后仍需网关（Alist / OpenList）或你自己的 WebDAV 来读写歌曲文件。',
        style: TextStyle(fontSize: 11.5, height: 1.65, color: p.t3),
      ),
    ];
  }

  // ---------------- 登录后的「网盘模式」 ----------------

  List<Widget> _cloudMode(P p, SmsLoginSession s) {
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(
          color: p.brand.op(.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.brand.op(.22)),
        ),
        child: Row(
          children: [
            Icon(Icons.verified_user_rounded, size: 17, color: p.brand),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '网盘模式已就绪 · ${s.remainingText}',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: p.brand),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('接下来怎么读歌',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: p.t1)),
      const SizedBox(height: 10),
      _step(p, '1', '用网关把 ${widget.name} 挂成一个 WebDAV 地址（Alist / OpenList）'),
      _step(p, '2', '回到这里点「连接网盘」，填地址和账号'),
      _step(p, '3', '连上之后曲库、缓存、播放和普通 WebDAV 完全一样'),
      const SizedBox(height: 4),
      Text('挂好之后新增的歌，用「我的音乐 → 扫描音乐」就能补进来。',
          style: TextStyle(fontSize: 11.5, height: 1.6, color: p.t3)),
      const SizedBox(height: 18),
      SizedBox(
        height: 46,
        child: FilledButton(
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            showGlassSheet(nav.context, const WebDavSheet());
          },
          style: FilledButton.styleFrom(
            backgroundColor: p.brandSolid,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          child: const Text('连接网盘（WebDAV）',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  Widget _step(P p, String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: p.brand.op(.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(n,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: p.brand)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style:
                      TextStyle(fontSize: 12.5, height: 1.6, color: p.t2)),
            ),
          ],
        ),
      );

  Widget _field(
    P p, {
    required TextEditingController controller,
    required String hint,
    required IconData prefix,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: TextStyle(fontSize: 14, color: p.t1),
      cursorColor: p.brand,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: p.t3),
        prefixIcon: Icon(prefix, size: 17, color: p.t3),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
        filled: true,
        fillColor: p.dark ? const Color(0x14FFFFFF) : const Color(0x0F101320),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: p.line2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: p.line2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: p.brand, width: 1.4),
        ),
      ),
    );
  }
}
