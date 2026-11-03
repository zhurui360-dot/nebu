import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../utils/cover_style.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../screens/player.dart' show showPlayer;

extension ColorAlpha on Color {
  /// 兼容 Flutter 3.22 及更早版本（withValues 为 3.27+ API）
  Color op(double opacity) => withAlpha((opacity * 255).round());
}

// ───────────────────────────────────────────────────────────────────────────
// iOS 磨砂玻璃材质
// ───────────────────────────────────────────────────────────────────────────

/// iOS 磨砂配方：高斯模糊 + 饱和度提升（1.6×）。
/// 只做 blur 会得到"磨砂塑料"，叠上饱和度才是玻璃那种通透的润。
ImageFilter frostedFilter(double sigma) => ImageFilter.compose(
      outer: const ColorFilter.matrix(<double>[
        1.4722, -0.4290, -0.0432, 0, 0, //
        -0.1278, 1.1710, -0.0432, 0, 0, //
        -0.1278, -0.4290, 1.5568, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );

/// iOS 玻璃材质。
///
/// 三个层次缺一不可：
/// ① 折射层：BackdropFilter 模糊 + 提饱和度，让背后的画面"糊成一片色"透上来；
/// ② 受光层：自上而下由亮到暗的半透明白，模拟光从上方透过玻璃；
/// ③ 边缘层：1px 渐变高光描边（左上最亮、右下微反光）+ 外投影。
///    这一笔是"看起来像玻璃"的关键，缺了就是一块半透明塑料。
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = R.xl,
    this.blur = Blur.regular,
    this.padding,
    this.fill,
    this.border,
    this.margin,
    this.clip = true,
    this.shadow,
    this.topLight = true,
    this.sheer = false,
    this.elevated = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  /// 自定义底色（品牌色玻璃，如「继续播放」卡）；不传用标准白玻璃
  final Color? fill;

  /// 自定义描边；不传用 iOS 渐变高光描边
  final Color? border;
  final bool clip;

  /// 自定义投影：需要强调"悬空感"的组件（如底部导航条）可传更重的
  final BoxShadow? shadow;

  /// 顶部受光内高光：小控件打开更立体，大块卡片关掉避免盖住首行文字
  final bool topLight;

  /// 全透明玻璃：填充压到几乎为零，只靠模糊 + 边缘高光成立。
  final bool sheer;

  /// 是否带外投影。贴合在页面里的板块可关掉（省一次离屏合成）
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final br = BorderRadius.circular(radius);

    final body = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: frostedFilter(blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: br,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: sheer
                  ? (p.dark
                      ? const [Color(0x08FFFFFF), Color(0x02000000)]
                      : const [Color(0x1FFFFFFF), Color(0x0AFFFFFF)])
                  : fill != null
                      ? (p.dark
                          ? const [Color(0x16FFFFFF), Color(0x05000000)]
                          : const [Color(0x5CFFFFFF), Color(0x1FFFFFFF)])
                      : (p.dark
                          ? const [Color(0x24FFFFFF), Color(0x07000000)]
                          : const [Color(0x8AFFFFFF), Color(0x3DF4F7FF)]),
            ),
          ),
          child: Stack(
            children: [
              // 顶部受光：模拟光自上而下穿过玻璃，边缘泛起一层薄光
              if (topLight)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.op(sheer
                                ? (p.dark ? .05 : .16)
                                : (p.dark ? .16 : .55)),
                            Colors.white.op(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ],
          ),
        ),
      ),
    );

    final content = Stack(
      children: [
        body,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GlassRim(
                radius: radius,
                dark: p.dark,
                color: border,
                sheer: sheer,
              ),
            ),
          ),
        ),
      ],
    );

    if (!elevated) return Container(margin: margin, child: content);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          shadow ??
              BoxShadow(
                color:
                    p.dark ? const Color(0x59000000) : const Color(0x1A101320),
                blurRadius: 30,
                offset: const Offset(0, 14),
                spreadRadius: -12,
              ),
        ],
      ),
      child: content,
    );
  }
}

/// 玻璃边缘：一圈渐变高光——左上受光最亮，中段几乎消失，右下留一点反光。
class _GlassRim extends CustomPainter {
  const _GlassRim({
    required this.radius,
    required this.dark,
    this.color,
    this.sheer = false,
  });

  final double radius;
  final bool dark;
  final Color? color;

