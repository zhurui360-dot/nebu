import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/category.dart';
import 'package:cloudtune/screens/me.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:cloudtune/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _out = 'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-v2-preview';

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

/// 页面上有循环动画（进度条流光、扫描闪烁）时 pumpAndSettle 不会停，用固定帧
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 200));
}

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

Track _t(int i) => Track(
      id: 'tr-$i',
      title: const [
        '听见光的样子',
        '雪落下的声音',
        '这一秒 只想安静',
        '夜航西飞',
        '雨落在旧街道',
        '光年之外',
        'halo',
        '晚风',
      ][i % 8],
      albumId: 'al-${i % 4}',
      albumName: '专辑 ${i % 4}',
      artist: const ['林屿', '陈一禾', 'Luna', '北辰'][i % 4],
      duration: Duration(minutes: 3, seconds: 20 + i),
      format: MusicFormat.flac,
      addedAt: 1700000000 + i,
    );

void main() {
  setUpAll(_loadFont);

  testWidgets('多选 / 歌手页 / 我的 / 文件名规则', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = AppState(LibraryRepository());
    app.tracks = [for (var i = 0; i < 10; i++) _t(i)];
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

    // ---- 1. 全部歌曲：进多选，勾两首 ----
    // 每个 case 换 key：否则同类型 widget 会复用上一个的 State（多选状态会串场）
    await tester.pumpWidget(wrap(
        const CategoryScreen(key: ValueKey('all'), kind: CategoryKind.all)));
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.checklist_rounded).first);
    await _settle(tester);
    await tester.tap(find.text('听见光的样子').first);
    await tester.pump();
    await tester.tap(find.text('雪落下的声音').first);
    await tester.pump();
    await _shot(tester, '01-多选加入歌单');

    // ---- 2. 歌手页：头像 + 播放全部 ----
    await tester.pumpWidget(wrap(const CategoryScreen(
      key: ValueKey('artist'),
      kind: CategoryKind.all,
      artistFilter: '林屿',
    )));
    await _settle(tester);
    await _shot(tester, '02-歌手页');

    // ---- 3. 我的：边听边缓存显示上限 + 新增两行 ----
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me'))));
    await _settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pump();
    await _shot(tester, '03-我的-音乐库');

    // ---- 4. 文件名规则面板（自定义模板 + 预览） ----
    await tester.pumpWidget(wrap(Builder(builder: (ctx) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: FilenameRuleSheet(),
      );
    })));
    await _settle(tester);
    await tester.tap(find.text('自定义'));
    await tester.pump();
    await _shot(tester, '04-文件名规则');
  });
}
