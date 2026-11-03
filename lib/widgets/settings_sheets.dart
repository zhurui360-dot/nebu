import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/lang.dart';
import '../l10n/strings.dart';
import '../services/download_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'sheets.dart' show glassSheetHeader;

/// 语言选择：跟随系统 + 7 种语言，就地切换、立即生效。
/// 作为「我的 → 语言」的居中弹窗内容使用。
class LanguageSheet extends StatelessWidget {
  const LanguageSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final l = L.of(context);

    Widget row({
      required String title,
      String? sub,
      required bool on,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? p.brand : p.t1,
                      ),
                    ),
                    if (sub != null && sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(sub,
                          style: TextStyle(fontSize: 11.5, color: p.t3)),
                    ],
                  ],
                ),
              ),
              if (on)
                Icon(Icons.check_circle_rounded, size: 19, color: p.brand),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        glassSheetHeader(context, l.t('lang.title'), l.t('lang.sub'),
            onClose: () => Navigator.pop(context)),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
            child: Column(
              children: [
                // 跟随系统
                row(
                  title: l.t('lang.system'),
                  sub: l.t('lang.systemSub'),
                  on: app.followSystemLang,
                  onTap: () => context.read<AppState>().setLang(null),
                ),
                Divider(height: 1, color: p.line),
                for (final lang in AppLang.values)
                  row(
                    title: lang.nativeName,
                    sub: null,
                    on: !app.followSystemLang && app.lang == lang,
                    onTap: () => context.read<AppState>().setLang(lang),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 音乐保存目录：三个位置二选一（公共音乐 / 系统下载 / 应用专属）。
class DownloadDirSheet extends StatefulWidget {
  const DownloadDirSheet({super.key});

  @override
  State<DownloadDirSheet> createState() => _DownloadDirSheetState();
}

class _DownloadDirSheetState extends State<DownloadDirSheet> {
  /// 真实路径（异步解析，先显示占位）
  final Map<DownloadDir, String> _paths = {};

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    for (final d in DownloadDir.values) {
      final path = await DownloadService.displayPath(d);
      if (!mounted) return;
      setState(() => _paths[d] = path);
    }
  }

  Future<void> _pick(DownloadDir d) async {
    final app = context.read<AppState>();
    final l = L.read(context);
    final messenger = ScaffoldMessenger.of(context);
    // 公共目录先要权限；拿不到就提示，但不阻止用户选择
    if (d.isPublic) {
      final ok = await DownloadService.ensurePermission(d);
      if (!ok && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.t('dir.needPermission'))),
        );
      }
    }
    await app.setDownloadDir(d);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final l = L.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        glassSheetHeader(context, l.t('dir.title'), l.t('dir.sub'),
            onClose: () => Navigator.pop(context)),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              children: [
                for (final d in DownloadDir.values)
                  InkWell(
                    onTap: () => _pick(d),
                    borderRadius: BorderRadius.circular(R.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 11),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            switch (d) {
                              DownloadDir.publicMusic =>
                                Icons.library_music_outlined,
                              DownloadDir.publicDownload =>
                                Icons.download_outlined,
                              DownloadDir.appPrivate => Icons.lock_outline_rounded,
                            },
                            size: 20,
                            color: app.downloadDir == d ? p.brand : p.t3,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.t(d.labelKey),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: app.downloadDir == d
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: app.downloadDir == d
                                        ? p.brand
                                        : p.t1,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _paths[d] ?? '…',
                                  style: TextStyle(fontSize: 10.5, color: p.t3),
                                ),
                              ],
                            ),
                          ),
                          if (app.downloadDir == d)
                            Icon(Icons.check_circle_rounded,
                                size: 18, color: p.brand),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
