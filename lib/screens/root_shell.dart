import 'dart:math' show pi, sin;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import '../state/player_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home.dart';
import 'library.dart';
import 'me.dart';
import 'search.dart';

/// 根容器：四个 Tab + 悬浮玻璃导航条 + 全局导入进度横幅 + 迷你播放条
///
/// 切换 Tab：页面沿切换方向滑入（带淡入）；导航条上的水滴沿导航条流过去，
/// 也支持按住导航条左右拖动，水滴跟手、停在哪个页签就切到哪个页面。
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  int? _lastTab;
  int _dir = 1; // 切换方向：往右切 = 1，往左切 = -1

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final player = context.watch<PlayerState>();
    final showBanner = app.importJob != null || app.localScanning;

    // Tab 变化 → 页面沿切换方向滑入（IndexedStack 状态不丢）
    if (_lastTab != app.tabIndex) {
      final from = _lastTab ?? app.tabIndex;
      _dir = app.tabIndex >= from ? 1 : -1;
      _lastTab = app.tabIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enter.forward(from: 0);
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // Tab 切换：整页跟手滑入 + 轻微上浮，300ms 缓出。
          // 这里刻意不用 Opacity：页面里全是 BackdropFilter，
          // 改透明度会强制整屏重建合成层（每帧重新模糊一遍），
          // 这正是之前切页发卡的根源。纯位移不触发重新模糊。
          AnimatedBuilder(
            animation: _enter,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_enter.value);
              return Transform.translate(
                offset: Offset(42 * _dir * (1 - t), 6 * (1 - t)),
                child: child,
              );
            },
            child: RepaintBoundary(
              child: IndexedStack(
                index: app.tabIndex,
                children: const [
                  HomeScreen(),
                  LibraryScreen(),
                  SearchScreen(),
                  MeScreen(),
                ],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBanner) ...[
                    const ImportBanner(),
                    const SizedBox(height: 8),
                  ],
                  if (player.showMiniPlayer) ...[
                    const MiniPlayerBar(),
                    const SizedBox(height: 8),
                  ],
                  _FloatingDock(index: app.tabIndex, onTap: app.setTab),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingDock extends StatefulWidget {
  const _FloatingDock({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  State<_FloatingDock> createState() => _FloatingDockState();
}

/// 水滴导航条：
/// - 点页签：水滴沿导航条流过去（跨页签时连续流过中间位置）
/// - 点下时页签先放大一下（按压反馈）
/// - 按住左右拖：水滴跟手移动、路过的页签跟着放大，松手落在哪个页签就切过去
// 这里有两个 AnimationController（水滴流动 + 呼吸），必须用多 ticker 的 mixin；
// SingleTickerProviderStateMixin 只在 debug 断言里报错，release 下不崩但会静默复用 ticker
class _FloatingDockState extends State<_FloatingDock>
    with TickerProviderStateMixin {
  /// 只有图标是固定的，文字跟着界面语言走（见 build 里的 [L]）
  static const _icons = [
    Icons.home_rounded,
    Icons.library_music_rounded,
    Icons.search_rounded,
    Icons.person_rounded,
  ];

  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    value: 1,
  );

  // 静止时的「呼吸」起伏已经去掉：那是个常驻 60fps 的动画，
  // 会让导航条每帧重新做一次背板模糊，是长时间使用后整体发烫发卡的主因之一。
  // 水滴的液体感改由切页时的形变（_flow）承担，肉眼几乎看不出差别。

  int _last = 0;
  double _from = 0; // 水滴出发位置（以页签为单位，可带小数）
  double _pos = 0; // 水滴当前位置
  bool _dragging = false;
  double _grabCenterOffset = 0; // 按下时手指与气泡中心的偏移（跟手用）
  int _hover = 0; // 拖动/按压时指着的页签
  int _pressed = -1; // 点下时的页签（按压放大反馈）

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  /// 气泡以「抓取点」为轴跟手：按下时记住手指与气泡中心的偏移，
  /// 拖动时保持这个偏移，气泡就像粘在手指上一样移动。
  void _startDrag(Offset local, double totalWidth) {
    final w = totalWidth / _icons.length;
    final bubbleCenter = (_pos + .5) * w;
    _grabCenterOffset = local.dx - bubbleCenter;
    _updateDrag(local, totalWidth);
  }

  void _updateDrag(Offset local, double totalWidth) {
    final w = totalWidth / _icons.length;
    final bubbleCenter = local.dx - _grabCenterOffset;
    final frac =
        (bubbleCenter / w - .5).clamp(0.0, _icons.length - 1.0);
    final hover = frac.round().clamp(0, _icons.length - 1);
    if (frac != _pos || hover != _hover) {
      setState(() {
        _pos = frac;
        if (hover != _hover) {
          _hover = hover;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final l = L.of(context);
    final labels = [l.tabHome, l.tabBrowse, l.tabSearch, l.tabMe];
    final index = widget.index;

    if (_last != index) {
      if (!_dragging) {
        _from = _pos; // 从当前位置（可能是拖动的半路）流到新页签
      } else {
        _from = index.toDouble();
        _pos = index.toDouble();
      }
      _last = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _flow.forward(from: 0);
      });
    }

    // 导航条：玻璃底板（frostedFilter 40）上浮一颗磨砂水滴气泡，
    // 层次：页面 → 底层玻璃板 → 水滴气泡 → 图标文字。
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth / _icons.length;
        const barH = 70.0;

        // 气泡这块玻璃只构建一次：以前它写在动画 builder 里，
        // 每帧都会重新建一遍 BackdropFilter，等于整条导航条在 60fps 跑模糊。
        final bubbleGlass = Glass(
          radius: 20,
          blur: Blur.thin,
          sheer: true,
          elevated: false,
          fill: p.dark ? const Color(0x16FFFFFF) : const Color(0x9EFFFFFF),
          child: const SizedBox.expand(),
        );

        final bubble = AnimatedBuilder(
          animation: _flow,
          child: bubbleGlass,
          builder: (context, child) {
            if (!_dragging) {
              final t = Curves.easeInOutCubic.transform(_flow.value);
              _pos = lerpDouble(_from, _last.toDouble(), t)!;
            }
            // 行进中的水滴形变：横向明显拉长、纵向微鼓；拖动时保持更大张力
            final k = _dragging ? .7 : sin(pi * _flow.value);
            return Positioned(
              left: _pos * w + 4,
              width: w - 8,
              top: 5, // 气泡收在导航框里面
              bottom: 5,
              child: Transform.scale(
                scaleX: 1 + .6 * k,
                scaleY: 1 + .3 * k,
                child: child,
              ),
            );
          },
        );

        final items = Positioned.fill(
          child: Row(
            children: [
              for (var i = 0; i < _icons.length; i++)
                Expanded(
                  child: SizedBox(
                    height: barH,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      scale: _pressed == i
                          ? 1.14
                          : ((_dragging ? _hover : index) == i
                              ? 1.06
                              : 1.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 图标：拖动/选中时轻微放大
                          AnimatedScale(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            scale:
                                (_dragging ? _hover : index) == i ? 1.12 : 1.0,
                            child: Icon(
                              _icons[i],
                              size: 26,
                              color: (_dragging ? _hover : index) == i
                                  ? p.brand
                                  : p.t3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: (_dragging ? _hover : index) == i
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: (_dragging ? _hover : index) == i
                                  ? p.brand
                                  : p.t3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        final stack = Stack(
          clipBehavior: Clip.none,
          children: [
            // 玻璃底板
            Positioned.fill(
              child: Glass(
                radius: R.dock,
                blur: Blur.thick,
                fill: p.dockFill,
                child: const SizedBox.expand(),
              ),
            ),
            // 白色气泡（凸出上沿，盖在玻璃上、垫在图标下）
            bubble,
            // 图标与文字
            items,
          ],
        );

        // 按住左右拖：水滴跟手，松手切到落点页签；
        // 点任意位置：水滴直接流到你点的那个页签
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (d) {
            if (_dragging) return;
            final i = (d.localPosition.dx / w)
                .floor()
                .clamp(0, _icons.length - 1);
            setState(() => _pressed = i);
          },
          onTapUp: (d) {
            if (_dragging) return;
            final i = (d.localPosition.dx / w)
                .floor()
                .clamp(0, _icons.length - 1);
            setState(() => _pressed = -1);
            if (i != widget.index) {
              HapticFeedback.selectionClick();
              widget.onTap(i);
            }
          },
          onTapCancel: () {
            if (!_dragging) setState(() => _pressed = -1);
          },
          onHorizontalDragStart: (d) {
            _dragging = true;
            _hover = _last;
            _startDrag(d.localPosition, c.maxWidth);
          },
          onHorizontalDragUpdate: (d) =>
              _updateDrag(d.localPosition, c.maxWidth),
          onHorizontalDragEnd: (_) {
            if (!_dragging) return;
            _dragging = false;
            final target = _hover;
            setState(() {});
            if (target != widget.index) {
              HapticFeedback.selectionClick();
              widget.onTap(target);
            } else {
              // 原地松手：把水滴收圆落回当前页签
              _from = _pos;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _flow.forward(from: 0);
              });
            }
          },
          // Stack 里全是定位子元素，必须给它固定高度，否则整条塌缩成 0
          child: SizedBox(height: barH, child: stack),
        );
      },
    );
  }
}