  /// 全透明玻璃：填充几乎没有，边缘必须更亮更硬，否则整块会消失
  final bool sheer;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(.5),
      Radius.circular(radius <= .5 ? 0 : radius - .5),
    );
    // 内侧柔光：贴着边缘往里渗 8px，制造玻璃的"厚度感"。
    // 透明玻璃之所以看起来还是一块玻璃，靠的就是这圈光，而不是填充色。
    canvas.drawRRect(
      rrect.deflate(4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
        ..color = Colors.white.op(sheer ? (dark ? .20 : .38) : (dark ? .13 : .32)),
    );

    // 主描边：左上受光最亮，中段几乎消失，右下留一点反光
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sheer ? 1.3 : 1.1;
    if (color != null) {
      paint.color = color!;
    } else {
      paint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: sheer
            ? (dark
                ? const [Color(0xC4FFFFFF), Color(0x33FFFFFF), Color(0x5CFFFFFF)]
                : const [Color(0xFFFFFFFF), Color(0x8AFFFFFF), Color(0xE6FFFFFF)])
            : (dark
                ? const [Color(0xB8FFFFFF), Color(0x1FFFFFFF), Color(0x4DFFFFFF)]
                : const [Color(0xFFFFFFFF), Color(0x3DFFFFFF), Color(0xC7FFFFFF)]),
        stops: const [0, .5, 1],
      ).createShader(rect);
    }
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRim old) =>
      old.dark != dark ||
      old.color != color ||
      old.radius != radius ||
      old.sheer != sheer;
}

