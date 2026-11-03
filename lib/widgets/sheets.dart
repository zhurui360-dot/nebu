import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/cloud/cloud_provider.dart';
import '../services/offline_cache.dart';
import '../app_meta.dart';
import '../services/tags/track_guesser.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import 'anchored_panel.dart';
import 'common.dart';

/// 统一的底部毛玻璃弹层
Future<Res?> showGlassSheet<Res>(BuildContext context, Widget child) {
  return showModalBottomSheet<Res>(
    context: context,
    isScrollControlled: true,
    barrierColor: const Color(0x59080A0F),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: child,
    ),
  );
}

/// 居中弹窗：和 [showGlassSheet] 同一套玻璃质感，
/// 但外壳带圆角玻璃卡片（不带把手），从屏幕正中弹出（「我的」页里的二级面板用这个）。
///
/// [child] 是弹窗正文（自带标题栏/按钮），外壳只负责居中 + 圆角玻璃 + 遮罩。
/// 弹窗本身可以随内容自适应高度，超高时内部滚动（约束 84% 屏高）。
Future<Res?> showCenteredGlassDialog<Res>(BuildContext context, Widget child) {
  return showDialog<Res>(
    context: context,
    barrierColor: const Color(0x59080A0F),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * .84,
        ),
        child: Glass(
          radius: R.xxl,
          blur: Blur.thick,
          clip: true,
          child: child,
        ),
      ),
    ),
  );
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child, this.showHandle = true});
  final Widget child;

  /// 从某一行下面弹出来时不要顶部把手（那是「从底部推上来」的语义）
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .88),
      child: Glass(
        radius: R.xxl,
        blur: Blur.thick,
        clip: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: showHandle ? 10 : 8),
            if (showHandle)
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: p.line2,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// 供其它面板复用的统一外壳：底部滑出的玻璃面板 + 顶部把手。
/// 想和「缓存大小上限」「我的音乐」长得一模一样就用它。
class GlassSheetShell extends StatelessWidget {
  const GlassSheetShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => _SheetShell(child: child);
}

/// 供其它面板复用的表头（大标题 + 副标题 + 右上角关闭）
Widget glassSheetHeader(
  BuildContext c,
  String title,
  String sub, {
  VoidCallback? onClose,
}) =>
    _sheetHeader(c, title, sub, onClose: onClose);

Widget _sheetHeader(BuildContext c, String title, String sub, {VoidCallback? onClose}) {
  final p = P.of(c);
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.t1)),
              const SizedBox(height: 3),
              Text(sub, style: TextStyle(fontSize: 12, color: p.t3)),
            ],
          ),
        ),
        if (onClose != null) RoundIcon(Icons.close_rounded, size: 34, onTap: onClose, color: p.t3),
      ],
    ),
  );
}

// ============================================================
// 导入：目录浏览器（逐级进入，勾选任意层作为导入目录）
// ============================================================
class ImportSheet extends StatefulWidget {
  const ImportSheet({
    super.key,
    required this.sourceId,
    required this.sourceName,
    this.replaceFolder,
  });
  final String sourceId;
  final String sourceName;

  /// 非空 = 这是「修改目录」，新目录扫进来之后把这条旧的删掉
  final SavedFolder? replaceFolder;

  @override
  State<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<ImportSheet> {
  String _cwd = '/';
  final _selected = <String>{};
  late Future<List<CloudEntry>> _future;
  bool _includeSub = true; // 默认包含子目录

  @override
  void initState() {
    super.initState();
    _future = _list();
  }

  Future<List<CloudEntry>> _list() =>
      context.read<AppState>().listEntries(widget.sourceId, _cwd);

  void _enter(String path) {
    setState(() {
      _cwd = path;
      _future = _list();
    });
  }

  void _up() {
    if (_cwd == '/' || _cwd.isEmpty) return;
    final parts = _cwd.split('/').where((e) => e.isNotEmpty).toList()..removeLast();
    _enter(parts.isEmpty ? '/' : '/${parts.join('/')}');
  }

  bool _isAudio(String name) =>
      MusicFormatX.fromExtension(name.split('.').last) != null;

  String get _displayPath => _cwd == '/' ? '根目录' : _cwd;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, '选择音乐目录', widget.sourceName,
              onClose: () => Navigator.pop(context)),

