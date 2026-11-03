import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/category.dart';
import 'package:cloudtune/screens/library.dart';
import 'package:cloudtune/screens/me.dart';
import 'package:cloudtune/screens/player.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _out = 'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-v5-preview';
const _logo =
    'C:/Users/36018/WorkBuddy/2026-10-24-15-55-22/cloudtune_app/assets/branding/logo_nebu.jpg';

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

  testWidgets('我的抽屉统一 / 编辑我的 / 悬浮条歌词 / 播放页交互', (tester) async {
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
        coverPath: _logo,
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
          fileCount: 128),
      const SavedFolder(
          id: 'webdav::/音乐',
          sourceId: 'webdav',
          path: '/音乐',
          fileCount: 302),
    ];
    final player = PlayerState()..attach(app);
    player.currentId = 'tr-1';
    player.debugSetLyrics(const [
      LyricLine(Duration.zero, '把窗帘拉开一点'),
      LyricLine(Duration(seconds: 6), '让光落在你的侧脸'),
      LyricLine(Duration(seconds: 12), '我们不急着说再见'),
    ], active: 1);

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

    // 1. 全部歌曲 + 悬浮播放条（3/4 宽 + 歌词）
    await tester.runAsync(() async {
      await tester.pumpWidget(
          wrap(const CategoryScreen(key: ValueKey('all'), kind: CategoryKind.all)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    await _settle(tester);
    await _shot(tester, '01-全部歌曲-悬浮条带歌词');

    // 2. 音乐库 → 编辑「我的」
    await tester.pumpWidget(wrap(const LibraryScreen(key: ValueKey('lib'))));
    await _settle(tester);
    await _shot(tester, '02-音乐库-我的可编辑');
    await tester.tap(find.text('编辑'));
    await _settle(tester);
    await _shot(tester, '03-编辑我的抽屉');
    await tester.tapAt(const Offset(200, 40));
    await _settle(tester);

    // 3. 我的 → 清除所有数据（抽屉 + 手输 yes）
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me'))));
    await _settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await _settle(tester);
    await tester.tap(find.text('清除缓存数据'));
    await _settle(tester);
    await _shot(tester, '04-清除所有数据抽屉');
    await tester.tapAt(const Offset(200, 40));
    await _settle(tester);

    // 4. 播放页：封面（歌手名带 ›）
    player.mode = PlayerMode.cover;
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap(const PlayerScreen(key: ValueKey('p1'))));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });
    await _shot(tester, '05-播放页-封面');

    // 5. 歌词页
    player.toggleMode();
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '06-播放页-歌词');

    // 6. 我的音乐抽屉：和上面几个面板同一套外壳
    player.mode = PlayerMode.cover;
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me2'))));
    await _settle(tester);
    await tester.tap(find.text('我的音乐'));
    await _settle(tester);
    await _shot(tester, '07-我的音乐抽屉');
  });
}