/// 全局毛玻璃底：一层近黑（浅色下为冷白）底 + 两团品牌柔光。
///
/// 毛玻璃必须先有"可模糊的内容"才有质感：如果页面自己铺一层实色底，
/// BackdropFilter 只会糊出一片死灰。所以全站页面背景统一透明，
/// 由这一层提供底色与光晕，玻璃面板浮在上面才有层次。
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: p.dark
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1B2050),
                        Color(0xFF131538),
                        Color(0xFF0C1226),
                        Color(0xFF07131C),
                      ],
                      stops: [0, .38, .72, 1],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFDFDFF),
                        Color(0xFFF0F3FD),
                        Color(0xFFE9F1FB),
                        Color(0xFFF4F7FD),
                      ],
                      stops: [0, .4, .75, 1],
                    ),
            ),
          ),
          // 左上紫光：主色，页面顶部的主调
          Positioned(
            top: -300,
            left: -260,
            child: _AuroraBlob(
              color: p.brand,
              size: 820,
              opacity: p.dark ? .42 : .18,
            ),
          ),
          // 右下青光：与紫光对位，玻璃边缘透出的冷暖对比
          Positioned(
            bottom: -340,
            right: -280,
            child: _AuroraBlob(
              color: p.brand2,
              size: 1100,
              opacity: p.dark ? .30 : .15,
            ),
          ),
          // 中段淡蓝：让屏幕中部的玻璃也有可折射的色，否则整块区域是死黑
          Positioned(
            top: 240,
            right: -220,
            child: _AuroraBlob(
              color: const Color(0xFF3B5BFF),
              size: 820,
              opacity: p.dark ? .20 : .10,
            ),
          ),
          // 顶部一道极淡的白光：玻璃上缘因此会泛出亮边
          Positioned(
            top: -180,
            left: -60,
            right: -60,
            height: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.op(p.dark ? .06 : .55),
                    Colors.white.op(0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuroraBlob extends StatelessWidget {
  const _AuroraBlob({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // 三段式衰减：单段线性衰减会在圆的边界留下一圈可见的"光晕边"，
            // 加中间档后过渡像真正的散射光
            gradient: RadialGradient(
              colors: [
                color.op(opacity),
                color.op(opacity * .34),
                color.op(0),
              ],
              stops: const [0, .42, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// 没有内嵌封面时的「品牌封面」：用 App 标记顶替专辑图。
///
/// 关键是与真封面走完全同一套管线——同样是 1:1 铺满（BoxFit.cover），
/// 因此在播放页会被同样的上下融边蒙版削掉边缘、被同样的 frostedFilter
/// 拿去铺背景。换掉硬编码的渐变灰块，就不会出现"有的歌是图、有的歌是灰块"。
class BrandCover extends StatelessWidget {
  const BrandCover({super.key, this.fit = BoxFit.cover});

  final BoxFit fit;

  /// 品牌封面资源（768×768）
  static const asset = 'assets/branding/logo_nebu.jpg';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// 后台导入进度：导入放在后台跑，这里显示它的状态
class ImportBanner extends StatelessWidget {
  const ImportBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final app = context.watch<AppState>();
    final job = app.importJob;

    // 本机扫描也在横幅里显示进度
    if (job == null && !app.localScanning) return const SizedBox.shrink();

    final Widget icon;
    final String label;
    double? progress;
    var failed = false;
    var canDismiss = false;

    if (app.localScanning && job == null) {
      // 用静态图标代替转圈动画：这条横幅常驻在毛玻璃上，
      // 一个永不停歇的动画会让整块背板每帧重绘，扫描时整机发烫。
      icon = Icon(Icons.sync_rounded, size: 16, color: p.brand);
      label = L.read(context).t('import.scanning');
      progress = app.localProgress > 0 ? app.localProgress : null;
    } else if (job!.failed) {
      failed = true;
      icon = const Icon(Icons.error_outline_rounded,
          size: 16, color: Color(0xFFC2412E));
      label = L.read(context).t('import.failed', {'e': job.error ?? ''});
    } else if (!job.isDone) {
      // 用静态图标代替转圈动画：这条横幅常驻在毛玻璃上，
      // 一个永不停歇的动画会让整块背板每帧重绘，扫描时整机发烫。
      icon = Icon(Icons.sync_rounded, size: 16, color: p.brand);
      label = L.read(context).t('import.progress',
          {'a': '${job.done}', 'b': '${job.total}'}) +
          (job.total > 0
              ? '（${(job.done * 100 / job.total).round()}%）'
              : '');
      if (job.total > 0) progress = job.done / job.total;
    } else {
      icon = Icon(Icons.check_circle_rounded, size: 16, color: p.mint);
      label = L.read(context).t('import.done', {'n': '${job.added}'}) +
          (job.skipped > 0
              ? L.read(context).t('import.skipped', {'n': '${job.skipped}'})
              : '');
      canDismiss = true;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      child: Glass(
        radius: R.lg,
        blur: Blur.thin,
        fill: failed ? const Color(0x14C2412E) : p.glassFill,
        padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: p.t2),
                  ),
                ),
                if (canDismiss)
                  TextButton(
                    onPressed: app.dismissImport,
                    child: Text(L.read(context).gotIt,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: p.line2,
                  valueColor: AlwaysStoppedAnimation(p.brand),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 全局迷你播放条：播放过才有；点整条进播放页
class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar>
    with SingleTickerProviderStateMixin {
  /// 切歌过场：旧内容跟手滑出 → 新内容从反方向滑入
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  double _offset = 0; // 内容横向位移
  double _from = 0;
  double _to = 0;
  String? _lastId;
  int _dir = 1; // 1 = 新歌从右进，-1 = 从左进

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      if (!mounted) return;
      setState(() => _offset =
          _from + (_to - _from) * Curves.easeOutCubic.transform(_settle.value));
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _from = _offset;
    _to = target;
    _settle.forward(from: 0);
  }

  /// 第二行：有歌词就唱歌词，没有就退回歌手名
  String _secondLine(PlayerState player, Track track) {
    if (player.lyrics.isNotEmpty) {
      final i = player.lyricIndex.clamp(0, player.lyrics.length - 1).toInt();
      final line = player.lyrics[i].text.trim();
      if (line.isNotEmpty) return line;
    }
    return track.artist;
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final player = context.watch<PlayerState>();
    if (!player.showMiniPlayer) return const SizedBox.shrink();
    final track = player.current;

    // 曲目变了：按队列里的前后关系决定从哪一侧滑入
    if (_lastId == null) {
      _lastId = track.id;
    } else if (_lastId != track.id) {
      final oldI = player.queue.indexOf(_lastId!);
      final newI = player.queue.indexOf(track.id);
      _dir = (oldI >= 0 && newI >= 0 && newI < oldI) ? -1 : 1;
      _lastId = track.id;
      // 新内容先停在反方向，再从那儿滑回原位
      _offset = -_dir * 96.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(0);
      });
    }

    final second = _secondLine(player, track);
    final showingLyric = player.lyrics.isNotEmpty && second != track.artist;

    return Glass(
      radius: 18,
      blur: Blur.thin,
      fill: p.dockFill,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: GestureDetector(
        // 迷你条上左右滑动切歌：内容跟手横移，松手才真的切
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) {
          setState(() => _offset = (_offset + d.delta.dx).clamp(-120.0, 120.0));
        },
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          final goNext = _offset < -42 || v < -320;
          final goPrev = _offset > 42 || v > 320;
          if (!goNext && !goPrev) {
            _animateTo(0); // 不够阈值，弹回原位
            return;
          }
          HapticFeedback.selectionClick();
          if (goNext) {
            player.next();
          } else {
            player.prev();
          }
          // 曲目没变（比如队列只有一首）也要把内容收回来
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _settle.isDismissed) _animateTo(0);
          });
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showPlayer(context),
          child: Transform.translate(
            offset: Offset(_offset, 0),
            child: Row(
              children: [
                CoverArt(
                  albumId: track.albumId,
                  size: 40,
                  radius: 10,
                  coverPath: track.coverPath,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: p.t1)),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 17,
                        // 歌词逐行变化：竖向小幅滑动切换，像卡拉OK机
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, .55),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              second,
                              key: ValueKey<String>(second),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: showingLyric ? p.t1 : p.t2,
                                fontWeight: showingLyric
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                RoundIcon(
                  player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 40,
                  color: p.t1,
                  tooltip: player.playing
                      ? L.read(context).t('pause')
                      : L.read(context).t('play'),
                  onTap: player.toggle,
                ),
                RoundIcon(
                  Icons.skip_next_rounded,
                  size: 38,
                  color: p.t1,
                  tooltip: '下一首',
                  onTap: player.next,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形/方形图标按钮
class RoundIcon extends StatelessWidget {
  const RoundIcon(this.icon,
      {super.key, this.onTap, this.size = 38, this.color, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size * .32),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size * .52, color: color ?? p.t1),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// 段落标题
class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.action, this.onTap, this.top});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  final double? top;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top ?? 0, 20, 10),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: p.t1)),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: onTap,
              child:
                  Text(action!, style: TextStyle(fontSize: 12.5, color: p.t2)),
            ),
        ],
      ),
    );
  }
}