          // 面包屑 + 上一级
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                if (_cwd != '/')
                  InkWell(
                    onTap: _up,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_upward_rounded, size: 13, color: p.t2),
                          const SizedBox(width: 3),
                          Text('上一级', style: TextStyle(fontSize: 12.5, color: p.t2)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _displayPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: p.t3),
                  ),
                ),
              ],
            ),
          ),

          Flexible(
            child: FutureBuilder<List<CloudEntry>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('读不到目录', style: TextStyle(fontSize: 13, color: p.t1)),
                        const SizedBox(height: 6),
                        Text('${snap.error}'.replaceAll('CloudException', '').trim(),
                            style: TextStyle(fontSize: 12.5, height: 1.6, color: p.t3)),
                      ],
                    ),
                  );
                }

                final entries = snap.data ?? const <CloudEntry>[];
                final dirs = entries.where((e) => e.isDir).toList();
                final audioHere = entries.where((e) => !e.isDir && _isAudio(e.name)).length;

                if (dirs.isEmpty && audioHere == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                    child: Text('这个目录是空的', style: TextStyle(fontSize: 13.5, color: p.t3)),
                  );
                }

                return ListView(
                  shrinkWrap: true,
                  children: [
                    // 当前目录本身可被选中（里面有音频才有意义）
                    if (audioHere > 0)
                      _row(
                        p,
                        icon: Icons.my_library_music_rounded,
                        title: '导入当前目录',
                        sub: '$audioHere 个音频文件（不含子目录）',
                        selected: _selected.contains(_cwd),
                        onCheck: () => setState(() =>
                            _selected.contains(_cwd) ? _selected.remove(_cwd) : _selected.add(_cwd)),
                        onTap: () => setState(() =>
                            _selected.contains(_cwd) ? _selected.remove(_cwd) : _selected.add(_cwd)),
                        highlight: true,
                      ),

                    for (final d in dirs)
                      _row(
                        p,
                        icon: Icons.folder_rounded,
                        title: d.name,
                        sub: '文件夹 · 点右侧圆圈勾选',
                        selected: _selected.contains(d.path),
                        onCheck: () => setState(() =>
                            _selected.contains(d.path) ? _selected.remove(d.path) : _selected.add(d.path)),
                        onTap: () => _enter(d.path),
                      ),

                    // 包含子目录开关
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('包含子目录', style: TextStyle(fontSize: 13.5, color: p.t1)),
                                const SizedBox(height: 2),
                                Text('勾选目录下的所有层级一起扫描',
                                    style: TextStyle(fontSize: 12, color: p.t3)),
                              ],
                            ),
                          ),
                          AppSwitch(value: _includeSub, onChanged: (v) => setState(() => _includeSub = v)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () async {
                        final paths = _selected.toList();
                        final includeSub = _includeSub;
                        final app = context.read<AppState>();
                        final messenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(context);
                        nav.pop();
                        await app.startImport(
                          widget.sourceId,
                          paths,
                          includeSubDirs: includeSub,
                        );
                        // 「修改目录」：新目录入库后把原来那条删掉
                        final old = widget.replaceFolder;
                        if (old != null) await app.removeFolder(old);
                        // 目录已保存，扫描在后台跑，不挡着用
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(old == null
                                ? '目录已添加，正在后台扫描'
                                : '已换成新目录，正在后台扫描'),
                          ),
                        );
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: p.brandSolid,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _selected.isEmpty ? '勾选要导入的目录' : '导入 ${_selected.length} 个目录',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 一行：整行点击是「进入目录」，右侧圆圈是「勾选」
  Widget _row(
    P p, {
    required IconData icon,
    required String title,
    required String sub,
    required bool selected,
    required VoidCallback onCheck,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: highlight ? p.brand.op(.12) : const Color(0x29FFB84D),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon,
                  size: 18, color: highlight ? p.brand : const Color(0xFFC07600)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.t1)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12, color: p.t3)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 15, color: p.t3.op(.6)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onCheck,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? p.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: selected ? p.brand : p.line2, width: 1.5),
                ),
                child: selected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 导入：流水线进度（真实数字）
// ============================================================
class ImportProgressSheet extends StatelessWidget {
  const ImportProgressSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final job = app.importJob ?? ImportJob(step: 3, progress: 100);
    final done = job.isDone;

