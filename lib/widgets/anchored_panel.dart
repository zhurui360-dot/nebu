import 'package:flutter/material.dart';

/// 从某一行（或某个控件）下方展开的小面板。
///
/// 「我的」页里所有入口都用它：点哪一行，菜单就从那一行下面长出来，
/// 而不是从屏幕底部整块推上来。下方空间不够时自动翻到上方。
Future<T?> showAnchoredPanel<T>(
  BuildContext anchor, {
  required Widget panel,
  double gap = 6,
  double margin = 12,
  double maxHeightRatio = .58,
}) {
  final box = anchor.findRenderObject();
  final overlay =
      Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  final screen = MediaQuery.sizeOf(anchor);

  var top = screen.height * .3;
  var maxH = screen.height * maxHeightRatio;
  var left = margin;
  var width = screen.width - margin * 2;

  if (box is RenderBox && box.hasSize && overlay != null) {
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = origin & box.size;
    // 底部多留一点，别让面板贴着屏幕边（圆角会被吃掉）
    final below = screen.height - (rect.bottom + gap) - 28;
    final above = rect.top - gap - 24;
    // 优先向下展开；下方放不下就向上，两边都不够就用最大可用高度
    if (below >= 160 || below >= above) {
      top = rect.bottom + gap;
      maxH = below.clamp(140.0, screen.height * maxHeightRatio + 40);
    } else {
      maxH = above.clamp(140.0, screen.height * maxHeightRatio);
      // 别贴到屏幕最底：留 16，让面板的圆角完整露出来
      top = (rect.top - gap - maxH)
          .clamp(24.0, (screen.height - maxH - 16).clamp(24.0, screen.height));
    }
    // 和触发的那一行左右对齐，但至少留 12 的边距
    left = rect.left.clamp(margin, screen.width - margin - 200);
    width = (rect.width).clamp(220.0, screen.width - margin * 2);
    if (left + width > screen.width - margin) {
      width = screen.width - margin - left;
    }
  }

  return showGeneralDialog<T>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x33000000),
    transitionDuration: const Duration(milliseconds: 170),
    pageBuilder: (ctx, _, __) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          // 面板本身按内容高度撑开，最多占 maxH
          // showGeneralDialog 不带 Material，InkWell 会直接抛
          // "No Material widget found"，这里补一层透明 Material
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: panel,
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -.045), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}