/// 封面：0 号是《学不会》山景（代码绘制），其余为渐变
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.albumId,
    this.size = 44,
    this.radius = 12,
    this.coverPath,
  });
  final String albumId;
  final double size;
  final double radius;

  /// 内嵌封面落盘路径；有就显示真封面，没有再用渐变兜底
  final String? coverPath;

  static const _gradients = <List<Color>>[
    [Color(0xFF2B1B4D), Color(0xFF7C5CFF), Color(0xFF33D6FF)],
    [Color(0xFF101830), Color(0xFF3C5BD8), Color(0xFF9BB8FF)],
    [Color(0xFF141C2E), Color(0xFF4A5B8C), Color(0xFFB9C6E8)],
    [Color(0xFF2A1024), Color(0xFFC2418A), Color(0xFFFFB84D)],
    [Color(0xFF0F2A2B), Color(0xFF1F9E8A), Color(0xFF8CE0C0)],
    [Color(0xFF2B1A12), Color(0xFFB65C2E), Color(0xFFF3C07B)],
    [Color(0xFF1F2A44), Color(0xFF5A6FA8), Color(0xFFC7D3EE)],
  ];

  /// 封面文件是否存在。
  ///
  /// `existsSync()` 是同步磁盘 IO：列表一屏二十几行、滚动时每帧都要判一次，
  /// 在主线程上做几十次 stat 就是掉帧的直接来源。这里按路径缓存结果，
  /// 文件真被删掉时由 Image.file 的 errorBuilder 兜底，行为不变。
  static final Map<String, bool> _existsCache = {};

  static bool _exists(String path) =>
      _existsCache[path] ??= File(path).existsSync();

  @override
  Widget build(BuildContext context) {
    final style = coverStyleOf(albumId);

    final cover = coverPath;
    if (cover != null && _exists(cover)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(cover),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(style),
          cacheWidth: (size * 3).round(),
        ),
      );
    }
    return _fallback(style);
  }

  Widget _fallback(int style) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: style == 0
            ? CustomPaint(painter: _AlpsPainter())
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _gradients[style.clamp(0, _gradients.length - 1)],
                  ),
                ),
              ),
      ),
    );
  }
}

