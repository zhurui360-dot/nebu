import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/online_meta.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'sheets.dart';

/// 歌词源 / 封面源管理：内置源 + 可手动添加
class MetaSourceSheet extends StatelessWidget {
  const MetaSourceSheet({
    super.key,
    this.inPanel = false,
    this.inline = false,
    this.centered = false,
  });

  /// true = 作为「从行下方弹出」的面板显示（不带把手）
  final bool inPanel;

  /// true = 直接在页面里向下展开（没有外壳、没有标题）
  final bool inline;

  /// true = 居中弹窗形态（独立 Dialog，外壳带标题栏 + 关闭按钮）
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final sources = app.metaSources;

    // 接口说明：居中弹窗放顶部（标题栏下面），底部弹层保持原位放底部
    final apiNote = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: p.line),
      ),
      child: Text(
        '两种接法：① 兼容接口——歌词源兼容 LRCLIB 的 /api/get（返回 '
        'syncedLyrics/plainLyrics），封面源兼容 iTunes Search（返回 '
        'results[].artworkUrl100）；② 模板地址——自己拼 URL，'
        '用 {title} {artist} {album} {duration} 占位，返回格式同上。',
        style: TextStyle(fontSize: 12, height: 1.7, color: p.t3),
      ),
    );

    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!inPanel && !inline && !centered) ...[
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                    color: p.line2, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          // 居中弹窗由外壳负责标题栏，这里不再重复标题
          if (!inline && !centered)
            Text('歌词源 / 封面源',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: p.t1)),
          if (!inline && !centered) const SizedBox(height: 4),
          // 居中弹窗：接口说明紧贴标题，放在弹窗顶部
          if (centered) apiNote,
          if (!centered)
            Text('在线补全时按顺序尝试；内置源免费公开，也可以自己加',
                style: TextStyle(fontSize: 12, color: p.t3)),
          if (!centered) const SizedBox(height: 14),

          for (final s in sources)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: (s.isLyric ? p.brand : p.brand2).op(.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      s.isLyric ? Icons.lyrics_outlined : Icons.image_outlined,
                      size: 16,
                      color: s.isLyric ? p.brand : p.brand2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: p.t1)),
                            ),
                            const SizedBox(width: 6),
                            _tag(p, s.isLyric ? '歌词' : '封面'),
                            if (s.builtIn) ...[
                              const SizedBox(width: 5),
                              _tag(p, '内置', muted: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(s.endpoint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: p.t3)),
                      ],
                    ),
                  ),
                  if (!s.builtIn)
                    TextButton(
                      onPressed: () => app.removeMetaSource(s.id),
                      child: Text('删除',
                          style: TextStyle(fontSize: 12.5, color: p.t3)),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _addSource(context, app),
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('添加源', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: p.line2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          // 底部弹层：说明放最底部（居中弹窗已在顶部显示）
          if (!centered) apiNote,
        ],
    );

    // 内联展开时外层页面本身可滚，不再嵌套滚动容器
    final body = inline
        ? content
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, centered ? 0 : 6, 20, 22),
            child: content,
          );
    if (inline) return body;

    // 居中弹窗：标题 + 说明放最顶部（外壳只负责玻璃卡片，不铺标题）
    if (centered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          glassSheetHeader(context, '歌词源 / 封面源',
              '在线补全时按顺序尝试；内置源免费公开，也可以自己加',
              onClose: () => Navigator.pop(context)),
          Flexible(child: body),
        ],
      );
    }

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .86),
      child: Glass(
        radius: R.xxl,
        blur: Blur.thick,
        child: body,
      ),
    );
  }

  Widget _tag(P p, String text, {bool muted = false}) {
    final color = muted ? p.t3 : (p.brand);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.op(.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.op(.25)),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Future<void> _addSource(BuildContext context, AppState app) =>
      showGlassSheet<void>(context, _AddSourceSheet(app: app));
}

/// 添加源：和「缓存大小上限」等面板同一套外壳（底部滑出 + 把手 + 标题）
class _AddSourceSheet extends StatefulWidget {
  const _AddSourceSheet({required this.app});
  final AppState app;

  @override
  State<_AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends State<_AddSourceSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String _kind = 'lyric';

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _url.text.trim().startsWith('http');

  Future<void> _submit() async {
    if (!_valid) return;
    await widget.app.addMetaSource(MetaSource(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      kind: _kind,
      endpoint: _url.text.trim(),
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return GlassSheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          glassSheetHeader(
            context,
            '添加源',
            '接口兼容 LRCLIB / iTunes，也可以写带占位符的模板地址',
            onClose: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  style: TextStyle(fontSize: 13.5, color: p.t1),
                  onChanged: (_) => setState(() {}),
                  decoration: _decoration(p, '名称', '我的歌词源'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _url,
                  style: TextStyle(fontSize: 13.5, color: p.t1),
                  onChanged: (_) => setState(() {}),
                  decoration: _decoration(
                    p,
                    '接口地址',
                    _kind == 'lyric'
                        ? 'https://lrclib.net/api 或 ?q={artist} {title}'
                        : 'https://itunes.apple.com/search 或 ?q={title}',
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _url.text.contains('{')
                      ? '模板源：{title} {artist} {album} {duration} 会被替换成实际值'
                      : '也可以直接写带占位符的完整地址，例如 '
                          'https://api.xxx.com/lyric?q={artist} {title}',
                  style: TextStyle(fontSize: 11, height: 1.5, color: p.t3),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _seg(p, '歌词源', _kind == 'lyric',
                        () => setState(() => _kind = 'lyric')),
                    const SizedBox(width: 8),
                    _seg(p, '封面源', _kind == 'cover',
                        () => setState(() => _kind = 'cover')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                          side: BorderSide(color: p.line2),
                        ),
                      ),
                      child: Text('取消',
                          style: TextStyle(fontSize: 14.5, color: p.t2)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: _valid ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.brandSolid,
                        disabledBackgroundColor: p.brandSolid.op(.28),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text('添加',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(P p, String label, String hint) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 12, color: p.t3),
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12.5, color: p.t3),
      filled: true,
      fillColor: p.dark ? const Color(0x14FFFFFF) : const Color(0x0F101320),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      border: border(p.line2),
      enabledBorder: border(p.line2),
      focusedBorder: border(p.brand, 1.4),
    );
  }

  Widget _seg(P p, String text, bool on, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? p.brand.op(.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? p.brand : p.line2),
          ),
          alignment: Alignment.center,
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: on ? p.brand : p.t2)),
        ),
      ),
    );
  }
}
