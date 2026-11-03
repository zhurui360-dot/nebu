import 'dart:io';
import 'dart:typed_data';

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/sources.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 回归：v0.0.64 重写「添加音乐来源」后，WebDAV 连接成功却不再往下走——
/// 选择弹层先 pop，再拿已失效的 context 去 showGlassSheet(ImportSheet)，
/// `context.mounted == false` 直接 return，目录选择面板永远不弹（添加不上）。
///
/// 正确姿势：pop 前先取 Navigator.of(context)，之后用 nav.context 串弹层；
/// 新账号检测只认「真连上的账号」，不能被内置占位源干扰。
void main() {
  setUpAll(() async {
    final bytes = await File('C:/Windows/Fonts/simhei.ttf').readAsBytes();
    final simhei = Future.value(ByteData.view(Uint8List.fromList(bytes).buffer));
    await (FontLoader('Roboto')..addFont(simhei)).load();
    await (FontLoader('SimHei')..addFont(simhei)).load();
    final icons = await File(
            'C:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
        .readAsBytes();
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(Uint8List.fromList(icons).buffer))))
        .load();
  });

  testWidgets('来源选择 → WebDAV → 连接成功 → 自动打开目录选择', (tester) async {
    final app = AppState(LibraryRepository());
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
              theme: AppTheme.build(Brightness.dark),
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

    await tester.pumpWidget(wrap(const SourcesScreen()));
    await tester.pumpAndSettle();

    // 1. 打开「添加音乐来源」
    await tester.tap(find.text('添加音乐来源'));
    await tester.pumpAndSettle();

    // 2. 选 WebDAV（已连过账号时文案是「再连一个 WebDAV 账号」）
    final webdavOption =
        find.textContaining('WebDAV').hitTestable(at: Alignment.center);
    expect(webdavOption, findsWidgets);
    await tester.tap(webdavOption.first);
    await tester.pumpAndSettle();
    expect(find.text('连接 WebDAV'), findsOneWidget);

    // 3. 模拟「连接成功」：saveWebdav 会把真账号写进 sources，然后弹层自己 pop
    app.sources = [
      ...app.sources.where((s) => s.id != 'webdav'),
      const CloudSource(
        id: 'webdav2',
        name: 'WebDAV · dav.example.com',
        kind: SourceKind.webdav,
        subtitle: 'dav.example.com',
        connected: true,
        gradient: [0xFF2E3A52, 0xFF5A6B8C],
        baseUrl: 'https://dav.example.com/dav/',
        username: 'me@example.com',
      ),
    ];
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    // 修复前：这里找不到 —— ImportSheet 没弹，流程断在半路
    expect(find.text('选择音乐目录'), findsOneWidget,
        reason: '连接成功后应自动打开目录选择面板');
  });

  testWidgets('全新安装：占位源不算「已连接」，不显示孤儿目录行', (tester) async {
    final app = AppState(LibraryRepository());
    final player = PlayerState()..attach(app);

    Widget wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(Brightness.dark),
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
        );

    await tester.pumpWidget(wrap(const SourcesScreen()));
    await tester.pumpAndSettle();

    // 占位源（connected: false）不能显示成「已连接 · 还没选目录」
    expect(find.text('已连接 · 还没选目录，点这里挑'), findsNothing);
  });
}
