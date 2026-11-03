import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/category.dart';
import 'package:cloudtune/screens/me.dart';
import 'package:cloudtune/screens/sources.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _out = 'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-v7-preview';

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

  testWidgets('v0.0.64：居中弹窗 / 扫描按钮 / 来源纯添加', (tester) async {
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
      Track(
        id: 'tr-3',
        title: '晚风收音机',
        albumId: 'al-3',
        albumName: '沿海',
        artist: '海边的卡夫卡',
        duration: const Duration(minutes: 3, seconds: 20),
        format: MusicFormat.mp3,
        addedAt: 1700000002,
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
      const SavedFolder(
        id: 'webdav::/音乐',
        sourceId: 'webdav',
        path: '/音乐',
        fileCount: 302,
        includeSub: true,
      ),
    ];
    app.sources = [
      ...app.sources.where((s) => s.id != 'webdav'),
      const CloudSource(
        id: 'webdav',
        name: 'WebDAV · dav.jianguoyun.com',
        kind: SourceKind.webdav,
        subtitle: 'dav.jianguoyun.com',
        connected: true,
        gradient: [0xFF2E3A52, 0xFF5A6B8C],
        baseUrl: 'https://dav.jianguoyun.com/dav/',
        username: 'nebu@example.com',
      ),
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

    // 1. 全部歌曲：悬浮播放条（按键已加大）
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap(
          const CategoryScreen(key: ValueKey('all'), kind: CategoryKind.all)));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    await _settle(tester);
    await _shot(tester, '01-全部歌曲-悬浮条大按键');

    // 2. 我的 → 我的音乐：玻璃内联展开（已去掉圆头像）
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me1'))));
    await _settle(tester);
    await tester.tap(find.text('我的音乐'));
    await _settle(tester);
    await _shot(tester, '02-我的音乐-玻璃内联');
    await tester.tap(find.text('我的音乐'));
    await _settle(tester);

    // 3. 我的 → 边听边缓存（居中弹窗）
    await tester.tap(find.text('边听边缓存'));
    await _settle(tester);
    await _shot(tester, '03-边听缓存-居中弹窗');
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // 4. 我的 → 清除缓存数据（手打 yes，居中弹窗）
    await tester.tap(find.text('清除缓存数据'));
    await _settle(tester);
    await _shot(tester, '04-清除数据-居中弹窗');
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // 5. 我的 → 歌词源（居中弹窗）
    await tester.tap(find.text('歌词源 / 封面源'));
    await _settle(tester);
    await _shot(tester, '05-歌词源-居中弹窗');
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // 6. 音乐来源：唯一入口 + 已添加目录
    await tester.pumpWidget(wrap(const SourcesScreen(key: ValueKey('src1'))));
    await _settle(tester);
    await _shot(tester, '06-音乐来源-单入口');

    // 7. 来源选择面板（只做添加入口，不含已连账号）
    await tester.tap(find.text('添加音乐来源'));
    await _settle(tester);
    await _shot(tester, '07-选择来源-仅添加入口');
    // 点面板外面的遮罩关掉它（逻辑屏是 360×780，别点到面板上）
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);

    // 8. 目录编辑面板（账户信息挂在这里）
    await tester.tap(find.text('/音乐'));
    await _settle(tester);
    await _shot(tester, '08-目录编辑-含账号');
  });
}
