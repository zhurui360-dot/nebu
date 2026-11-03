import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import '../utils/transitions.dart';
import '../widgets/webdav_sheet.dart';
import 'local_folders.dart';

/// 音乐来源：入口只有一个「添加音乐来源」，点进去再挑具体来源与目录。
///
/// 连过的账号不再单独占一张卡——账户信息跟着「已添加目录」走，
/// 想改账号、改目录、网盘失效了要重连，都在那一条目录里改。
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final l = L.of(context);

    // 真正连上的 WebDAV 账号（内置占位源不算，它的 baseUrl 是空的）
    final connected = app.webdavSources
        .where((s) => s.connected && (s.baseUrl ?? '').isNotEmpty)
        .toList();

    // 连了账号但还没挑目录的来源也列出来，否则账号会「消失」没法再操作
    final orphans = connected
        .where((s) => !app.savedFolders.any((f) => f.sourceId == s.id))
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  RoundIcon(Icons.chevron_left_rounded,
                      size: 40, onTap: () => Navigator.maybePop(context)),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(l.t('src.title'),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: p.t1)),
                        Text(l.songs(app.tracks.length),
                            style: TextStyle(fontSize: 12, color: p.t3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 46),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Text(
                      l.t('src.prose'),
                      style: TextStyle(
                          fontSize: 13.5, height: 1.7, color: p.t2),
                    ),
                  ),

                  // ---------- 唯一入口 ----------
                  _addEntry(p, context),

                  // 本地的快捷方式：不挑目录，直接扫手机里全部音乐
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 2, 20, 6),
                    child: app.localScanning
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: app.localProgress == 0
                                      ? null
                                      : app.localProgress,
                                  minHeight: 4,
                                  backgroundColor: p.line2,
                                  valueColor: AlwaysStoppedAnimation(p.brand),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l.t('src.localScanning', {
                                  'p': '${(app.localProgress * 100).round()}'
                                }),
                                style: TextStyle(fontSize: 12, color: p.t3),
                              ),
                            ],
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 2, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _scanLocal(context, app),
                              child: Text(l.t('src.scanAll'),
                                  style: TextStyle(fontSize: 12.5, color: p.brand)),
                            ),
                          ),
                  ),

                  // ---------- 已添加的目录（账户就挂在这里） ----------
                  if (app.savedFolders.isNotEmpty || orphans.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Text(l.t('src.folders'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: p.t3)),
                    ),
                    for (final f in app.savedFolders)
                      _folderRow(context, p, f),
                    // 连了账号还没选目录：点进去挑目录
                    for (final s in orphans)
                      _orphanRow(context, p, s),
                  ],

                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: p.mint.op(.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.mint.op(.18)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 15, color: p.mint),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(fontSize: 12, height: 1.65, color: p.t2),
                              children: [
                                TextSpan(
                                  text: '${l.t('src.privacyTitle')}\n',
                                  style: TextStyle(color: p.t1, fontWeight: FontWeight.w700),
                                ),
                                TextSpan(text: l.t('src.privacyBody')),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 唯一入口：点进去才选择来源
  Widget _addEntry(P p, BuildContext context) {
    final app = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(R.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.lg),
          onTap: () => showGlassSheet(context, const _SourcePickSheet()),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: p.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6A45E8), Color(0xFF33D6FF)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add_rounded, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('添加音乐来源',
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: p.t1)),
                      const SizedBox(height: 3),
                      Text(
                        app.savedFolders.isEmpty
                            ? '本地目录 / 网盘，点这里开始'
                            : '再加一个本地目录或网盘账号',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, height: 1.4, color: p.t3),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 一条已添加的目录：点开就能改账号 / 改目录 / 重扫 / 移除
  Widget _folderRow(BuildContext context, P p, SavedFolder f) {
    final app = context.watch<AppState>();
    final job = app.importJob;
    final scanning =
        job != null && !job.isDone && job.folderProgress.containsKey(f.path);
    final prog = scanning ? job.folderProgress[f.path]! : null;
    final addedN = scanning ? (job.folderAdded[f.path] ?? 0) : null;
    final pct = (prog != null && prog[1] > 0) ? (prog[0] / prog[1] * 100).round() : 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showGlassSheet(context, _FolderSheet(folder: f)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 9, 12, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scanning ? p.brand.op(.35) : p.line),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 16, color: p.t3),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: p.t1)),
                      const SizedBox(height: 2),
                      if (scanning && prog != null) ...[
                        Text(
                          '扫描中 ${prog[0]}/${prog[1]}（$pct%）'
                          '${addedN != null && addedN > 0 ? ' · 已入库 $addedN 首' : ''}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: p.brand),
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: prog[1] > 0 ? prog[0] / prog[1] : null,
                            minHeight: 3,
                            backgroundColor: p.line2,
                            valueColor: AlwaysStoppedAnimation(p.brand),
                          ),
                        ),
                      ] else
                        Text(
                          '${app.sourceNameOf(f.sourceId)} · '
                          '${f.fileCount} 个文件${f.includeSub ? ' · 含子目录' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.t3),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 连了账号、还没挑目录
  Widget _orphanRow(BuildContext context, P p, CloudSource s) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showGlassSheet(
              context, ImportSheet(sourceId: s.id, sourceName: s.name)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 9, 12, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_outlined, size: 16, color: p.t3),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: p.t1)),
                      const SizedBox(height: 2),
                      Text('已连接 · 还没选目录，点这里挑',
                          style: TextStyle(fontSize: 12, color: p.t3)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 选择来源：只做「添加入口」，不在这里列已连的账号
/// （账号信息挂在已添加的目录上，进目录编辑里看/改）
class _SourcePickSheet extends StatelessWidget {
  const _SourcePickSheet();

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final l = L.of(context);
    // 内置占位源（无地址）不算已连接
    final hasConnectedWebdav = app.webdavSources
        .any((s) => s.connected && (s.baseUrl ?? '').isNotEmpty);

    return GlassSheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          glassSheetHeader(context, l.t('src.add'), l.t('src.addSub'),
              onClose: () => Navigator.pop(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              children: [
                _opt(
                  p,
                  icon: Icons.smartphone_rounded,
                  colors: const [Color(0xFF1F9E8A), Color(0xFF5FD3BE)],
                  title: l.t('src.local'),
                  sub: l.t('src.localSub'),
                  onTap: () {
                    // 先抓 Navigator 再 pop，pop 后用 nav.context 挑目录
                    final nav = Navigator.of(context);
                    final app2 = context.read<AppState>();
                    nav.pop();
                    _pickLocalFolder(nav.context, app2);
                  },
                ),
                _opt(
                  p,
                  icon: Icons.add_rounded,
                  colors: const [Color(0xFF3C4A66), Color(0xFF6B7C9E)],
                  title: hasConnectedWebdav
                      ? l.t('src.webdavAdd')
                      : l.t('src.webdav'),
                  sub: l.t('src.webdavSub'),
                  onTap: () => _connectWebdav(context),
                ),
                // 夸克网盘 / 联通网盘暂时下线（v0.0.65）。
                // 原因：两家都没有对外开放的文件接口，验证码登录拿不到可用的
                // 目录读写权限，入口点进去只能空转。等有正式开放平台再接，
                // 底层留着的 CloudGatewaySheet / SmsLoginService 先不挂到界面上。
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 连新账号：连接成功就接着挑目录（账号信息之后挂在目录上）
  ///
  /// 注意：选择弹层这一步会先 pop，之后不能再拿它的 context 串弹层
  /// （deactivated context 会让 `context.mounted == false`，流程悄悄断掉）。
  /// 必须 pop 前先抓 Navigator，之后统一用 nav.context。
  Future<void> _connectWebdav(BuildContext context) async {
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    // 只认真正连上的账号：内置占位源（无地址）不算，否则第一次连接会被误判成「没有新增」
    bool real(CloudSource s) => s.connected && (s.baseUrl ?? '').isNotEmpty;
    final before = app.webdavSources.where(real).map((s) => s.id).toSet();
    nav.pop();
    await showGlassSheet(nav.context, const WebDavSheet());
    if (!nav.mounted) return;
    final added =
        app.webdavSources.where((s) => real(s) && !before.contains(s.id)).toList();
    if (added.isEmpty) return;
    final s = added.last;
    await showGlassSheet(
        nav.context, ImportSheet(sourceId: s.id, sourceName: s.name));
  }

  Widget _opt(
    P p, {
    required IconData icon,
    required List<Color> colors,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: p.t1)),
                      const SizedBox(height: 2),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.t3)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单条目录的编辑面板：账户信息、目录、重扫、移除都在这里
class _FolderSheet extends StatelessWidget {
  const _FolderSheet({required this.folder});
  final SavedFolder folder;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final src = app.sourceById(folder.sourceId);
    final isLocal = folder.sourceId == 'local';
    final name = app.sourceNameOf(folder.sourceId);

    final scanning = app.importJob != null &&
        !app.importJob!.isDone &&
        app.importJob!.folderProgress.containsKey(folder.path);

    return GlassSheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          glassSheetHeader(context, '已添加的目录', name,
              onClose: () => Navigator.pop(context)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv(p, '目录', folder.path),
                  const SizedBox(height: 11),
                  _kv(p, '来源', name),
                  if (src?.baseUrl != null) ...[
                    const SizedBox(height: 11),
                    _kv(p, '服务器', src!.baseUrl!),
                  ],
                  if ((src?.username ?? '').isNotEmpty) ...[
                    const SizedBox(height: 11),
                    _kv(p, '账号', src!.username!),
                  ],
                  const SizedBox(height: 11),
                  _kv(p, '内容',
                      '${folder.fileCount} 个文件${folder.includeSub ? ' · 含子目录' : ''}'),
                  if (!isLocal) ...[
                    const SizedBox(height: 14),
                    Text(
                      '网盘连不上、密码改过、地址变了，直接在这里改账号或换个目录，'
                      '不用重新添加来源。',
                      style: TextStyle(fontSize: 12, height: 1.6, color: p.t3),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    if (!isLocal)
                      Expanded(
                        child: _btn(p, '修改账号',
                            onTap: () => showGlassSheet(
                                context, WebDavSheet(sourceId: folder.sourceId))),
                      ),
                    if (!isLocal) const SizedBox(width: 10),
                    Expanded(
                      child: _btn(p, '修改目录',
                          onTap: () => _changeDir(context, folder)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _btn(p, scanning ? '扫描中…' : '重新扫描',
                          enabled: !scanning,
                          onTap: () async {
                            Navigator.pop(context);
                            final messenger = ScaffoldMessenger.of(context);
                            await context
                                .read<AppState>()
                                .rescanFolder(folder);
                            messenger.showSnackBar(const SnackBar(
                                content: Text('已开始重新扫描，只添加新歌')));
                          }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _btn(p, '移除',
                          danger: true,
                          onTap: () async {
                            Navigator.pop(context);
                            final messenger = ScaffoldMessenger.of(context);
                            await context
                                .read<AppState>()
                                .removeFolder(folder);
                            messenger.showSnackBar(
                                const SnackBar(content: Text('已移除这个目录')));
                          }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 换一个目录：网盘走目录选择器（新目录入库后删掉旧的），本地重新挑一个文件夹
  Future<void> _changeDir(BuildContext context, SavedFolder folder) async {
    if (folder.sourceId == 'local') {
      final nav = Navigator.of(context);
      final app = context.read<AppState>();
      final path =
          await nav.push<String>(slidePageRoute(const LocalFolderPicker()));
      if (path == null || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(content: Text('正在扫描新目录…')));
      await app.addLocalFolder(path);
      await app.removeFolder(folder);
      if (!nav.mounted) return;
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('已换成新目录')));
      return;
    }
    final app = context.read<AppState>();
    await showGlassSheet(
      context,
      ImportSheet(
        sourceId: folder.sourceId,
        sourceName: app.sourceNameOf(folder.sourceId),
        replaceFolder: folder,
      ),
    );
  }

  Widget _kv(P p, String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(fontSize: 11, color: p.t3)),
        const SizedBox(height: 3),
        Text(v,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: p.t1)),
      ],
    );
  }

  Widget _btn(P p, String label,
      {VoidCallback? onTap, bool danger = false, bool enabled = true}) {
    final fg = danger ? p.rose : p.t1;
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(color: enabled ? p.line2 : p.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled ? fg : p.t3)),
      ),
    );
  }
}

/// 不挑目录，直接扫手机里全部音乐
Future<void> _scanLocal(BuildContext context, AppState app) async {
  if (app.localScanning) return;
  final messenger = ScaffoldMessenger.of(context);
  final msg = await app.scanLocal();
  messenger.showSnackBar(SnackBar(content: Text(msg)));
}

/// 选一个本地目录 → 记住并扫描（和网盘目录同一套机制）
Future<void> _pickLocalFolder(BuildContext context, AppState app) async {
  final path = await Navigator.of(context)
      .push<String>(slidePageRoute(const LocalFolderPicker()));
  if (path == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('正在扫描这个目录…')));
  final msg = await app.addLocalFolder(path);
  if (!context.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(msg)));
}
