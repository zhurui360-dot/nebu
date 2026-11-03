import 'dart:io';
import 'dart:ui' show ImageFilter, FontFeature;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'category.dart';

/// 以「从下往上」的方式打开播放页
Future<void> showPlayer(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      // 播放页是整屏不透明的，标成 opaque 后下层页面不再重复绘制
      opaque: true,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => const PlayerScreen(),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
          // 同上：整页先栅格化再位移，动画期间只挪图层不重绘
          child: RepaintBoundary(child: child),
        );
      },
    ),
  );
}

/// 播放页：整体强制深色（与参考样式一致，封面/歌词两态）。
/// - 封面页：大封面 + 上方歌手 + 下方专辑名 + 当句歌词 + 标题行
/// - 歌词页：双语逐行滚动，当前句高亮，点任意行跳播
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final app = context.watch<AppState>();
    final track = player.current;
    final album = app.albumOf(track.albumId);

    // 播放页永远是深色氛围（不管全局主题），文字都直接压在模糊封面上
    return Theme(
      data: AppTheme.build(Brightness.dark),
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1016),
        body: Stack(
          children: [
            _Backdrop(track: track),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _Header(track: track, lyricMode: player.mode == PlayerMode.lyric),
                  Expanded(
                    child: player.mode == PlayerMode.lyric
                        // 歌词页：点歌词行 = 跳到那一句（行自己处理），
                        // 点歌词旁边的空白 = 切回封面页
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                context.read<PlayerState>().toggleMode(),
                            child: player.hasLyrics
                                ? _LyricView(
                                    lines: player.lyrics,
                                    active: player.lyricIndex)
                                : const _NoLyric(),
                          )
                        : _CoverView(track: track, album: album),
                  ),
                  _BottomPanel(track: track),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 背景：封面放大高斯模糊 + 深色压暗层；没有封面时退回深色渐变
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final path = track.coverPath;
    final hasCover = path != null && File(path).existsSync();

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF11141B)),
        if (hasCover)
          Positioned.fill(
            // iOS 磨砂配方：blur(70) + 饱和度提升，封面颜色在上下未覆盖区
            // 以「润」的模糊态延伸铺满整个页面
            child: RepaintBoundary(
              child: ImageFiltered(
                imageFilter: frostedFilter(70),
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // 要被 70σ 模糊掉的图，解码到 320px 完全够用；
                  // 按原图解码（动辄 2000px）再模糊，正是切歌卡顿的主因
                  cacheWidth: 320,
                ),
              ),
            ),
          )
        else
          // 没有封面：拿品牌图当封面用，同样高斯模糊 + 提饱和度铺满，
          // 于是页面氛围色来自 logo，而不是一块死板的灰渐变
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: frostedFilter(70),
              child: const BrandCover(),
            ),
          ),
        // 深色渐变压底，保证白字可读；整体调轻，
        // 让封面颜色在上下边缘的模糊延伸能透出来
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x330B0D12),
                Color(0x520B0D12),
                Color(0x990B0D12),
                Color(0xE60B0D12),
              ],
              stops: [0, .38, .78, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// 顶栏：歌词页 = 标题 + 歌手；封面页 = 只放歌手名（大写字母间距）
class _Header extends StatelessWidget {
  const _Header({required this.track, required this.lyricMode});
  final Track track;
  final bool lyricMode;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 6),
          RoundIcon(Icons.keyboard_arrow_down_rounded, size: 40,
              onTap: () => Navigator.of(context).maybePop()),
          Expanded(
            child: lyricMode
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.t2)),
                    ],
                  )
                : Text(
                    track.artist.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        letterSpacing: 2.6, color: p.t3),
                  ),
          ),
          const SizedBox(width: 46),
        ],
      ),
    );
  }
}

class _LyricView extends StatefulWidget {
  const _LyricView({required this.lines, required this.active});
  final List<LyricLine> lines;
  final int active;