/// 《学不会》封面：北欧雪山夜色（示意，正式封面为版权素材）
class _AlpsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width, h = size.height;

    // 天空
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF070C16),
            Color(0xFF111F36),
            Color(0xFF2B4365),
            Color(0xFF6B8199),
            Color(0xFFC7D2DE),
            Color(0xFFEFF2F6),
          ],
          stops: [0, .28, .5, .67, .82, 1],
        ).createShader(rect),
    );

    // 月光
    final moonCenter = Offset(w * .71, h * .23);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0xF2FFF7E2),
            Color(0x42FFF7E2),
            Color(0x00FFF7E2)
          ],
          stops: [0, .34, 1],
        ).createShader(Rect.fromCircle(center: moonCenter, radius: w * .46)),
    );

    // 两道山脊
    Path ridge(double leftTop, double midTop, double rightTop) => Path()
      ..moveTo(0, h * leftTop)
      ..lineTo(w * .55, h * midTop)
      ..lineTo(w, h * rightTop)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      ridge(.62, .78, .56),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16273F), Color(0xFF0A1524)],
        ).createShader(rect),
    );
    canvas.drawPath(
      ridge(.72, .72, .66),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101F35), Color(0xFF070F1C)],
        ).createShader(rect),
    );

    // 雪线
    canvas.drawLine(
      Offset(0, h * .72),
      Offset(w * .55, h * .72),
      Paint()
        ..color = const Color(0x33DEECFF)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 曲目行
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.subtitle,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.showFormat = false,
    this.playing = false,
  });

  final Track track;
  final String subtitle;
  final VoidCallback? onTap;

  /// 长按出歌曲菜单（加入歌单 / 喜欢 / 移出歌单）
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool showFormat;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    // 只订阅「这一首有没有被缓存」这一个布尔值。
    // 之前是 watch 整个 AppState：列表里每个 tile 都监听整份曲库，
    // 任何一次 notify（导入进度、播放记录、收藏…）都要把整屏 tile 重建一遍。
    final cached = context.select<AppState, bool>((a) => a.isCached(track.id));
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: playing ? p.brand.op(.09) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CoverArt(albumId: track.albumId, coverPath: track.coverPath),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: p.t1,
                          ),
                        ),
                      ),
                      if (showFormat) ...[
                        const SizedBox(width: 6),
                        _Badge(track.format.label, color: p.brand),
                        if (!track.hasTags) ...[
                          const SizedBox(width: 5),
                          _Badge(L.read(context).t('badgeNoTag'),
                              color: const Color(0xFFC2412E), filled: true),
                        ],
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.t3),
                  ),
                ],
              ),
            ),
            if (cached) ...[
              const SizedBox(width: 5),
              Icon(Icons.download_done_rounded, size: 13, color: p.mint),
            ],
            const SizedBox(width: 8),
            trailing ??
                Text(
                  _fmt(track.duration),
                  style: TextStyle(
                      fontSize: 12,
                      color: p.t3,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
          ],
        ),
      ),
    );
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.color, this.filled = false});
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color.op(.07) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.op(.32)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: .3),
      ),
    );
  }
}

/// 播放中的均衡器
class Equalizer extends StatefulWidget {
  const Equalizer({super.key, this.color});
  final Color? color;

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? P.of(context).mint;
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          double v(int i) =>
              0.35 + 0.65 * ((1 - ((_c.value + i * .33) % 1)).abs());
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              return Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 2),
                child: Container(
                  width: 2.5,
                  height: 14 * v(i),
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2)),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// 页面头部：小标题 + 大标题 + 右侧动作
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.actions = const [],
    this.large = true,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!, style: TextStyle(fontSize: 12.5, color: p.t2)),
                  const SizedBox(height: 3),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: large ? 26 : 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                    color: p.t1,
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 设置分组容器
class GroupBox extends StatelessWidget {
  const GroupBox({super.key, required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: p.t3,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Glass(
            radius: R.lg,
            blur: Blur.regular,
            padding: EdgeInsets.zero,
            topLight: false,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.line),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置行
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.sub,
    this.onTap,
    this.valueColor,
  });

  final String label;
  final String? value;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, color: p.t1)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!, style: TextStyle(fontSize: 12, color: p.t3)),
                  ],
                ],
              ),
            ),
            // 数值靠右对齐：Align 撑满剩余空间后把文本推到最右
            if (value != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: value!.length > 26 ? 10.5 : 11.5,
                          color: valueColor ?? p.t3,
                        )),
                  ),
                ),
              ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 16, color: p.t3),
            ],
          ],
        ),
      ),
    );
  }
}

/// 开关
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return GestureDetector(
      onTap: () => onChanged?.call(!value),
      child: Container(
        width: 40,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: value
              ? const LinearGradient(
                  colors: [Color(0xFF6A45E8), Color(0xFF33B5FF)])
              : null,
          color: value ? null : p.line2,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withAlpha(60),
                    blurRadius: 3,
                    offset: const Offset(0, 1))
              ],
            ),
          ),
        ),
      ),
    );
  }
}
