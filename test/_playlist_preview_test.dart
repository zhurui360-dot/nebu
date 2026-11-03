import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/category.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _out =
    'C:/Users/36018/WorkBuddy/2026-10-25-14-17-04/cloudtune-playlist-preview';

Future<void> _loadFont() async {
  final bytes = await File('C:/Windows/Fonts/simhei.ttf').readAsBytes();
  final loader = FontLoader('SimHei')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();

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
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
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

  testWidgets('歌单页截图', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = AppState(LibraryRepository());
    app.tracks = [for (var i = 0; i < 12; i++) _t(i)];
    final pl1 = await app.createPlaylist('深夜通勤',
        trackIds: ['tr-0', 'tr-1', 'tr-2', 'tr-3']);
    final pl2 = await app.createPlaylist('雨天');
    final player = PlayerState();

    Widget wrap(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(Brightness.dark).copyWith(
              textTheme: AppTheme.build(Brightness.dark)
                  .textTheme
                  .apply(fontFamily: 'SimHei'),
            ),
            home: RepaintBoundary(
              key: const Key('shot'),
              child: Stack(
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

    await tester.pumpWidget(
        wrap(const CategoryScreen(kind: CategoryKind.playlists)));
    await tester.pumpAndSettle();
    await _shot(tester, const Key('shot'), '01-歌单列表');

    await tester.pumpWidget(wrap(
        CategoryScreen(kind: CategoryKind.playlists, playlistId: pl1.id)));
    await tester.pumpAndSettle();
    await _shot(tester, const Key('shot'), '02-歌单详情');

    await tester.pumpWidget(wrap(
        CategoryScreen(kind: CategoryKind.playlists, playlistId: pl2.id)));
    await tester.pumpAndSettle();
    await _shot(tester, const Key('shot'), '03-空歌单');
  });
}
