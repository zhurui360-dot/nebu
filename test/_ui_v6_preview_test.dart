import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/category.dart';
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

const _out = 'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-v6-preview';

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

  testWidgets('Nebu：行下展开面板 / 悬浮条 / 新封面', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = AppState(LibraryRepository());
    app.tracks = [
      const Track(
        id: 'tr-1',
        title: '听见光的样子',
        albumId: 'al-1',
        albumName: '夜航',
        artist: '林屿',
        duration: Duration(minutes: 3, seconds: 42),
        format: MusicFormat.flac,
        addedAt: 1700000000,
      ),
      const Track(
        id: 'tr-2',
        title: '雪落下的声音',
        albumId: 'al-2',
        albumName: '冬',
        artist: '陈一禾',
        duration: Duration(minutes: 4),
        format: MusicFormat.flac,
        addedAt: 1700000001,
      ),
      const Track(
        id: 'tr-3',
        title: '晚风收音机',
        albumId: 'al-3',
        albumName: '沿海',
        artist: '海边的卡夫卡',
        duration: Duration(minutes: 3, seconds: 20),
        format: MusicFormat.mp3,
        addedAt: 1700000002,
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

    // 1. 全部歌曲：悬浮播放条（浮层）
    await tester.runAsync(() async {
      await tester.pumpWidget(
          wrap(const CategoryScreen(key: ValueKey('all'), kind: CategoryKind.all)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    await _settle(tester);
    await _shot(tester, '01-全部歌曲-悬浮条');

    // 2. 我的 → 我的音乐：从卡片下方展开
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me1'))));
    await _settle(tester);
    await tester.tap(find.text('我的音乐'));
    await _settle(tester);
    await _shot(tester, '02-我的音乐-行下展开');
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // 3. 我的 → 边听边缓存：从这一行下方展开
    await tester.tap(find.text('边听边缓存'));
    await _settle(tester);
    await _shot(tester, '03-边听缓存-行下展开');
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // 4. 我的 → 清除缓存数据：确认面板也贴在行下
    await tester.tap(find.text('清除缓存数据'));
    await _settle(tester);
    await _shot(tester, '04-清除所有数据-行下展开');
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // 5. 播放页：没有封面的歌用新品牌图
    player.currentId = 'tr-3';
    player.mode = PlayerMode.cover;
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap(const PlayerScreen(key: ValueKey('p1'))));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });
    await _shot(tester, '05-无封面-品牌图');
  });
}
