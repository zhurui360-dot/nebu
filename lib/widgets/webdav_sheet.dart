import '../models/models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// WebDAV 连接配置：填地址/账号/密码 → 先真实连一次 → 成功才保存
class WebDavSheet extends StatefulWidget {
  const WebDavSheet({super.key, this.sourceId});

  /// 非空 = 编辑这个账号；为空 = 新增一个账号
  final String? sourceId;

  @override
  State<WebDavSheet> createState() => _WebDavSheetState();
}

class _WebDavSheetState extends State<WebDavSheet> {
  CloudSource get _editing {
    final app = context.read<AppState>();
    final id = widget.sourceId;
    return (id == null ? null : app.sourceById(id)) ?? app.webdavSource;
  }

  late final _url = TextEditingController(text: _editing.baseUrl ?? '');
  late final _user = TextEditingController(text: _editing.username ?? '');
  final _pass = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请填写服务器地址');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = '地址要以 http:// 或 https:// 开头');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await context.read<AppState>().saveWebdav(
            baseUrl: url,
            id: widget.sourceId,
            username: _user.text.trim(),
            password: _pass.text,
          );
      if (!mounted) return;
      // 先抓 messenger 再 pop：pop 之后当前 context 随时可能失效
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('连接成功，正在读取目录')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _humanize(e);
      });
    }
  }

  /// 把底层异常翻译成用户能看懂的话
  String _humanize(Object e) {
    final raw = '$e'.replaceAll('CloudException', '').trim();
    final s = raw.startsWith(':') ? raw.substring(1).trim() : raw;
    if (s.contains('401') || s.contains('账号或密码')) {
      return '账号或密码不对。坚果云请用「账户信息 → 安全选项」里生成的应用密码';
    }
    if (s.contains('404')) {
      return '地址找不到。检查地址是否包含正确路径，例如 https://dav.jianguoyun.com/dav/';
    }
    if (s.contains('403')) return '服务器拒绝了访问，检查账号是否拥有该目录权限';
    if (s.contains('percent encoding') || s.contains('Illegal')) {
      return '服务器返回的文件名里有无法解析的特殊字符（这一版已做容错，若仍出现请把地址发我）';
    }
    if (s.contains('Bad state') || s.contains('No element')) {
      return '服务器返回的目录格式无法识别，试试把地址末尾的 / 补上';
    }
    if (s.contains('SocketException') || s.contains('连不上')) {
      return '连不上服务器，检查网络和地址是否正确';
    }
    if (s.contains('FormatException') || s.contains('XML')) {
      return '返回内容不是 WebDAV 响应，确认地址指向 WebDAV 根路径';
    }
    return s.isEmpty ? '连接失败，请检查地址与账号' : s;
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final mq = MediaQuery.of(context);

    // 键盘弹出时按「剩余可用高度」限高，避免顶部留一大片空白
    final maxH = (mq.size.height - mq.viewInsets.bottom) * .92;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Glass(
        radius: R.xxl,
        blur: Blur.thick,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(color: p.line2, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.sourceId == null ? '连接 WebDAV' : 'WebDAV 账号',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.t1)),
                        const SizedBox(height: 4),
                        Text('群晖 / 坚果云 / Nextcloud / Alist 通用',
                            style: TextStyle(fontSize: 12, color: p.t3)),
                      ],
                    ),
                  ),
                  if (app.webdavConfigured)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await context
                                  .read<AppState>()
                                  .disconnectWebdav(_editing.id);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                            },
                      child: const Text('断开', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _field(
                p,
                label: '服务器地址',
                controller: _url,
                hint: 'https://dav.jianguoyun.com/dav/',
                keyboard: TextInputType.url,
              ),
              const SizedBox(height: 12),
              _field(p, label: '账号', controller: _user, hint: '邮箱或用户名'),
              const SizedBox(height: 12),
              _field(
                p,
                label: '密码',
                controller: _pass,
                hint: app.webdavConfigured ? '不修改请留空即可' : '应用专用密码',
                obscure: _obscure,
                trailing: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 18, color: p.t3),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0x14C2412E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x2EC2412E)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFFC2412E))),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.brandSolid,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Text('连接并验证',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '密码经系统钥匙串加密保存在本机，不会上传。'
                '坚果云要在「账户信息 → 安全选项」里生成应用密码，不要用登录密码。',
                style: TextStyle(fontSize: 12, height: 1.7, color: p.t3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    P p, {
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.t2)),
        ),
        Container(
          padding: EdgeInsets.only(left: 12, right: trailing == null ? 12 : 4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboard,
                  obscureText: obscure,
                  style: TextStyle(fontSize: 14.5, color: p.t1),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: 13, color: p.t3),
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ],
    );
  }
}
