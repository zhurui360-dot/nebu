import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/category.dart';
import 'package:cloudtune/screens/player.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'test_fonts.dart';

const _out =
    'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-player-preview';

const _logo = 'C:/Users/36018/WorkBuddy/2026-10-24-15-55-22/cloudtune_app/assets/branding/logo_nebu.jpg';

Future<void> _loadFont() => loadTestFonts();

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump(const Duration(milliseconds: 260));
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

  testWidgets('播放页与新入口截图', (tester) async {
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
        coverPath: _logo,
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
    ];
    final player = PlayerState()..attach(app);
    // 不走 play()：那会去写 sqflite（测试环境没初始化 factory），
    // 截图只需要"有一首当前曲目"
    player.currentId = 'tr-1';
    player.mode = PlayerMode.cover;

    Widget wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          // 截图边界要放在 MaterialApp 外面：
          // 放 home 里的话，压下一条路由后 home 就 offstage 了，抓不到
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

    // 封面是真的图片文件，测试环境默认不解码，用 runAsync 让编解码真的跑一遍
    await tester.pumpWidget(wrap(const PlayerScreen()));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await _shot(tester, '01-播放页-封面');

    // 同一套控件的歌词页，确认新加的「加入歌单」也在
    player.toggleMode();
    await tester.pump(const Duration(milliseconds: 260));
    await _shot(tester, '01b-播放页-歌词');

    // 专辑页：从按钮里走 pushAlbum，验证新入口能正常打开
    await tester.pumpWidget(wrap(Builder(builder: (ctx) {
      return Center(
        child: TextButton(
          onPressed: () => pushAlbum(ctx, app.albumOf('al-1')),
          child: const Text('open album'),
        ),
      );
    })));
    await tester.pump();
    await tester.tap(find.text('open album'));
    // 播放进度条有个循环流光动画，pumpAndSettle 永远不会停，用固定帧推进
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await _shot(tester, '02-专辑页');
  });
}
