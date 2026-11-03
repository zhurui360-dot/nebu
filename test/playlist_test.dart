import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/screens/category.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Track _t(String id, String title) => Track(
      id: id,
      title: title,
      albumId: 'al-$id',
      albumName: '专辑 $id',
      artist: '歌手 $id',
      duration: const Duration(minutes: 3),
      format: MusicFormat.flac,
    );

AppState _app() {
  final app = AppState(LibraryRepository());
  app.tracks = [_t('a', '第一首'), _t('b', '第二首'), _t('c', '第三首')];
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('歌单数据层', () {
    test('新建歌单后能按加入顺序取出曲目', () async {
      final app = _app();
      final pl = await app.createPlaylist('通勤', trackIds: ['b', 'a']);

      expect(app.playlists.length, 1);
      // 4 个智能歌单 + 1 个自建
      expect(app.playlistCount, 5);

      final list = app.tracksOfPlaylist(pl.id);
      expect(list.map((t) => t.id).toList(), ['b', 'a']);
      expect(list.first.title, '第二首');
    });

    test('加入歌单会去重，返回真正新增的数量', () async {
      final app = _app();
      final pl = await app.createPlaylist('通勤');

      expect(await app.addToPlaylist(pl.id, ['a', 'b']), 2);
      expect(await app.addToPlaylist(pl.id, ['b', 'c']), 1);
      expect(app.playlistOf(pl.id)!.trackIds, ['a', 'b', 'c']);
    });

    test('移出、重命名、删除', () async {
      final app = _app();
      final pl = await app.createPlaylist('通勤', trackIds: ['a', 'b']);

      await app.removeFromPlaylist(pl.id, 'a');
      expect(app.tracksOfPlaylist(pl.id).map((t) => t.id), ['b']);

      await app.renamePlaylist(pl.id, '上班路上');
      expect(app.playlistOf(pl.id)!.name, '上班路上');

      await app.deletePlaylist(pl.id);
      expect(app.playlists, isEmpty);
      expect(app.playlistCount, 4);
      expect(app.tracksOfPlaylist(pl.id), isEmpty);
    });

    test('曲库删掉的歌不会让歌单崩，直接跳过', () {
      final app = _app();
      app.tracks = [_t('a', '第一首')];
      // 直接塞一个不存在的 id
      app.playlists = [
        Playlist(id: 'pl-x', name: '旧歌单', trackIds: ['a', '已删除的歌']),
      ];
      expect(app.tracksOfPlaylist('pl-x').map((t) => t.id), ['a']);
    });

    test('json 存档能往返', () {
      final pl = Playlist(
        id: 'pl-1',
        name: '深夜',
        trackIds: ['a', 'b'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final back = Playlist.fromJson(pl.toJson());
      expect(back.id, pl.id);
      expect(back.name, pl.name);
      expect(back.trackIds, pl.trackIds);
      expect(back.createdAt, pl.createdAt);
    });
  });

  group('删除歌曲', () {
    // 纯内存状态断言：测试环境没有 sqflite 原生库，写库部分由真机验收覆盖
    test('曲库移除后索引与歌单引用一起清掉', () {
      final app = _app();
      app.playlists = [
        Playlist(id: 'pl-1', name: '通勤', trackIds: ['a', 'b', 'c']),
      ];
      app.favorites.add('b');
      app.recent.insert(0, 'b');

      final changed = app.removeTrackLocal('b');
      expect(changed, isTrue);

      // 曲库
      expect(app.tracks.map((t) => t.id), ['a', 'c']);
      expect(app.trackOf('b'), isNull);
      expect(app.tracksOfAlbum('al-b'), isEmpty);

      // 收藏 / 最近播放 / 歌单
      expect(app.favorites.contains('b'), isFalse);
      expect(app.recent.contains('b'), isFalse);
      expect(app.playlistOf('pl-1')!.trackIds, ['a', 'c']);
    });

    test('删不存在的歌是空操作', () {
      final app = _app();
      expect(app.removeTrackLocal('不存在'), isNull);
      expect(app.tracks.length, 3);
    });

    test('歌单里没引用时返回 false（不需要落盘歌单）', () {
      final app = _app();
      app.playlists = [Playlist(id: 'pl-1', name: '空', trackIds: ['a'])];
      expect(app.removeTrackLocal('b'), isFalse);
      expect(app.tracks.map((t) => t.id), ['a', 'c']);
    });
  });

  group('歌单界面', () {
    testWidgets('歌单页有「新建歌单」，自建歌单点进去能看到曲目', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final app = _app();
      final pl = await app.createPlaylist('通勤', trackIds: ['a']);
      final player = PlayerState();

      Widget wrap(Widget child) => MultiProvider(
            providers: [
              ChangeNotifierProvider<AppState>.value(value: app),
              ChangeNotifierProvider<PlayerState>.value(value: player),
            ],
            child: MaterialApp(
              theme: AppTheme.build(Brightness.dark),
              home: Scaffold(body: child),
            ),
          );

      await tester.pumpWidget(wrap(const CategoryScreen(kind: CategoryKind.playlists)));
      await tester.pumpAndSettle();

      expect(find.text('新建歌单'), findsOneWidget);
      expect(find.text('通勤'), findsOneWidget);
      expect(find.text('全部歌曲'), findsOneWidget);

      // 进入自建歌单
      await tester.pumpWidget(wrap(CategoryScreen(
        kind: CategoryKind.playlists,
        playlistId: pl.id,
      )));
      await tester.pumpAndSettle();

      expect(find.text('第一首'), findsOneWidget);
      expect(find.textContaining('共 1 首'), findsOneWidget);
    });

    testWidgets('空歌单给出加歌指引', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final app = _app();
      final pl = await app.createPlaylist('空歌单');

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<PlayerState>.value(value: PlayerState()),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          home: Scaffold(
            body: CategoryScreen(
              kind: CategoryKind.playlists,
              playlistId: pl.id,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('这个歌单还是空的'), findsOneWidget);
      expect(find.textContaining('长按'), findsWidgets);
    });
  });
}