    final steps = [
      [
        '扫描音频文件并读取标签',
        '只下文件头 256KB · ID3v2 / Vorbis / MP4 Atom',
        job.step > 0
            ? '${job.done}/${job.total}'
            : (job.total == 0 ? '准备中' : '${job.done}/${job.total}'),
      ],
      ['写入曲库', '同源同路径自动去重，重复导入不会翻倍', job.step > 1 ? '${job.added} 首' : '待处理'],
      [
        '在线补全封面与歌词',
        '仅对缺标签的曲目发起，匹配后回写本地库',
        job.step > 2 ? '${job.untagged} 首' : '待处理',
      ],
    ];

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(
            context,
            job.failed ? '导入中断' : (done ? '导入完成' : '正在导入音乐库'),
            job.failed ? (job.error ?? '请稍后重试') : (done ? '可以在音乐库里搜索与播放了' : '源文件不会移动，只把索引收进来'),
            onClose: done
                ? () {
                    context.read<AppState>().dismissImport();
                    Navigator.pop(context);
                  }
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              children: List.generate(steps.length, (i) {
                final stDone = job.step > i;
                final cur = job.step == i && !done;
                final pct = i == 0 ? job.progress : (stDone ? 100.0 : 0.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: stDone ? p.mint.op(.14) : (cur ? p.brand.op(.14) : p.line),
                        ),
                        child: Center(
                          child: stDone
                              ? Icon(Icons.check_rounded, size: 13, color: p.mint)
                              : cur
                                  ? SizedBox(
                                      width: 6,
                                      height: 6,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle),
                                      ),
                                    )
                                  : Text('${i + 1}', style: TextStyle(fontSize: 11.5, color: p.t3)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(steps[i][0],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: stDone || cur ? p.t1 : p.t3,
                                )),
                            const SizedBox(height: 2),
                            Text(steps[i][1], style: TextStyle(fontSize: 12, color: p.t3)),
                            if (cur && i == 0) ...[
                              const SizedBox(height: 9),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: (pct / 100).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: p.line2,
                                  valueColor: AlwaysStoppedAnimation(p.brand),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        steps[i][2],
                        style: TextStyle(fontSize: 12, color: stDone || cur ? p.t2 : p.t3),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          if (done)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(14)),
              child: Text(
                job.failed
                    ? (job.error ?? '')
                    : '${job.added} 首入库，${job.tagged} 首读到内置标签\n'
                        '${job.untagged} 首缺标签，已补全封面与歌词\n'
                        '${job.skipped} 首已存在，自动跳过',
                style: TextStyle(fontSize: 12.5, height: 1.9, color: p.t2),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: done
                    ? () {
                        context.read<AppState>().dismissImport();
                        Navigator.pop(context);
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: p.brandSolid,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(done ? '完成' : '导入中…',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 播放队列
// ============================================================
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final app = context.read<AppState>();
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, '播放队列', '共 ${player.queue.length} 首',
              onClose: () => Navigator.pop(context)),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in player.queue.map(app.trackOf).whereType<Track>())
                  Builder(builder: (ctx) {
                    final id = t.id;
                    return TrackTile(
                      track: t,
                      subtitle: '${t.artist} · ${app.albumOf(t.albumId).name}',
                      playing: player.currentId == id,
                      trailing: player.currentId == id
                          ? const Equalizer()
                          : null,
                      onTap: () {
                        player.play(id);
                        Navigator.pop(context);
                      },
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

// ============================================================
// 版本更新（真实检查：拉 version.json）
// ============================================================
class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final u = app.update;
    if (u == null) return const SizedBox.shrink();

    Widget body;
    switch (u.phase) {
      case UpdatePhase.checking:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(context, '检查更新', '当前版本 v${AppMeta.version}', onClose: () => Navigator.pop(context)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
            ),
            Text('正在读取更新信息…', style: TextStyle(fontSize: 12, color: p.t3)),
            const SizedBox(height: 26),
          ],
        );
        break;

      case UpdatePhase.latest:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(context, '检查更新', '当前版本 v${AppMeta.version}'),
            _updateHead(p, Icons.check_rounded, p.mint, '已是最新版本', 'v${AppMeta.version}'),
            _primary(context, '知道了', () => Navigator.pop(context)),
            const SizedBox(height: 8),
          ],
        );
        break;

      case UpdatePhase.error:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(context, '检查更新', '当前版本 v${AppMeta.version}', onClose: () => Navigator.pop(context)),
            _updateHead(p, Icons.error_outline_rounded, const Color(0xFFC2412E), '检查失败', u.error ?? '未知错误'),
            _primary(context, '知道了', () => Navigator.pop(context)),
            const SizedBox(height: 8),
          ],
        );
        break;

      case UpdatePhase.downloading:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(context, '正在下载更新', '安装包会保存到应用缓存目录'),
            _updateHead(
              p,
              Icons.download_rounded,
              null,
              '${(u.progress * 100).round()}%',
              u.sizeText.isEmpty ? '正在下载…' : '共 ${u.sizeText}',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: u.progress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: p.line2,
                  valueColor: AlwaysStoppedAnimation(p.brand),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
        break;

      case UpdatePhase.ready:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(context, '下载完成', '已调起系统安装器'),
            _updateHead(
              p,
              Icons.check_rounded,
              p.mint,
              'v${u.latestVersion} 已就绪',
              '如果没看到安装界面，点下面的按钮重新打开',
            ),
            _primary(context, '打开安装器', () => app.installDownloaded()),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('稍后安装', style: TextStyle(fontSize: 12.5, color: p.t3)),
            ),
            const SizedBox(height: 6),
          ],
        );
        break;

      default: // found
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(context, '发现新版本', '应用内下载，完成后会自动弹出安装', onClose: () => Navigator.pop(context)),
            _updateHead(
              p,
              Icons.system_update_rounded,
              null,
              'v${u.latestVersion}',
              u.sizeText.isEmpty ? '有新版本可用' : u.sizeText,
            ),
            if (u.notes.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final n in u.notes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(top: 7, right: 8),
                              decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(2)),
                            ),
                            Expanded(
                              child: Text(n, style: TextStyle(fontSize: 12, height: 1.6, color: p.t2)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            _primary(context, '下载并安装', () => app.downloadAndInstall()),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('以后再说', style: TextStyle(fontSize: 12.5, color: p.t3)),
            ),
            const SizedBox(height: 6),
          ],
        );
    }

    return _SheetShell(child: body);
  }

  Widget _updateHead(P p, IconData icon, Color? color, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: color == null
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6A45E8), Color(0xFF2F8CFF)],
                    )
                  : null,
              color: color,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.white, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.t1)),
                const SizedBox(height: 3),
                Text(sub, style: TextStyle(fontSize: 12, height: 1.5, color: p.t3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _primary(BuildContext c, String label, VoidCallback onTap) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: p.brandSolid,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ============================================================
// 缓存大小上限：五档离散滑条，选完立刻持久化
// ============================================================
class CacheLimitSheet extends StatefulWidget {
  const CacheLimitSheet({
    super.key,
    this.inPanel = false,
    this.inline = false,
    this.centered = false,
  });

  /// true = 作为「从行下方弹出」的面板显示（不带把手）
  final bool inPanel;

  /// true = 直接在页面里向下展开（没有外壳、没有标题）
  final bool inline;

  /// true = 居中弹窗形态（独立 Dialog，带标题栏 + 关闭按钮）
  final bool centered;

  @override
  State<CacheLimitSheet> createState() => _CacheLimitSheetState();
}

class _CacheLimitSheetState extends State<CacheLimitSheet> {
  /// 1G / 5G / 10G / 20G / 不限制（0 = 不限制）
  static const _limits = [1024, 5120, 10240, 20480, 0];
  static const _labels = ['1G', '5G', '10G', '20G', '不限制'];

  int _index = 1;
  int _used = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final i = _limits.indexOf(context.read<AppState>().cacheLimitMb);
    _index = i < 0 ? 1 : i;
    _loadUsed();
  }

  Future<void> _loadUsed() async {
    var bytes = 0;
    try {
      bytes = await OfflineCache.totalSize();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _used = bytes;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.read<AppState>();
    final label = _labels[_index];
    final usedMb = (_used / 1024 / 1024).toStringAsFixed(0);

    final body = Padding(
      padding: EdgeInsets.fromLTRB(20, (widget.inline || widget.centered) ? 6 : 4,
          20, (widget.inline || widget.centered) ? 14 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800, color: p.t1)),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        _loaded ? '已用 $usedMb MB / 上限 $label' : '统计中…',
                        style: TextStyle(fontSize: 12, color: p.t3),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _index.toDouble(),
                  min: 0,
                  max: (_limits.length - 1).toDouble(),
                  divisions: _limits.length - 1,
                  activeColor: p.brand,
                  label: label,
                  onChanged: (v) => setState(() => _index = v.round()),
                  onChangeEnd: (v) => app.cacheLimitMb = _limits[v.round()],
                ),
                // 档位刻度说明
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final l in _labels)
                      Text(l, style: TextStyle(fontSize: 11, color: p.t3)),
                  ],
                ),
                const SizedBox(height: 10),
                Text('不限制时缓存会一直增长，占满手机存储前请手动清理。',
                    style: TextStyle(fontSize: 12, height: 1.6, color: p.t3)),
          ],
        ),
    );

    if (widget.inline) return body;

    // 居中弹窗：外壳（showCenteredGlassDialog）已带玻璃卡片，这里铺标题 + 内容
    if (widget.centered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, L.read(context).t('cache.title'),
              L.read(context).t('cache.sub'),
              onClose: () => Navigator.pop(context)),
          Flexible(child: SingleChildScrollView(child: body)),
        ],
      );
    }

    return _SheetShell(
      showHandle: !widget.inPanel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, L.read(context).t('cache.title'),
              L.read(context).t('cache.sub'),
              onClose: () => Navigator.pop(context)),
          body,
        ],
      ),
    );
  }
}

