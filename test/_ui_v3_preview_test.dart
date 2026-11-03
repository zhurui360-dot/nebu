import 'dart:io';
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

const _out = 'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-v3-preview';

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
  await tester.pump(const Duration(milliseconds: 240));
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

Track _t(int i) => Track(
      id: 'tr-$i',
      title: const [
        '听见光的样子',
        '雪落下的声音',
        '这一秒 只想安静',
        '夜航西飞',
        '雨落在旧街道',
        '光年之外',
      ][i % 6],
      albumId: 'al-${i % 3}',
      albumName: '专辑 ${i % 3}',
      artist: const ['林屿', '陈一禾', 'Luna'][i % 3],
      duration: Duration(minutes: 3, seconds: 20 + i),
      format: MusicFormat.flac,
      addedAt: 1700000000 + i,
    );

void main() {
  setUpAll(_loadFont);

  testWidgets('悬浮播放 / 我的缓存 / 确认 / 文件名间隔', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = AppState(LibraryRepository());
    app.tracks = [for (var i = 0; i < 8; i++) _t(i)];
    app.filenameSep = '-–—_·';
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

    // 1. 全部歌曲 + 底部悬浮播放控件
    await tester.pumpWidget(wrap(
        const CategoryScreen(key: ValueKey('all'), kind: CategoryKind.all)));
    await _settle(tester);
    await _shot(tester, '01-全部歌曲-悬浮播放');

    // 2. 我的：边听缓存显示大小
    await tester.pumpWidget(wrap(const MeScreen(key: ValueKey('me'))));
    await _settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pump();
    // 等缓存大小统计回来
    await tester.pump(const Duration(seconds: 3));
    await _shot(tester, '02-我的-缓存大小');

    // 3. 清除所有数据：必须输入 yes
    await tester.tap(find.text('清除缓存数据'));
    await _settle(tester);
    await _shot(tester, '03-输入yes确认');
    // 关掉弹窗：下一个 case 复用同一个 MaterialApp，Navigator 里的路由不会自动清
    await tester.tap(find.text('取消'));
    await _settle(tester);

    // 4. 文件名规则：自定义模板 + 间隔符号
    await tester.pumpWidget(wrap(const Align(
      alignment: Alignment.bottomCenter,
      child: FilenameRuleSheet(key: ValueKey('rule')),
    )));
    await _settle(tester);
    await tester.tap(find.text('自定义'));
    await _settle(tester);
    await _shot(tester, '04-文件名间隔符号');
  });
}
