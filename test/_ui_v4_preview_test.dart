import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/me.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/settings_sheets.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'test_fonts.dart';

const _out = 'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-v4-preview';

Future<void> _loadFont() => loadTestFonts();

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 260));
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 200));
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFont);

  testWidgets('我的音乐抽屉 / 缓存 / 网盘引导', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = AppState(LibraryRepository());
    app.savedFolders = [
      const SavedFolder(
          id: 'local::/storage/emulated/0/Music',
          sourceId: 'local',
          path: '/storage/emulated/0/Music',
          fileCount: 128),
      const SavedFolder(
          id: 'local::/storage/emulated/0/Download/无损',
          sourceId: 'local',
          path: '/storage/emulated/0/Download/无损',
          fileCount: 46),
      const SavedFolder(
          id: 'webdav::/音乐',
          sourceId: 'webdav',
          path: '/音乐',
          fileCount: 302),
    ];
    final player = PlayerState()..attach(app);

    Widget wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: RepaintBoundary(
            key: const Key('shot'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(Brightness.dark).copyWith(
                textTheme: AppTheme.build(Brightness.dark)
                    .textTheme
                    .apply(fontFamily: 'SimHei'),
              ),
              home: Stack(
                children: [
                  const Positioned.fill(child: GlassBackdrop()),
                  Positioned.fill(
                    child: Scaffold(
                      backgroundColor: Colors.transparent,
                      body: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    // 1. 我的：卡片改名 + 缓存行
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me'))));
    await _settle(tester);
    await _shot(tester, '01-我的');

    // 2. 抽屉：已添加的目录
    await tester.tap(find.text('我的音乐'));
    await _settle(tester);
    await _shot(tester, '02-我的音乐抽屉');

    // 关掉抽屉：下面还会 pumpWidget 复用同一个 MaterialApp，路由不会自动清
    await tester.tapAt(const Offset(200, 60));
    await _settle(tester);

    // 3. 语言选择（居中弹窗）+ 保存目录（居中弹窗）
    await tester.pumpWidget(wrap(const Align(
      alignment: Alignment.center,
      child: LanguageSheet(key: ValueKey('lang')),
    )));
    await _settle(tester);
    await _shot(tester, '03-语言选择');

    await tester.pumpWidget(wrap(const Align(
      alignment: Alignment.center,
      child: DownloadDirSheet(key: ValueKey('dir')),
    )));
    await _settle(tester);
    await _shot(tester, '04-音乐保存目录');
  });
}
