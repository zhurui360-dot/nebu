import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:cloudtune/widgets/floating_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('悬浮播放条：滑动时隐藏，停手后回来', (tester) async {
    final app = AppState(LibraryRepository());
    app.tracks = [
      const Track(
        id: 'tr-1',
        title: '听见光的样子',
        albumId: 'al-1',
        albumName: '夜航',
        artist: '林屿',
        duration: Duration(minutes: 3),
        format: MusicFormat.flac,
        addedAt: 1700000000,
      ),
    ];
    final player = PlayerState()..attach(app);
    player.currentId = 'tr-1';

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<PlayerState>.value(value: player),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: Scaffold(
          body: FloatingPlayerOverlay(
            child: ListView.builder(
              itemCount: 60,
              itemBuilder: (c, i) => SizedBox(
                height: 60,
                child: Text('行 $i'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    double opacity() => tester
        .widget<AnimatedOpacity>(find.descendant(
          of: find.byType(FloatingPlayerOverlay),
          matching: find.byType(AnimatedOpacity),
        ))
        .opacity;

    expect(find.byType(FloatingPlayerBar), findsOneWidget);
    expect(opacity(), 1);

    // 滑动 → 隐藏
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(opacity(), 0, reason: '滑动时应该躲开');

    // 停手后回来
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(opacity(), 1, reason: '停止滑动后应该重新浮出来');
  });
}
