import 'dart:ui';

import 'package:flutter/material.dart';

/// 设计 token：一套语义色，明暗两套取值。
/// 所有界面只允许取这里的颜色，不写死色值。
@immutable
class P {
  const P({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.elev,
    required this.line,
    required this.line2,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.brand,
    required this.brand2,
    required this.mint,
    required this.gold,
    required this.rose,
    required this.glassFill,
    required this.glassLine,
    required this.dockFill,
    required this.dockLine,
  });

  final bool dark;
  final Color bg, surface, elev, line, line2, t1, t2, t3;
  final Color brand, brand2, mint, gold, rose, glassFill, glassLine, dockFill, dockLine;

  static const light = P(
    dark: false,
    bg: Color(0xFFFAFBFD),
    surface: Color(0xFFFFFFFF),
    elev: Color(0xFFF4F5FA),
    line: Color(0x14101320),
    line2: Color(0x24101320),
    t1: Color(0xFF101320),
    t2: Color(0xFF5A6175),
    t3: Color(0xFF8A90A3),
    brand: Color(0xFF6A45E8),
    brand2: Color(0xFF2F8CFF),
    mint: Color(0xFF12A67A),
    gold: Color(0xFFA86200),
    rose: Color(0xFFE4566A),
    glassFill: Color(0x96FFFFFF),
    glassLine: Color(0xF0FFFFFF),
    dockFill: Color(0x8FFFFFFF),
    dockLine: Color(0xEBFFFFFF),
  );

  static const darkP = P(
    dark: true,
    bg: Color(0xFF0B0D12),
    surface: Color(0xFF141821),
    elev: Color(0xFF1B2030),
    line: Color(0x14FFFFFF),
    line2: Color(0x24FFFFFF),
    t1: Color(0xFFF2F4F9),
    t2: Color(0xFF9AA1B4),
    t3: Color(0xFF878EA3), // 背景改成壁纸后提亮一档，保住辅助文字对比度
    brand: Color(0xFF7C5CFF),
    brand2: Color(0xFF33D6FF),
    mint: Color(0xFF39E0A6),
    gold: Color(0xFFFFD37A),
    rose: Color(0xFFFF6B7A),
    glassFill: Color(0x1FFFFFFF),
    glassLine: Color(0x2EFFFFFF),
    // 深色模式底部导航条：5% 透明玻璃（与播放控件同档，靠模糊兜住可读性）
    dockFill: Color(0x0D0B0D12),
    dockLine: Color(0x24FFFFFF),
  );

  static P of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? darkP : light;

  /// 品牌渐变（装饰用）
  LinearGradient get brandGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7C5CFF), Color(0xFF33D6FF)],
      );

  /// 承载白字时用的实色（对比度 5.8:1）
  Color get brandSolid => const Color(0xFF6A45E8);
}

/// 圆角与间距，与设计稿 1:1
class R {
  static const sm = 8.0, md = 12.0, lg = 16.0, xl = 22.0, xxl = 26.0, dock = 21.0;
}

/// 字号体系（v0.0.20 上调一档）：全局只允许取表内值，最小 10.5
class T {
  static const display = 27.0; // 页面大标题
  static const title = 18.0; // 卡片标题 / 空态标题
  static const heading = 16.0; // 小节标题
  static const body = 14.5; // 正文 / 歌曲行标题
  static const body2 = 13.5; // 次级正文
  static const caption = 12.0; // 说明 / 歌手行
  static const aux = 11.0; // 辅助计数
  static const badge = 10.5; // 徽标
}

class AppTheme {
  static ThemeData build(Brightness b) {
    final p = b == Brightness.dark ? P.darkP : P.light;
    final base = ThemeData(brightness: b, useMaterial3: true);
    return base.copyWith(
      // 页面底色透明：由 GlassBackdrop 统一铺底，
      // 这样玻璃面板的 BackdropFilter 才有内容可模糊
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: base.colorScheme.copyWith(
        primary: p.brand,
        surface: p.surface,
        onSurface: p.t1,
      ),
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: p.t1,
        displayColor: p.t1,
        fontFamily: null, // 用系统字体：PingFang / HarmonyOS Sans / Roboto
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

/// 常用模糊参数（Liquid Glass：Apple 实测 30–40px 高斯，
/// 但模糊过头背后的内容就糊成一片死灰，玻璃的"透"反而没了。
/// 取 18–34 这一档，让背后的颜色能认出来 —— 这才是玻璃不是磨砂纸）
class Blur {
  static const thin = 22.0;
  static const regular = 30.0;
  static const thick = 40.0;

  static ImageFilter f(double sigma) =>
      ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp);
}
