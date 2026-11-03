import 'package:flutter/material.dart';

import '../widgets/common.dart' show GlassBackdrop;

/// 全站统一的页面推入动画：从右侧整屏滑入，280ms 缓出。
///
/// 为什么不用 MaterialPageRoute 默认过渡：
/// 默认是「缩放 + 淡入」，淡入会给整页开一个 saveLayer，
/// 而我们的页面里到处是 BackdropFilter（玻璃），
/// 一层不透明度的变化会强制所有玻璃层每帧重新模糊一次，肉眼就是卡顿。
/// 纯位移不做合成层，同样顺滑但开销小得多。
Route<T> slidePageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 230),
    pageBuilder: (_, __, ___) => _OpaquePage(child: page),
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        // 整页先栅格化成一层再位移：动画期间只是挪动已有图层，
        // 不会每帧重新排版/重绘整棵树
        child: RepaintBoundary(child: child),
      );
    },
  );
}

/// 给推入的页面自己铺一层壁纸底。
///
/// 之前所有页面的 Scaffold 都是透明的，靠 MaterialApp.builder 里那层全局
/// 壁纸当背景。于是新页面滑进来的过程中它是**半透明**的——上一页的内容会
/// 从新页面底下透出来（就是"残影"），等动画结束下层路由停止绘制，那一层
/// 又突然消失，看起来像闪了一下。
/// 页面自带一层同样的壁纸底，滑入时就能完整遮住上一页。
class _OpaquePage extends StatelessWidget {
  const _OpaquePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: GlassBackdrop()),
        Positioned.fill(child: child),
      ],
    );
  }
}
