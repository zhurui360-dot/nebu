import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/screens/root_shell.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _out = 'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-liquid-preview';

ThemeData _theme(Brightness b) {
  final t = AppTheme.build(b);
  return t.copyWith(textTheme: t.textTheme.apply(fontFamily: 'SimHei'));
}

Future<void> _loadFont() async {
  final bytes = await File('C:/Windows/Fonts/simhei.ttf').readAsBytes();
  final loader = FontLoader('SimHei')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();

  // 图标字体：不加载的话预览里所有 Icon 都是方块
  final icons = await File(
          'C:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
      .readAsBytes();
  final iconLoader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(icons).buffer)));
  await iconLoader.load();
}

Future<void> _shot(WidgetTester tester, Key key, String name) async {
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump(const Duration(milliseconds: 260));
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// 背后要有"东西"才看得出折射与透明：铺一层高饱和封面墙 + 文字
Widget _busyContent({required bool dark}) {
  const palette = <List<Color>>[
    [Color(0xFF2B1B4D), Color(0xFF7C5CFF), Color(0xFF33D6FF)],
    [Color(0xFF2A1024), Color(0xFFC2418A), Color(0xFFFFB84D)],
    [Color(0xFF0F2A2B), Color(0xFF1F9E8A), Color(0xFF8CE0C0)],
    [Color(0xFF2B1A12), Color(0xFFB65C2E), Color(0xFFF3C07B)],
    [Color(0xFF101830), Color(0xFF3C5BD8), Color(0xFF9BB8FF)],
    [Color(0xFF3A1030), Color(0xFF8E3BD8), Color(0xFFFF9BD5)],
  ];
  return SingleChildScrollView(
    padding: const EdgeInsets.only(top: 56, left: 16, right: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('听见光的样子',
            style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
        const SizedBox(height: 4),
        const Text('最近播放 · 24 首',
            style: TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 16),
        for (var row = 0; row < 7; row++) ...[
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 10),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: palette[(row * 3 + i) % palette.length],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    ),
  );
}

void main() {
  setUpAll(_loadFont);

  testWidgets('材质研究：一层内容 + 五块玻璃', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    const k = ValueKey('shot');
    await tester.pumpWidget(
      RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.dark),
          builder: (context, child) => Stack(
            children: [
              const Positioned.fill(child: GlassBackdrop()),
              if (child != null) child,
            ],
          ),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                _busyContent(dark: true),
                // 悬浮层：真实尺寸的导航条 / 迷你播放条 / 卡片
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 14,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Glass(
                        radius: 18,
                        blur: Blur.thin,
                        fill: P.darkP.dockFill,
                        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text('雪落下的声音\n这一秒 只想安静',
                                  style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      color: Colors.white)),
                            ),
                            const Icon(Icons.pause_rounded,
                                color: Colors.white, size: 22),
                            const SizedBox(width: 12),
                            const Icon(Icons.skip_next_rounded,
                                color: Colors.white, size: 22),
                            const SizedBox(width: 6),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 70,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Glass(
                                radius: R.dock,
                                blur: Blur.thick,
                                fill: P.darkP.dockFill,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            const Positioned(
                              left: 4,
                              width: 92,
                              top: 5,
                              bottom: 5,
                              child: Glass(
                                radius: 20,
                                blur: Blur.thin,
                                sheer: true,
                                elevated: false,
                                fill: Color(0x16FFFFFF),
                                child: SizedBox.expand(),
                              ),
                            ),
                            const Positioned.fill(
                              child: Row(
                                children: [
                                  _DockItem('首页', Icons.home_rounded, true),
                                  _DockItem('浏览', Icons.library_music_rounded, false),
                                  _DockItem('搜索', Icons.search_rounded, false),
                                  _DockItem('我的', Icons.person_rounded, false),
                                ],
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
        ),
      ),
    );

    await _shot(tester, k, '01-材质研究-深色');
  });

  testWidgets('真机首页：导航条玻璃', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    const k = ValueKey('shot2');
    final app = AppState(LibraryRepository());
    await tester.pumpWidget(
      RepaintBoundary(
        key: k,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            ChangeNotifierProvider<PlayerState>.value(value: PlayerState()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _theme(Brightness.dark),
            builder: (context, child) => Stack(
              children: [
                const Positioned.fill(child: GlassBackdrop()),
                if (child != null) child,
              ],
            ),
            home: const RootShell(),
          ),
        ),
      ),
    );
    await _shot(tester, k, '02-首页-深色');
  });
  testWidgets('浅色模式材质', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    const k = ValueKey('shot4');
    await tester.pumpWidget(
      RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          builder: (context, child) => Stack(
            children: [
              const Positioned.fill(child: GlassBackdrop()),
              if (child != null) child,
            ],
          ),
          home: const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 300,
                    child: Glass(
                      radius: 26,
                      blur: Blur.regular,
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Liquid Glass',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF101320))),
                          SizedBox(height: 6),
                          Text('浅色档：乳白为主，倒角仍是白色的光',
                              style: TextStyle(
                                  fontSize: 12.5, color: Color(0xFF5A6175))),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 26),
                  SizedBox(
                    width: 300,
                    child: Glass(
                      radius: 26,
                      blur: Blur.regular,
                      sheer: true,
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Clear Glass',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF101320))),
                          SizedBox(height: 6),
                          Text('体色压到最低',
                              style: TextStyle(
                                  fontSize: 12.5, color: Color(0xFF5A6175))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await _shot(tester, k, '04-浅色模式');
  });

  testWidgets('单块玻璃特写', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    const k = ValueKey('shot3');
    await tester.pumpWidget(
      RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.dark),
          builder: (context, child) => Stack(
            children: [
              const Positioned.fill(child: GlassBackdrop()),
              if (child != null) child,
            ],
          ),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                _busyContent(dark: true),
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 300,
                        child: Glass(
                          radius: 26,
                          blur: Blur.regular,
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Liquid Glass',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              SizedBox(height: 6),
                              Text('折射 · 侧光 · 倒角 · 厚度',
                                  style: TextStyle(
                                      fontSize: 12.5, color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 26),
                      SizedBox(
                        width: 300,
                        child: Glass(
                          radius: 26,
                          blur: Blur.regular,
                          sheer: true,
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Clear Glass（全透明档）',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              SizedBox(height: 6),
                              Text('体色几乎为零，只剩倒角',
                                  style: TextStyle(
                                      fontSize: 12.5, color: Colors.white70)),
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
        ),
      ),
    );

    await _shot(tester, k, '03-单块玻璃特写');
  });
}

class _DockItem extends StatelessWidget {
  const _DockItem(this.label, this.icon, this.on);
  final String label;
  final IconData icon;
  final bool on;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 25,
                color: on ? const Color(0xFF7C5CFF) : Colors.white70),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                    color: on ? const Color(0xFF7C5CFF) : Colors.white70)),
          ],
        ),
      );
}