  @override
  State<_LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<_LyricView> {
  final _keys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _keys.addAll(List.generate(widget.lines.length, (_) => GlobalKey()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  @override
  void didUpdateWidget(covariant _LyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
    }
  }

  void _scrollToActive() {
    final ctx = _keys[widget.active.clamp(0, _keys.length - 1).toInt()].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerState>();
    final showTrans = player.showTrans;

    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
        stops: [0, .14, .86, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 60),
        child: Column(
          children: [
            for (var i = 0; i < widget.lines.length; i++)
              _line(context, widget.lines[i], i == widget.active, showTrans, _keys[i]),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, LyricLine line, bool on, bool showTrans, GlobalKey key) {
    // 歌词行原本给的是「全空 style」，会绕开主题字体（真机上退到系统默认，
    // 测试环境里直接变成方块）。这里继承外层字体，只覆盖大小/粗细/颜色。
    final base = DefaultTextStyle.of(context).style;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => context.read<PlayerState>().seekTo(line.time),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: on ? 12 : 9),
        alignment: Alignment.center,
        child: Column(
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: base.copyWith(
                fontSize: on ? 19.5 : 15,
                height: 1.45,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? Colors.white : Colors.white.op(.38),
                letterSpacing: -.2,
              ),
              child: Text(line.text, textAlign: TextAlign.center),
            ),
            if (showTrans && line.trans != null && line.trans!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                line.trans!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: on ? 12.5 : 11,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: on ? Colors.white.op(.78) : Colors.white.op(.26),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 该曲目没有内嵌歌词、同目录也没有 .lrc 时显示
class _NoLyric extends StatelessWidget {
  const _NoLyric();

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined, size: 34, color: p.t3),
          const SizedBox(height: 12),
          Text(L.of(context).t('player.noLyric'),
              style: TextStyle(fontSize: 14.5, color: p.t2)),
          const SizedBox(height: 6),
          Text(L.of(context).t('player.lrcHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.6, color: p.t3)),
        ],
      ),
    );
  }
}

/// 封面页（参考样式二）：上方歌手 → 大封面 → 专辑名 → 当句歌词 → 标题行。
/// 支持上下拖动切歌：整块内容（封面 + 信息行）跟手纵移、淡出并微缩，
/// 超过屏幕高度 18%（或快速甩动）触发上一首 / 下一首。
class _CoverView extends StatefulWidget {
  const _CoverView({required this.track, required this.album});
  final Track track;
  final Album album;

  @override
  State<_CoverView> createState() => _CoverViewState();
}

class _CoverViewState extends State<_CoverView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addListener(_onTick);

  double _dy = 0; // 内容纵向位移（跟手）
  String? _warmedFor; // 已经预热过封面的曲目，避免重复解码

  /// 预热相邻曲目的封面：切歌时图片已在图片缓存里，那一帧就不会掉。
  void _warmNeighborCovers() {
    final player = context.read<PlayerState>();
    final app = context.read<AppState>();
    final id = player.currentId;
    if (id.isEmpty || _warmedFor == id) return;
    _warmedFor = id;
    final q = player.queue;
    final i = q.indexOf(id);
    if (i < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final d in const [-1, 1]) {
        final j = i + d;
        if (j < 0 || j >= q.length) continue;
        final path = app.trackOf(q[j])?.coverPath;
        if (path == null || path.isEmpty) continue;
        if (!File(path).existsSync()) continue;
        precacheImage(FileImage(File(path)), context, onError: (_, __) {});
      }
    });
  }
  double _from = 0;
  double _to = 0;
  bool _busy = false; // 正在切歌，忽略新的拖动