// ============================================================
// 音乐库 → 我的：编辑展示哪些行
// ============================================================

Future<void> showMyRowsSheet(BuildContext context) => showGlassSheet<void>(
      context,
      const _MyRowsSheet(),
    );

class _MyRowsSheet extends StatelessWidget {
  const _MyRowsSheet();

  /// 固定的四行
  static const _fixed = <(String, String, String)>[
    ('favorites', '我喜欢', '点过红心的歌'),
    ('bookmarks', '收藏', '收藏的专辑'),
    ('recent', '最近播放', '按时间倒序'),
    ('downloads', '下载列表', '已缓存到本地，断网也能播'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();

    // 固定四行 + 自己建的歌单（key 前缀 pl:，和 AppState.isMyRowVisible 对应）
    final items = <(String, String, String)>[
      ..._fixed,
      for (final pl in app.playlists)
        (
          'pl:${pl.id}',
          pl.name,
          '自建歌单 · ${pl.trackIds.length} 首',
        ),
    ];

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, '编辑「我的」', '关掉的条目不会出现在音乐库首页',
              onClose: () => Navigator.pop(context)),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              children: [
                for (final (key, title, sub) in items)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => app.setMyRowVisible(
                        key, !app.isMyRowVisible(key)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: p.t1)),
                                const SizedBox(height: 2),
                                Text(sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TextStyle(fontSize: 12, color: p.t3)),
                              ],
                            ),
                          ),
                          AppSwitch(
                            value: app.isMyRowVisible(key),
                            onChanged: (v) => app.setMyRowVisible(key, v),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                      app.playlists.isEmpty
                          ? '全部关掉也可以，只是这一块会空着'
                          : '自建歌单也可以放到首页「我的」里',
                      style: TextStyle(fontSize: 11.5, color: p.t3)),
                ),
                TextButton(
                  onPressed: () async {
                    for (final (key, _, _) in items) {
                      await app.setMyRowVisible(key, true);
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text('全部显示',
                      style: TextStyle(fontSize: 13, color: p.brand)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 统一确认抽屉（危险操作）
// ============================================================

/// 和「缓存大小上限」「我的音乐」完全同一套外壳的确认框：
/// 从底部滑出、顶部把手、标题 + 副标题、右上角关闭。
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  String sub = '',
  List<String> lines = const [],
  String confirm = '确认',
  String? cancelLabel,
  bool danger = false,
  String? keyword,
  /// 非空时从这一行下方弹出（而不是从屏幕底部推上来）
  BuildContext? anchor,
}) async {
  final panel = ConfirmSheet(
    title: title,
    sub: sub,
    lines: lines,
    confirm: confirm,
    cancelLabel: cancelLabel,
    danger: danger,
    keyword: keyword,
    inPanel: anchor != null,
  );
  final r = anchor != null
      ? await showAnchoredPanel<bool>(anchor, panel: panel)
      : await showGlassSheet<bool>(context, panel);
  return r == true;
}

class ConfirmSheet extends StatefulWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.sub,
    required this.lines,
    required this.confirm,
    required this.danger,
    this.keyword,
    this.inPanel = false,
    this.inline = false,
    this.centered = false,
    this.cancelLabel,
    this.onResult,
  });

  final bool inPanel;

  /// true = 直接在页面里向下展开（没有外壳、没有关闭按钮）
  final bool inline;

  /// true = 居中弹窗形态（独立 Dialog，不带把手，带关闭按钮）。
  /// 结果仍然走 [onResult] 回调，不用 Navigator.pop 返回值。
  final bool centered;

  /// 内联展开 / 居中弹窗时的结果回调：true 确认 / false 取消
  final ValueChanged<bool>? onResult;

  final String title;
  final String sub;
  final List<String> lines;
  final String confirm;

  /// 取消按钮文案（不传就用当前语言的「取消」）
  final String? cancelLabel;
  final bool danger;

  /// 非空时必须手打这个词（不区分大小写）才能确认
  final String? keyword;

  @override
  State<ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<ConfirmSheet> {
  final _c = TextEditingController();
  bool _ok = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final dangerColor = widget.danger ? p.rose : p.brandSolid;
    final needType = (widget.keyword ?? '').isNotEmpty;

    void resolve(bool v) {
      if (widget.inline || widget.centered) {
        widget.onResult?.call(v);
      } else {
        Navigator.pop(context, v);
      }
    }

    // 弹层里这段要能滚（高度受限，不滚会把按钮挤出屏幕）；
    // 内联展开时外层页面本来就能滚，直接铺开
    final linesCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in widget.lines)
          Padding(
            padding: EdgeInsets.only(bottom: l.isEmpty ? 8 : 3),
            child: Text(
              l,
              style: TextStyle(
                fontSize: l.isEmpty ? 6 : 12.5,
                height: 1.7,
                color: p.t2,
              ),
            ),
          ),
      ],
    );

    // 内联展开的头部：保留标题和副标题，去掉关闭按钮
    final inlineHead = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w700, color: p.t1)),
          if (widget.sub.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(widget.sub, style: TextStyle(fontSize: 12, color: p.t3)),
          ],
        ],
      ),
    );

    if (widget.inline) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          inlineHead,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: linesCol,
          ),
          if (needType) _typeBox(p),
          _buttons(p, dangerColor, needType, resolve),
        ],
      );
    }

    // 居中弹窗：外壳（showCenteredGlassDialog）已经带玻璃卡片，
    // 这里铺内容 + 关闭按钮（关闭 = 视作取消）
    if (widget.centered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, widget.title, widget.sub,
              onClose: () {
                widget.onResult?.call(false);
              }),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: linesCol,
            ),
          ),
          if (needType) _typeBox(p),
          _buttons(p, dangerColor, needType, resolve),
        ],
      );
    }

    return _SheetShell(
      showHandle: !widget.inPanel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, widget.title, widget.sub,
              onClose: () => Navigator.pop(context, false)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: linesCol,
            ),
          ),
          // 手打确认词的输入框固定在按钮上方，不会被滚出去
          if (needType) _typeBox(p),
          _buttons(p, dangerColor, needType, resolve),
        ],
      ),
    );
  }

  /// 手打确认词的输入框（危险操作）
  Widget _typeBox(P p) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          (widget.inline || widget.centered) ? 16 : 20,
          (widget.inline || widget.centered) ? 8 : 14,
          (widget.inline || widget.centered) ? 16 : 20,
          0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              L.read(context)
                  .t('confirm.typeHint', {'w': widget.keyword ?? ''}),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: p.rose)),
          const SizedBox(height: 6),
          TextField(
            controller: _c,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (v) => setState(() =>
                _ok = v.trim().toLowerCase() == widget.keyword!.toLowerCase()),
            style: TextStyle(fontSize: 14, color: p.t1),
            cursorColor: p.rose,
            decoration: InputDecoration(
              hintText: widget.keyword,
              hintStyle: TextStyle(fontSize: 14, color: p.t3),
              filled: true,
              fillColor:
                  p.dark ? const Color(0x14FFFFFF) : const Color(0x0F101320),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                borderSide: BorderSide(color: p.rose, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 取消 / 确认两个按钮
  Widget _buttons(
      P p, Color dangerColor, bool needType, ValueChanged<bool> resolve) {
    final tight = widget.inline || widget.centered;
    return Padding(
      padding: EdgeInsets.fromLTRB(tight ? 16 : 20, 14,
          tight ? 16 : 20, tight ? 12 : 18),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextButton(
                onPressed: () => resolve(false),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(color: p.line2),
                  ),
                ),
                child: Text(widget.cancelLabel ?? L.read(context).cancel,
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
                onPressed: (needType && !_ok) ? null : () => resolve(true),
                style: FilledButton.styleFrom(
                  backgroundColor: dangerColor,
                  disabledBackgroundColor: dangerColor.op(.28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: Text(widget.confirm,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

// ============================================================
// 我的音乐：已添加的目录
// ============================================================

/// 和「缓存大小上限」等面板同一套外壳：底部弹层 + 把手 + 标题。
Future<void> showMyMusicSheet(
  BuildContext context, {
  required VoidCallback onOpenSettings,
}) {
  return showGlassSheet<void>(
    context,
    MyMusicSheet(onOpenSettings: onOpenSettings),
  );
}

class MyMusicSheet extends StatelessWidget {
  const MyMusicSheet({
    super.key,
    required this.onOpenSettings,
    this.inPanel = false,
    this.inline = false,
  });

  /// true = 作为「从行下方弹出」的面板显示（不带把手）
  final bool inPanel;

  /// true = 直接在页面里向下展开
  final bool inline;

  /// 点目录行或底部「添加目录」都走这里（由调用方负责跳设置页）
  final VoidCallback onOpenSettings;

  /// 正在扫描（有导入任务在跑）
  bool _scanning(AppState app) => app.isScanning;

  /// 一键扫描全部已添加目录：本地目录走本地扫描，网盘目录走增量导入。
  /// 只补新歌，已有的曲目不会重复入库。
  Future<void> _scanAll(BuildContext context) async {
    final app = context.read<AppState>();
    final l = L.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final folders = app.savedFolders;
    if (folders.isEmpty) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.t('mymusic.noFolderToScan'))));
      return;
    }
    if (_scanning(app)) {
      messenger.showSnackBar(SnackBar(content: Text(l.t('mymusic.busy'))));
      return;
    }
    final before = app.tracks.length;
    messenger.showSnackBar(SnackBar(
      content: Text(l.t('mymusic.scanStart', {'n': '${folders.length}'})),
      duration: const Duration(seconds: 2),
    ));
    for (var i = 0; i < folders.length; i++) {
      try {
        // 每个目录占整条进度的一截，扫完一个再扫下一个，进度不会来回跳
        await app.rescanFolder(
          folders[i],
          base: i / folders.length,
          span: 1 / folders.length,
        );
        await app.importDone;
      } catch (_) {}
    }
    // 本地扫描是同步返回的；网盘导入在后台跑，这里只报告本地结果
    if (!context.mounted) return;
    final added = app.tracks.length - before;
    messenger.showSnackBar(SnackBar(
      content: Text(added > 0
          ? l.t('mymusic.scanDone', {'n': '$added'})
          : (_scanning(app)
              ? l.t('mymusic.scanRunning')
              : l.t('mymusic.scanNoNew'))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final folders = app.savedFolders;
    final scanning = _scanning(app);

    final l = L.of(context);
    final header = _sheetHeader(
      context,
      l.t('home.myMusic'),
      l.t('me.foldersIndexed', {
        'a': '${folders.length}',
        'b': '${app.tracks.length}',
      }),
      onClose: () => Navigator.pop(context),
    );

    final body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!inline) header,
          if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Icon(Icons.folder_open_rounded, size: 18, color: p.t3),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(l.t('mymusic.emptyRow'),
                        style: TextStyle(fontSize: 12.5, color: p.t3)),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Column(
                children: [
                  for (final f in folders)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (!inline) Navigator.pop(context);
                        onOpenSettings();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              f.sourceId == 'local'
                                  ? Icons.folder_rounded
                                  : Icons.cloud_outlined,
                              size: 18,
                              color: p.brand,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.path.split('/').lastWhere(
                                        (e) => e.isNotEmpty,
                                        orElse: () => f.path),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: p.t1),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${f.sourceId == 'local' ? l.t('src.localShort') : l.t('src.cloudShort')}'
                                    ' · ${l.t('unit.files', {'n': '${f.fileCount}'})}',
                                    style: TextStyle(
                                        fontSize: 11.5, color: p.t3),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 16, color: p.t3),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Divider(height: 1, color: p.line),
          InkWell(
            onTap: () => _scanAll(context),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Icon(
                    scanning
                        ? Icons.sync_rounded
                        : Icons.refresh_rounded,
                    size: 19,
                    color: scanning ? p.t3 : p.brand,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      scanning
                          ? l.t('mymusic.scanning', {
                              'p': '${app.scanProgress.round()}'
                            })
                          : l.t('mymusic.scan'),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scanning ? p.t3 : p.brand),
                    ),
                  ),
                  if (folders.isNotEmpty && !scanning)
                    Text('${folders.length} 个目录',
                        style: TextStyle(fontSize: 12, color: p.t3)),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: p.line),
          InkWell(
            onTap: () {
              if (!inline) Navigator.pop(context);
              onOpenSettings();
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 19, color: p.brand),
                  const SizedBox(width: 10),
                  Text('添加目录 / 管理音乐来源',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.brand)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );

    if (inline) return body;

    return _SheetShell(
      showHandle: !inPanel,
      child: body,
    );
  }
}

// ============================================================
// 歌单：命名 / 添加到歌单
// ============================================================

/// 输入歌单名称（新建与重命名共用），返回 null 表示取消
Future<String?> showPlaylistNameSheet(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirm = '创建',
}) {
  return showGlassSheet<String>(
    context,
    _PlaylistNameSheet(title: title, initial: initial, confirm: confirm),
  );
}

class _PlaylistNameSheet extends StatefulWidget {
  const _PlaylistNameSheet({
    required this.title,
    required this.initial,
    required this.confirm,
  });

  final String title;
  final String initial;
  final String confirm;

  @override
  State<_PlaylistNameSheet> createState() => _PlaylistNameSheetState();
}

class _PlaylistNameSheetState extends State<_PlaylistNameSheet> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, widget.title, '起一个以后一眼能认出来的名字',
              onClose: () => Navigator.pop(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: TextField(
              controller: _c,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: TextStyle(fontSize: 15, color: p.t1),
              cursorColor: p.brand,
              decoration: InputDecoration(
                hintText: '例如：深夜通勤',
                hintStyle: TextStyle(fontSize: 15, color: p.t3),
                filled: true,
                fillColor: p.dark ? const Color(0x14FFFFFF) : const Color(0x0F101320),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide(color: p.line2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide(color: p.line2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide(color: p.brand, width: 1.4),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('取消',
                          style: TextStyle(fontSize: 14.5, color: p.t2)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.brandSolid,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(widget.confirm,
                          style: const TextStyle(
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
}

/// 把歌曲加入歌单（可直接新建一个歌单，新歌单会带上这些歌）
Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required List<String> trackIds,
}) {
  return showGlassSheet<void>(
    context,
    _AddToPlaylistSheet(trackIds: trackIds),
  );
}

class _AddToPlaylistSheet extends StatelessWidget {
  const _AddToPlaylistSheet({required this.trackIds});

  final List<String> trackIds;

  Future<void> _createAndAdd(BuildContext context, AppState app) async {
    final name = await showPlaylistNameSheet(context, title: '新建歌单');
    if (name == null) return;
    await app.createPlaylist(name, trackIds: trackIds);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(
            context,
            '添加到歌单',
            trackIds.length > 1 ? '已选中 ${trackIds.length} 首' : '选一个歌单放进去',
            onClose: () => Navigator.pop(context),
          ),
          if (app.playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Text('还没有自建歌单，先新建一个',
                  style: TextStyle(fontSize: 13, color: p.t3)),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                children: [
                  for (final pl in app.playlists)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        await app.addToPlaylist(pl.id, trackIds);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                        child: Row(
                          children: [
                            Icon(Icons.queue_music_rounded,
                                size: 20, color: p.brand),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(pl.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: p.t1)),
                            ),
                            Text('${pl.trackIds.length} 首',
                                style: TextStyle(fontSize: 12, color: p.t3)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Divider(height: 1, color: p.line),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _createAndAdd(context, app),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 20, color: p.brand),
                  const SizedBox(width: 10),
                  Text('新建歌单',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: p.brand)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌单自身的操作菜单（重命名 / 删除），返回 'rename' 或 'delete'
Future<String?> showPlaylistActionsSheet(
  BuildContext context, {
  required String name,
  required int count,
}) {
  return showGlassSheet<String>(
    context,
    _SheetShell(
      child: Builder(builder: (ctx) {
        final p = P.of(ctx);
        Widget item(IconData icon, String label, Color color, String value) {
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(ctx, value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
              child: Row(
                children: [
                  Icon(icon, size: 19, color: color),
                  const SizedBox(width: 11),
                  Text(label,
                      style: TextStyle(fontSize: 14.5, color: color)),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHeader(ctx, name, '$count 首 · 自建歌单',
                onClose: () => Navigator.pop(ctx)),
            item(Icons.drive_file_rename_outline_rounded, '重命名',
                p.t1, 'rename'),
            item(Icons.delete_outline_rounded, '删除歌单',
                const Color(0xFFE4566A), 'delete'),
            const SizedBox(height: 8),
          ],
        );
      }),
    ),
  );
}

/// 单曲操作菜单：加入歌单 / 喜欢 / （在歌单里时）移出歌单
Future<void> showTrackActionsSheet(
  BuildContext context, {
  required Track track,
  String? removeFromPlaylistId,
}) {
  return showGlassSheet<void>(
    context,
    _TrackActionsSheet(track: track, removeFromPlaylistId: removeFromPlaylistId),
  );
}

class _TrackActionsSheet extends StatelessWidget {
  const _TrackActionsSheet({required this.track, this.removeFromPlaylistId});

  final Track track;
  final String? removeFromPlaylistId;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final l = L.of(context);
    final fav = app.isFavorite(track.id);
    final downloading = app.downloadingId == track.id;

    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
    }) {
      final c = color ?? p.t1;
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 19, color: c),
              const SizedBox(width: 11),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, color: c)),
              ),
            ],
          ),
        ),
      );
    }

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, track.title, track.artist,
              onClose: () => Navigator.pop(context)),
          item(Icons.playlist_add_rounded, l.t('track.addToPlaylist'), () {
            // 先取 Navigator 再关自己：关掉之后这个 context 已经失效，
            // 再用它开新弹层会拿不到祖先（Provider / Overlay）
            final nav = Navigator.of(context);
            nav.pop();
            showAddToPlaylistSheet(nav.context, trackIds: [track.id]);
          }),
          item(
            fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            fav ? l.t('track.unlike') : l.t('track.like'),
            () {
              app.toggleFavorite(track.id);
              Navigator.pop(context);
            },
            color: fav ? p.rose : null,
          ),
          // 下载到本地：存进「我的 → 音乐保存目录」
          item(
            downloading
                ? Icons.downloading_rounded
                : Icons.download_outlined,
            downloading
                ? l.t('track.downloading',
                    {'p': '${(app.downloadProgress * 100).round()}'})
                : l.t('track.download'),
            () async {
              if (downloading) return;
              final nav = Navigator.of(context);
              final hostCtx = nav.context;
              final appRef = context.read<AppState>();
              final lr = L.read(hostCtx);
              final messenger = ScaffoldMessenger.of(hostCtx);
              nav.pop();
              try {
                final path = await appRef.downloadTrack(track.id);
                messenger.showSnackBar(
                    SnackBar(content: Text(lr.t('dir.saved', {'p': path}))));
              } catch (e) {
                messenger.showSnackBar(
                    SnackBar(content: Text(lr.t('dir.failed', {'e': '$e'}))));
              }
            },
            color: downloading ? p.brand : null,
          ),
          if (removeFromPlaylistId != null)
            item(Icons.playlist_remove_rounded, l.t('track.removeFromPlaylist'),
                () {
              app.removeFromPlaylist(removeFromPlaylistId!, track.id);
              Navigator.pop(context);
            }),
          item(Icons.delete_outline_rounded, l.delete, () async {
            // 先取 Navigator 再关自己：关掉之后这个 context 已经失效
            final nav = Navigator.of(context);
            // 关掉当前菜单那一帧之后，nav.context 才是稳定的祖先上下文
            final hostCtx = nav.context;
            final appRef = context.read<AppState>();
            final playerRef = context.read<PlayerState>();
            final lr = L.read(hostCtx);
            nav.pop();
            final ok = await showConfirmSheet(
              hostCtx,
              title: lr.t('track.deleteTitle'),
              sub: '${track.title} · ${track.artist}',
              lines: [
                lr.t('track.deleteBody1'),
                lr.t('track.deleteBody2'),
                lr.t('track.deleteBody3'),
              ],
              confirm: lr.delete,
              cancelLabel: lr.cancel,
              danger: true,
            );
            if (!ok) return;
            // 先摘队列再删曲库：正在播的这首会顺延到下一首
            await playerRef.removeFromQueue(track.id);
            await appRef.deleteTrack(track.id);
            if (!hostCtx.mounted) return;
            ScaffoldMessenger.of(hostCtx).showSnackBar(SnackBar(
                content: Text(lr.t('track.deleted', {'t': track.title}))));
          }, color: p.rose),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ============================================================
// 按文件名识别：模板设置 + 实时预览
// ============================================================

/// 常见命名模板（pattern 为空 = 智能识别）
const _filenamePresets = <String, String>{
  '智能识别': '',
  '歌手 - 歌名': '{artist} - {title}',
  '歌名 - 歌手': '{title} - {artist}',
  '序号. 歌手 - 歌名': '{track}. {artist} - {title}',
  '歌手 - 专辑 - 歌名': '{artist} - {album} - {title}',
};

class FilenameRuleSheet extends StatefulWidget {
  const FilenameRuleSheet({
    super.key,
    this.inPanel = false,
    this.inline = false,
    this.centered = false,
    this.onDone,
  });

  /// true = 作为「从行下方弹出」的面板显示（不带把手）
  final bool inPanel;

  /// true = 直接在页面里向下展开
  final bool inline;

  /// true = 居中弹窗形态（独立 Dialog，带标题栏 + 关闭按钮）。
  /// 保存完成走 Navigator.pop 关闭。
  final bool centered;

  /// 内联模式下保存完成后收起（弹层模式用 Navigator.pop）
  final VoidCallback? onDone;

  @override
  State<FilenameRuleSheet> createState() => _FilenameRuleSheetState();
}

class _FilenameRuleSheetState extends State<FilenameRuleSheet> {
  late String _draft = context.read<AppState>().filenamePattern;
  late final TextEditingController _c = TextEditingController(text: _draft);
  late String _sep = context.read<AppState>().filenameSep;
  late final TextEditingController _sepC = TextEditingController(text: _sep);
  bool _custom = false;

  static const _sample = '01. 周杰伦 - 晴天.flac';

  @override
  void initState() {
    super.initState();
    _custom = _draft.isNotEmpty && !_filenamePresets.containsValue(_draft);
  }

  @override
  void dispose() {
    _c.dispose();
    _sepC.dispose();
    super.dispose();
  }

  void _pick(String pattern) {
    setState(() {
      _draft = pattern;
      _c.text = pattern;
      _custom = false;
    });
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    app.filenameSep = _sep;
    app.filenamePattern = _draft;
    if (widget.inline) {
      widget.onDone?.call();
    } else {
      nav.pop();
    }
    final msg = await app.reapplyFilenameRule();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    // 预览要用「草稿里」的间隔符号，算完立刻还原，别改到全局设置
    final oldSep = TrackGuesser.separators;
    TrackGuesser.separators = _sep.trim().isEmpty ? '-–—_·' : _sep.trim();
    final preview = _draft.isEmpty ? null : TrackGuesser.previewWith(_draft, _sample);
    TrackGuesser.separators = oldSep;
    final auto = _draft.isEmpty;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.inline && !widget.centered)
          _sheetHeader(context, '按文件名识别', '没读到内嵌标签时，用文件名切出歌名和歌手',
              onClose: () => Navigator.pop(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _filenamePresets.entries)
                    _chip(p, e.key, !_custom && _draft == e.value,
                        () => _pick(e.value)),
                  _chip(p, '自定义', _custom, () {
                    setState(() {
                      _custom = true;
                      if (_draft.isEmpty) {
                        _draft = '{artist} - {title}';
                        _c.text = _draft;
                      }
                    });
                  }),
                ],
              ),
              if (_custom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _c,
                  style: TextStyle(fontSize: 14, color: p.t1),
                  cursorColor: p.brand,
                  onChanged: (v) => setState(() => _draft = v.trim()),
                  decoration: InputDecoration(
                    hintText: '{artist} - {title}',
                    hintStyle: TextStyle(fontSize: 14, color: p.t3),
                    filled: true,
                    fillColor: p.dark
                        ? const Color(0x14FFFFFF)
                        : const Color(0x0F101320),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.md),
                      borderSide: BorderSide(color: p.line2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.md),
                      borderSide: BorderSide(color: p.line2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.md),
                      borderSide: BorderSide(color: p.brand, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text('可用占位符：{artist} 歌手 · {title} 歌名 · {album} 专辑 · {track} 序号',
                    style: TextStyle(fontSize: 11.5, height: 1.5, color: p.t3)),
              ],
              if (!auto) ...[
                const SizedBox(height: 14),
                Text('间隔符号',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: p.t2)),
                const SizedBox(height: 6),
                TextField(
                  controller: _sepC,
                  style: TextStyle(fontSize: 14, color: p.t1),
                  cursorColor: p.brand,
                  onChanged: (v) => setState(() => _sep = v),
                  decoration: InputDecoration(
                    hintText: '-–—_·',
                    hintStyle: TextStyle(fontSize: 14, color: p.t3),
                    filled: true,
                    fillColor: p.dark
                        ? const Color(0x14FFFFFF)
                        : const Color(0x0F101320),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.md),
                      borderSide: BorderSide(color: p.line2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.md),
                      borderSide: BorderSide(color: p.line2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.md),
                      borderSide: BorderSide(color: p.brand, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('模板里写这些符号中的任意一个，匹配时都会互通：填了 - _ 之后，'
                    '「歌手 - 歌名」也能吃「歌手_歌名」。',
                    style: TextStyle(fontSize: 11.5, height: 1.5, color: p.t3)),
              ],
              const SizedBox(height: 14),
              // 实时预览：拿一个典型文件名试切
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('预览 · $_sample',
                        style: TextStyle(fontSize: 11.5, color: p.t3)),
                    const SizedBox(height: 7),
                    if (auto)
                      Text('智能识别会参考目录名、平台前后缀和标签，按最常见的写法切分',
                          style: TextStyle(
                              fontSize: 12.5, height: 1.6, color: p.t2))
                    else if (preview == null)
                      Text('这个模板匹配不上示例文件，换个写法试试',
                          style: TextStyle(fontSize: 12.5, color: p.rose))
                    else
                      Row(
                        children: [
                          _kv(p, '歌名', preview.title),
                          const SizedBox(width: 14),
                          _kv(p, '歌手', preview.artist ?? '—'),
                          if (preview.album != null) ...[
                            const SizedBox(width: 14),
                            _kv(p, '专辑', preview.album!),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.brandSolid,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text('保存并按新规则重新识别',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              Text('只会重算「没读到内嵌标签」的歌；标签正常的不会被覆盖。',
                  style: TextStyle(fontSize: 11.5, height: 1.6, color: p.t3)),
            ],
          ),
        ),
      ],
    );

    final body = widget.inline
        ? content
        : SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: content,
          );
    if (widget.inline) return body;

    // 居中弹窗：标题 + 说明放最顶部（外壳只负责玻璃卡片，不铺标题）
    if (widget.centered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetHeader(context, '按文件名识别', '没读到内嵌标签时，用文件名切出歌名和歌手',
              onClose: () => Navigator.pop(context)),
          Flexible(child: body),
        ],
      );
    }

    return _SheetShell(
      showHandle: !widget.inPanel,
      child: body,
    );
  }

  Widget _kv(P p, String k, String v) {
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: 10.5, color: p.t3)),
          const SizedBox(height: 2),
          Text(v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: p.t1)),
        ],
      ),
    );
  }

  Widget _chip(P p, String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? p.brand.op(.14) : p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? p.brand : p.line2),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? p.brand : p.t2)),
      ),
    );
  }
}
