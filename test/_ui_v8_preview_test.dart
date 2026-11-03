import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/l10n/lang.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/me.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:cloudtune/widgets/settings_sheets.dart';
import 'package:cloudtune/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _out = 'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-v8-preview';

Future<void> _loadFont() async {
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
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('v0.0.65：多语言 / 主题自动 / 下载到本地', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = AppState(LibraryRepository());
    app.tracks = [
      Track(
        id: 'tr-1',
        title: '听见光的样子',
        albumId: 'al-1',
        albumName: '夜航',
        artist: '林屿',
        duration: const Duration(minutes: 3, seconds: 42),
        format: MusicFormat.flac,
        addedAt: 1700000000,
      ),
      Track(
        id: 'tr-2',
        title: '雪落下的声音',
        albumId: 'al-2',
        albumName: '冬',
        artist: '陈一禾',
        duration: const Duration(minutes: 4),
        format: MusicFormat.flac,
        addedAt: 1700000001,
      ),
    ];
    app.savedFolders = [
      const SavedFolder(
        id: 'local::/storage/emulated/0/Music',
        sourceId: 'local',
        path: '/storage/emulated/0/Music',
        fileCount: 128,
        includeSub: true,
      ),
    ];
    final player = PlayerState()..attach(app);
    player.currentId = 'tr-1';

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

    // 1. 我的页（中文）：外观组新增「自动 / 浅色 / 深色」三档 + 语言行
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me-zh'))));
    await _settle(tester);
    await _shot(tester, '01-我的-中文-主题三档');

    // 2. 语言弹窗：跟随系统 + 7 种语言
    await tester.tap(find.text('语言'));
    await _settle(tester);
    await _shot(tester, '02-语言选择');
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // 3. 同一页切英文：整页文案跟着变
    await app.setLang(AppLang.en);
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me-en'))));
    await _settle(tester);
    await _shot(tester, '03-我的-英文');

    // 4. 切维吾尔语：核心界面已翻译
    await app.setLang(AppLang.ug);
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me-ug'))));
    await _settle(tester);
    await _shot(tester, '04-我的-维语');

    // 5. 音乐保存目录（居中弹窗，列出三个真实路径）
    await app.setLang(AppLang.zhHans);
    await tester.pumpWidget(wrap(Align(
      alignment: Alignment.center,
      child: const DownloadDirSheet(key: ValueKey('dir')),
    )));
    await _settle(tester);
    await _shot(tester, '05-音乐保存目录');

    // 6. 歌曲菜单：新增「下载到本地」
    await tester.pumpWidget(wrap(Builder(
      builder: (ctx) => Center(
        child: TextButton(
          onPressed: () => showTrackActionsSheet(ctx, track: app.tracks.first),
          child: const Text('打开歌曲菜单'),
        ),
      ),
    )));
    await _settle(tester);
    await tester.tap(find.text('打开歌曲菜单'));
    await _settle(tester);
    await _shot(tester, '06-歌曲菜单-下载到本地');
  });
}