  void _onTick() {
    if (!mounted) return;
    setState(() {
      _dy = _from + (_to - _from) * Curves.easeOutCubic.transform(_anim.value);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _slideTo(double target, {VoidCallback? onDone}) {
    _from = _dy;
    _to = target;
    _anim.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      onDone?.call();
    });
  }

  void _endDrag(DragEndDetails d, double height) {
    if (_busy) return;
    final v = d.primaryVelocity ?? 0;
    final threshold = height * .18;
    final goNext = _dy < -threshold || v < -600; // 上滑 → 下一首
    final goPrev = _dy > threshold || v > 600; // 下滑 → 上一首
    if (!goNext && !goPrev) {
      _slideTo(0); // 不足阈值 → 回弹
      return;
    }

    _busy = true;
    final dir = goNext ? -1.0 : 1.0;
    // ① 旧内容整块滑出
    _slideTo(dir * height * .85, onDone: () async {
      final player = context.read<PlayerState>();
      if (goNext) {
        await player.next();
      } else {
        await player.prev();
      }
      if (!mounted) return;
      // ② 新内容从另一侧滑入
      setState(() {
        _dy = -dir * height * .28;
        _from = _dy;
        _to = 0;
      });
      _anim.forward(from: 0).whenComplete(() {
        _busy = false;
        if (mounted) setState(() => _dy = 0);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final player = context.watch<PlayerState>();
    final app = context.watch<AppState>();
    final track = widget.track;
    final album = widget.album;
    _warmNeighborCovers();
    // 封面通栏铺满整个屏幕宽度，无边框、无内边距
    final size = MediaQuery.of(context).size;
    final side = size.width;
    final height = size.height;
    final lyric = _currentLine(player);
    // 跟手上下移动时同步淡出 + 轻微缩小，做出"整块内容跟着滑走"的层次
    final travel = (_dy.abs() / (height * .55)).clamp(0.0, 1.0);
    final opacity = (1 - travel * 1.15).clamp(0.0, 1.0);
    final scale = 1 - travel * .06;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // 上下滑动切歌：整块内容（封面 + 专辑名 + 歌词 + 标题行）一起跟手位移
      onVerticalDragUpdate: (d) {
        if (_busy) return;
        setState(() => _dy = (_dy + d.delta.dy).clamp(-height, height));
      },
      onVerticalDragEnd: (d) => _endDrag(d, height),
      child: Transform.translate(
        offset: Offset(0, _dy),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 点封面 → 切到歌词页；封面通栏，上下边缘模糊融入背景
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: player.toggleMode,
                    // 歌词进度每几百毫秒推一次，封面单独成层，避免跟着重绘
                    child: RepaintBoundary(
                      child: _MeltCover(
                        albumId: track.albumId,
                        side: side,
                        coverPath: track.coverPath,
                      ),
                    ),
                  ),
                  // 封面通栏后，其余内容自己留出水平内边距
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (album.name.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              album.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.6,
                                  color: p.t3),
                            ),
                          ),
                        ],
                        if (lyric.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          GestureDetector(
                            onTap: player.toggleMode,
                            child: Text(
                              lyric,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.55,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -.3,
                                          color: Colors.white)),
                                  const SizedBox(height: 4),
                                  // 歌手名可点：进这位歌手的歌单
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: track.artist.isEmpty
                                        ? null
                                        : () => pushArtist(context, track.artist),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: p.t2)),
                                        ),
                                        if (track.artist.isNotEmpty) ...[
                                          const SizedBox(width: 2),
                                          Icon(Icons.chevron_right_rounded,
                                              size: 14, color: p.t2),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            RoundIcon(
                              Icons.lyrics_outlined,
                              size: 34,
                              color: p.t2,
                              onTap: player.toggleMode,
                            ),
                            const SizedBox(width: 2),
                            RoundIcon(
                              app.isFavorite(track.id)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 38,
                              color: app.isFavorite(track.id) ? p.rose : p.t2,
                              onTap: () => app.toggleFavorite(track.id),
                            ),
                            const SizedBox(width: 2),
                            RoundIcon(
                              Icons.more_vert_rounded,
                              size: 34,
                              color: p.t2,
                              onTap: () => _showMore(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// 与背景融为一体的封面：通栏铺满屏幕宽度、无边框，
/// 只做上下两边的模糊融合——用垂直 alpha 渐变蒙版把上下边缘融掉，
/// 封面看起来是从播放器的暗色氛围里透出来的，看不到任何边界。
class _MeltCover extends StatelessWidget {
  const _MeltCover({
    required this.albumId,
    required this.side,
    required this.coverPath,
  });
  final String albumId;
  final double side;
  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    final cover = CoverArt(
      albumId: albumId,
      size: side,
      radius: 0, // 边缘会被蒙版融掉，不需要圆角
      coverPath: coverPath,
    );

    final hasCover = coverPath != null && File(coverPath!).existsSync();
    // 没有封面就用品牌标顶替；下面这套融边蒙版照样套在它身上，
    // 视觉上和真封面完全一致，只是画面内容是 logo
    final art = hasCover
        ? cover
        : SizedBox(width: side, height: side, child: const BrandCover());

    // 垂直渐隐：顶部融 12%，底部融 22%（往歌词区过渡更长）
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        stops: [0, .12, .78, 1],
      ).createShader(rect),
      child: art,
    );
  }
}

/// 底部面板：歌词页多一排（翻译开关 / 喜欢 / 更多），下面是进度条 + 控制键
class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final player = context.watch<PlayerState>();
    final app = context.watch<AppState>();
    final lyricMode = player.mode == PlayerMode.lyric;

    // 播放控制面板：深色玻璃只留 5% 填充，靠模糊兜住可读性
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x000B0D12), Color(0x0D0B0D12), Color(0x0D0B0D12)],
              stops: [0, .55, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 歌词页的小操作行：封面切换 / 翻译开关 / 喜欢 / 更多
              if (lyricMode)
                Row(
                  children: [
                    _Ctl(
                      icon: Icons.album_outlined,
                      size: 21,
                      onTap: player.toggleMode,
                      tooltip: L.of(context).t('player.cover'),
                    ),
                    const SizedBox(width: 8),
                    if (player.hasTrans)
                      _Ctl(
                        icon: Icons.translate_rounded,
                        size: 20,
                        active: player.showTrans,
                        onTap: player.toggleTrans,
                        tooltip: player.showTrans
                            ? L.of(context).t('player.hideTrans')
                            : L.of(context).t('player.showTrans'),
                      )
                    else
                      const SizedBox(width: 34),
                    const Spacer(),
                    RoundIcon(
                      app.isFavorite(track.id)
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 36,
                      color: app.isFavorite(track.id) ? p.rose : p.t2,
                      onTap: () => app.toggleFavorite(track.id),
                    ),
                    const SizedBox(width: 8),
                    RoundIcon(
                      Icons.more_vert_rounded,
                      size: 32,
                      color: p.t2,
                      onTap: () => _showMore(context),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              // 只把「进度」这一条通知通道交给进度条：
              // 播放页其余部分不再随进度 5Hz 重建
              _ProgressBar(
                pos: player.pos,
                onSeek: player.seekRatio,
                duration: player.duration,
                playing: player.playing,
              ),
              // 直链播不出来时明确告知原因，并提供重试
              if (player.playError != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.fromLTRB(11, 9, 6, 9),
                  decoration: BoxDecoration(
                    color: const Color(0x1AC2412E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x2EC2412E)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_off_rounded, size: 16, color: Color(0xFFFF8A7A)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L.of(context).t('player.preview'),
                              style: TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              player.playError!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, height: 1.5, color: Color(0xFFFF8A7A)),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: player.retry,
                        child: const Text('重试', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 播放模式：顺序 → 单曲循环 → 列表循环 → 随机，点一下切一档
                  _Ctl(
                    icon: switch (player.playMode) {
                      PlayMode.sequence => Icons.trending_up_rounded,
                      PlayMode.repeatOne => Icons.repeat_one_rounded,
                      PlayMode.repeatAll => Icons.repeat_rounded,
                      PlayMode.shuffle => Icons.shuffle_rounded,
                    },
                    size: 22,
                    active: player.playMode != PlayMode.sequence,
                    onTap: player.cycleMode,
                    tooltip: player.playModeName,
                  ),
                  _Ctl(icon: Icons.skip_previous_rounded, size: 34, onTap: player.prev),
                  _PlayButton(playing: player.playing, onTap: player.toggle),
                  _Ctl(icon: Icons.skip_next_rounded, size: 34, onTap: player.next),
                  _Ctl(
                    icon: Icons.format_list_bulleted_rounded,
                    size: 25,
                    onTap: () => showGlassSheet(context, const QueueSheet()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _currentLine(PlayerState player) {
  final list = player.lyrics;
  if (list.isEmpty) return '';
  final i = player.lyricIndex.clamp(0, list.length - 1).toInt();
  return list[i].text;
}

class _Ctl extends StatelessWidget {
  const _Ctl({required this.icon, this.onTap, this.active = false, this.size = 20, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, size: size, color: active ? Colors.white : p.t3),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// 播放页「更多」：缓存 / 补全 / 随机 / 专辑
void _showMore(BuildContext context) {
  final app = context.read<AppState>();
  final player = context.read<PlayerState>();
  final track = player.current;
  final p = P.of(context);

  Future<void> run(Future<String> Function() action) async {
    final msg = await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget item(IconData icon, String text, String? sub, VoidCallback onTap) => InkWell(
        onTap: () {
          // 先记住要做的事，等弹层收起、下一帧再执行：
          // 同一个 frame 里 pop 完立刻 push，新路由拿到的还是正在销毁的上下文
          Navigator.pop(context);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) onTap();
          });
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
          child: Row(
            children: [
              Icon(icon, size: 18, color: p.t2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: TextStyle(fontSize: 14.5, color: p.t1)),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(fontSize: 12, color: p.t3)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  showGlassSheet(
    context,
    ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .6),
      child: Glass(
        radius: R.xxl,
        blur: Blur.thick,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(color: p.line2, borderRadius: BorderRadius.circular(3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.t2)),
            ),
            Divider(height: 1, color: p.line),
            item(
              switch (player.playMode) {
                PlayMode.sequence => Icons.trending_up_rounded,
                PlayMode.repeatOne => Icons.repeat_one_rounded,
                PlayMode.repeatAll => Icons.repeat_rounded,
                PlayMode.shuffle => Icons.shuffle_rounded,
              },
              L.of(context).t('player.playMode', {'m': player.playModeName}),
              L.of(context).t('player.playModeHint'),
              player.cycleMode,
            ),
            // 单曲「缓存这首 / 移除缓存」入口按需求移除：
            // 离线缓存统一在「我的 → 清除缓存数据」里管理，缓存能力（AppState.cacheTrack）保留。
            Divider(height: 1, color: p.line),
            item(Icons.auto_awesome_rounded, L.of(context).t('player.fillMeta'),
                L.of(context).t('player.fillMetaSub'),
                () => run(() => app.fillTrackMeta(track.id))),
            Divider(height: 1, color: p.line),
            item(Icons.playlist_add_rounded, L.of(context).t('player.addToPlaylist'),
                L.of(context).t('player.intoPlaylist'),
                () => showAddToPlaylistSheet(context, trackIds: [track.id])),
            Divider(height: 1, color: p.line),
            item(Icons.person_outline_rounded, L.of(context).t('player.viewArtist'),
                track.artist,
                () => pushArtist(context, track.artist)),
            Divider(height: 1, color: p.line),
            // 之前这里先去「专辑」总列表，进去还得再翻一次；直接进这张专辑
            item(Icons.album_outlined, L.of(context).t('player.viewAlbum'),
                app.albumOf(track.albumId).name,
                () => pushAlbum(context, app.albumOf(track.albumId))),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

/// 播放键：参考样式是「无底圈」的大图标
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        height: 64,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              size: 56,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部面板是 5% 透明玻璃，小字叠一点阴影保证对比度
const List<Shadow> _labelShadow = [
  Shadow(color: Colors.black54, blurRadius: 6),
];

/// 播放进度条 · 方案 A「流光扫过」
/// - 8px 轨道，已播区间紫→青渐变
/// - 一道高光在已播区间内循环掠过（2.4s），提供"正在流动"的暗示
/// - 16px 白滑块带紫青光晕，整条 32px 高作为触摸热区，拖拽跟手
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({
    required this.pos,
    required this.onSeek,
    required this.duration,
    required this.playing,
  });

  /// 播放进度（独立通知通道）
  final ValueListenable<Duration> pos;
  final ValueChanged<double> onSeek;
  final Duration duration;

  /// 只有播放中才跑流光动画：暂停时静止，省电也省重绘
  final bool playing;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar>
    with SingleTickerProviderStateMixin {
  /// 流光循环：2.4s 一轮，对应设计稿 A 方案
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant _ProgressBar old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!widget.playing && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  /// 拖拽中的临时进度（松手后交给播放器，避免进度回跳）
  double? _dragValue;

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // 只有这条进度条会随着播放进度刷新（5Hz），开销仅限这一小块
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.pos,
      builder: (context, position, _) {
        final total = widget.duration.inMilliseconds;
        final progress = total <= 0
            ? 0.0
            : (position.inMilliseconds / total).clamp(0.0, 1.0);
        return _buildBar(context, position, progress);
      },
    );
  }

  Widget _buildBar(BuildContext context, Duration position, double progress) {
    final p = P.of(context);
    final value = (_dragValue ?? progress).clamp(0.0, 1.0);
    final shown = _dragValue == null
        ? position
        : widget.duration * _dragValue!.clamp(0.0, 1.0);

    return Column(
      children: [
        LayoutBuilder(builder: (ctx, box) {
          void seek(Offset local) {
            final r = (local.dx / box.maxWidth).clamp(0.0, 1.0);
            setState(() => _dragValue = r);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              seek(d.localPosition);
              widget.onSeek(_dragValue!);
              setState(() => _dragValue = null);
            },
            onHorizontalDragStart: (d) => seek(d.localPosition),
            onHorizontalDragUpdate: (d) => seek(d.localPosition),
            onHorizontalDragEnd: (_) {
              final v = _dragValue;
              if (v != null) widget.onSeek(v);
              setState(() => _dragValue = null);
            },
            onHorizontalDragCancel: () => setState(() => _dragValue = null),
            child: SizedBox(
              height: 32, // 触摸热区：视觉 8px，命中区放大 4 倍
              child: Center(
                child: SizedBox(
                  height: 8,
                  width: double.infinity,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 轨道底
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.op(.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                      // 已播区间：渐变 + 流光
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: value,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Stack(
                              children: [
                                const Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          Color(0xFF6A45E8),
                                          Color(0xFF7C5CFF),
                                          Color(0xFF33D6FF),
                                        ],
                                        stops: [0, .45, 1],
                                      ),
                                    ),
                                  ),
                                ),
                                // 流光：64px 宽白色光带在已播区间内往复掠过
                                AnimatedBuilder(
                                  animation: _sweep,
                                  builder: (context, _) {
                                    final t = Curves.easeInOut
                                        .transform(_sweep.value);
                                    return Positioned.fill(
                                      child: FractionallySizedBox(
                                        alignment: Alignment(-1 + 2 * t, 0),
                                        widthFactor: .38,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                Color(0x8CFFFFFF),
                                                Colors.transparent,
                                              ],
                                              stops: [0, .5, 1],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 滑块：随进度定位，白点 + 双层光晕
                      Positioned(
                        left: box.maxWidth * value - 8,
                        top: -4,
                        child: IgnorePointer(
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7C5CFF).op(.40),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                                BoxShadow(
                                  color: const Color(0xFF33D6FF).op(.55),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                                const BoxShadow(
                                  color: Color(0x66000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Text(_fmt(shown),
                  style: TextStyle(
                      fontSize: 12,
                      color: p.t2,
                      shadows: _labelShadow,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const Spacer(),
              Text(_fmt(widget.duration),
                  style: TextStyle(
                      fontSize: 12,
                      color: p.t2,
                      shadows: _labelShadow,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ],
    );
  }
}
