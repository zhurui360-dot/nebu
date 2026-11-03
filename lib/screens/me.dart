import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_meta.dart';
import '../l10n/strings.dart';
import '../state/player_state.dart';
import '../services/download_service.dart';
import '../services/offline_cache.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/meta_source_sheet.dart';
import '../widgets/settings_sheets.dart';
import '../widgets/sheets.dart';
import 'sources.dart';
import '../utils/transitions.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  /// 边听缓存的大小 / 首数（进入页面时算一次，清完再算一次）
  int _cacheBytes = 0;
  int _cacheCount = 0;
  bool _cacheLoaded = false;

  /// 保存目录里已有的文件数（点了「音乐保存目录」才统计）
  int _savedFiles = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    _loadSavedFiles();
  }

  Future<void> _loadCacheSize() async {
    var bytes = 0, count = 0;
    try {
      bytes = await OfflineCache.totalSize();
      count = await OfflineCache.count();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _cacheBytes = bytes;
      _cacheCount = count;
      _cacheLoaded = true;
    });
  }

  /// 统计完成前不显示数字（避免闪一下"统计中"）
  String? get _cacheText {
    if (!_cacheLoaded || _cacheBytes <= 0) return null;
    final mb = _cacheBytes / 1024 / 1024;
    final size = mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    return '$size · $_cacheCount';
  }

  /// 当前内联展开的那一项（只保留「我的音乐」抽屉；
  /// 其余面板都改成屏幕正中的居中弹窗，见 [_openCentered]）
  String? _open;

  void _toggle(String key) => setState(() => _open = _open == key ? null : key);

  void _close() => setState(() => _open = null);

  /// 居中弹窗：二级设置面板统一走这里（不再就地展开）
  Future<void> _openCentered(Widget panel) {
    _close();
    return showCenteredGlassDialog<void>(context, panel);
  }

  /// 「我的音乐」内联抽屉：行 / 卡片下面「长出来」的那块面板
  Widget _panel(P p, String key, Widget child) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _open == key
          ? Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
              child: Glass(
                radius: 15,
                blur: Blur.thin,
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                topLight: false,
                elevated: false,
                child: SizedBox(width: double.infinity, child: child),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  /// 卡片 / 目录行点下去要跳设置页：先收起展开块再跳
  void _openSettings() {
    _close();
    Navigator.of(context).push(slidePageRoute(const SourcesScreen()));
  }

  /// 检查更新：没新版就不弹面板，只在下面提示一句
  Future<void> _checkUpdate(BuildContext context) async {
    final app = context.read<AppState>();
    final l = L.read(context);
    // 已经发现新版 / APK 已就绪：不再重复请求，直接打开更新面板
    final phase = app.update?.phase;
    if (phase != UpdatePhase.found && phase != UpdatePhase.ready) {
      await app.checkUpdate();
      if (!context.mounted) return;
    }
    final u = context.read<AppState>().update;
    final found = u != null &&
        (u.phase == UpdatePhase.found || u.phase == UpdatePhase.ready);
    if (!found) {
      final err = u?.phase == UpdatePhase.error ? (u?.error ?? '') : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err.isNotEmpty
            ? err
            : l.t('me.upToDate', {'v': AppMeta.version})),
      ));
      return;
    }
    if (!context.mounted) return;
    showGlassSheet(context, const UpdateSheet());
  }

  /// 清除边听缓存的确认走居中弹窗
  Widget _clearAudioSheet() {
    final l = L.read(context);
    return StatefulBuilder(builder: (ctx, _) {
      return ConfirmSheet(
        centered: true,
        title: l.t('me.clearAudio'),
        sub: _cacheText ?? l.t('clearAudio.subEmpty'),
        lines: [
          l.t('clearAudio.l1',
              {'mb': (_cacheBytes / 1024 / 1024).toStringAsFixed(0)}),
          l.t('clearAudio.l2'),
        ],
        confirm: l.t('confirm.clearAudio'),
        cancelLabel: l.cancel,
        danger: true,
        onResult: (ok) async {
          Navigator.of(ctx).pop();
          if (!ok) return;
          await context.read<AppState>().clearAudioCache();
          await _loadCacheSize();
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l.t('clearAudio.done'))));
        },
      );
    });
  }

  /// 清除全部数据：不可撤销，手打 yes 才能确认（居中弹窗）
  Widget _resetSheet(AppState app) {
    final l = L.read(context);
    return StatefulBuilder(builder: (ctx, _) {
      return ConfirmSheet(
        centered: true,
        title: l.t('reset.title'),
        sub: l.t('reset.sub'),
        lines: [
          l.t('reset.l0'),
          l.t('reset.l1', {'n': '${app.tracks.length}'}),
          l.t('reset.l2'),
          l.t('reset.l3'),
          l.t('reset.l4'),
          '',
          l.t('reset.l5'),
        ],
        confirm: l.t('confirm.clearAll'),
        cancelLabel: l.cancel,
        danger: true,
        // 不可撤销的操作，让用户手打 yes 再执行
        keyword: 'yes',
        onResult: (ok) async {
          Navigator.of(ctx).pop();
          if (!ok) return;
          final msg = await app.resetLibraryData();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final player = context.watch<PlayerState>();
    final l = L.of(context);
    // 迷你播放条出现时把内容垫高，别盖住「检查更新」
    final bottomPad = player.showMiniPlayer ? 178.0 : 110.0;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.only(top: 4, bottom: bottomPad),
        children: [
          PageHeader(title: l.tabMe),

          // 账户卡：点一下在卡片下面展开「已添加的目录」，不新开页面
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Glass(
                  radius: R.lg,
                  fill: p.brand.op(p.dark ? .10 : .07),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggle('mymusic'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.t('home.myMusic'),
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: p.t1)),
                                const SizedBox(height: 3),
                                Text(
                                    l.t('me.foldersIndexed', {
                                      'a': '${app.savedFolders.length}',
                                      'b': '${app.tracks.length}',
                                    }),
                                    style: TextStyle(
                                        fontSize: 12, color: p.t2)),
                              ],
                            ),
                          ),
                          Icon(
                            _open == 'mymusic'
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 22,
                            color: p.t3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _panel(
                  p,
                  'mymusic',
                  MyMusicSheet(inline: true, onOpenSettings: _openSettings),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 播放
          GroupBox(
            label: l.t('me.groupPlay'),
            children: [
              SettingRow(
                label: l.t('me.cacheLimit'),
                sub: l.t('me.cacheLimitSub'),
                value: _limitText(app.cacheLimitMb, l),
                onTap: () => _openCentered(const CacheLimitSheet(centered: true)),
              ),
              SettingRow(
                label: l.t('me.clearAudio'),
                sub: l.t('me.clearAudioSub'),
                value: _cacheText,
                valueColor: p.rose,
                onTap: _cacheBytes > 0
                    ? () => _openCentered(_clearAudioSheet())
                    : null,
              ),
              SettingRow(
                label: l.t('me.clearData'),
                sub: l.t('me.clearDataSub'),
                valueColor: p.rose,
                onTap: () => _openCentered(_resetSheet(app)),
              ),
            ],
          ),

          // 音乐库
          GroupBox(
            label: l.t('me.groupLibrary'),
            children: [
              SettingRow(
                label: l.t('me.onlineMeta'),
                sub: app.fillingMeta
                    ? '${(app.fillProgress * 100).round()}%'
                    : l.t('me.onlineMetaSub'),
                trailing: AppSwitch(
                  value: app.onlineMetaEnabled,
                  onChanged: (v) => context.read<AppState>().onlineMetaEnabled = v,
                ),
              ),
              SettingRow(
                label: l.t('me.metaSources'),
                sub:
                    '${app.metaSources.where((e) => e.builtIn).length} / ${app.metaSources.where((e) => !e.builtIn).length}',
                value: l.t('me.manage'),
                onTap: () => _openCentered(const MetaSourceSheet(centered: true)),
              ),
              SettingRow(
                label: l.t('me.filenameRule'),
                sub: app.filenamePattern.isEmpty ? null : app.filenamePattern,
                value: app.filenamePattern.isEmpty
                    ? l.t('me.filenameAuto')
                    : l.t('me.filenameCustom'),
                valueColor: app.filenamePattern.isEmpty ? null : p.brand,
                onTap: () => _openCentered(const FilenameRuleSheet(centered: true)),
              ),
            ],
          ),

          // 外观：主题三档（自动 / 浅色 / 深色）+ 语言
          GroupBox(
            label: l.t('me.groupAppearance'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Text(l.t('me.theme'),
                        style: TextStyle(fontSize: 13, color: p.t1)),
                    const Spacer(),
                    // 维语等长文案时整块等比缩小，不挤压出横向溢出
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: p.line,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Row(
                            children: [
                              _ThemeSeg(
                                label: l.t('me.themeAuto'),
                                on: app.themeMode == ThemeMode.system,
                                onTap: () => app.setTheme(ThemeMode.system),
                              ),
                              _ThemeSeg(
                                label: l.t('me.themeLight'),
                                on: app.themeMode == ThemeMode.light,
                                onTap: () => app.setTheme(ThemeMode.light),
                              ),
                              _ThemeSeg(
                                label: l.t('me.themeDark'),
                                on: app.themeMode == ThemeMode.dark,
                                onTap: () => app.setTheme(ThemeMode.dark),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SettingRow(
                label: l.t('me.language'),
                sub: app.lang.nativeName,
                value: app.followSystemLang ? l.t('lang.system') : null,
                onTap: () => _openCentered(const LanguageSheet()),
              ),
            ],
          ),

          // 下载与存储
          GroupBox(
            label: l.t('me.groupStorage'),
            children: [
              SettingRow(
                label: l.t('me.saveDir'),
                sub: _savedText(app, l),
                value: l.t(app.downloadDir.labelKey),
                onTap: () async {
                  await _openCentered(const DownloadDirSheet());
                  await _loadSavedFiles();
                },
              ),
            ],
          ),

          // 关于 / 更新
          GroupBox(
            label: l.t('me.groupAbout'),
            children: [
              SettingRow(
                  label: l.t('me.version'), value: 'v${AppMeta.version}'),
              Builder(builder: (context) {
                // 启动静默检查发现新版后，入口自然亮起（theme token，不硬编码颜色）
                final u = app.update;
                final found = u != null &&
                    (u.phase == UpdatePhase.found || u.phase == UpdatePhase.ready);
                return SettingRow(
                  label: found
                      ? '${l.t('me.newVersion')} v${u.latestVersion}'
                      : l.t('me.checkUpdate'),
                  value: found ? l.t('me.foundTag') : null,
                  valueColor: found ? p.brand : null,
                  onTap: () => _checkUpdate(context),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadSavedFiles() async {
    final app = context.read<AppState>();
    final n = await DownloadService.countFiles(app.downloadDir);
    if (!mounted) return;
    setState(() => _savedFiles = n);
  }

  /// 保存目录下面那行小字：目录里已有几首
  String? _savedText(AppState app, L l) {
    if (!app.downloadDir.isPublic) return l.t('dir.appSub');
    if (_savedFiles > 0) return l.t('unit.songs', {'n': '$_savedFiles'});
    return l.t('me.saveDirSub');
  }
}

/// 缓存上限的写法：1024 → 1G，0 → 不限制
String _limitText(int mb, L l) {
  if (mb <= 0) return l.t('cache.unlimited');
  if (mb >= 1024 && mb % 1024 == 0) return '${mb ~/ 1024}G';
  return '${mb}MB';
}

class _ThemeSeg extends StatelessWidget {
  const _ThemeSeg({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: on ? p.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: on
              ? [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 3, offset: const Offset(0, 1))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: on ? p.t1 : p.t3,
          ),
        ),
      ),
    );
  }
}
