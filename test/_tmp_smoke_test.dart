import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/screens/category.dart';
import 'package:cloudtune/screens/me.dart';
import 'package:cloudtune/screens/player.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) {
  final app = AppState(LibraryRepository());
  final player = PlayerState();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<PlayerState>.value(value: player),
    ],
    // 包一层 Scaffold：SettingRow 内部用 InkWell，需要 Material 祖先
    child: MaterialApp(
      theme: AppTheme.build(Brightness.dark),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('我的页：我的音乐内联抽屉 / 缓存上限居中弹窗', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const MeScreen()));
    await tester.pumpAndSettle();

    // 账户卡改名「我的音乐」，不再有内联的「扫描本地音乐」
    expect(find.text('我的音乐'), findsOneWidget);
    expect(find.text('扫描本地音乐'), findsNothing);

    // 点卡片 → 在卡片下面展开已添加的目录（唯一保留的内联抽屉）
    await tester.tap(find.text('我的音乐'));
    await tester.pumpAndSettle();
    expect(find.text('添加目录 / 管理音乐来源'), findsOneWidget);
    expect(find.text('我的音乐'), findsOneWidget); // 内联展开不重复标题
    // 抽屉里新增「扫描音乐」按钮
    expect(find.text('扫描音乐'), findsOneWidget);

    // 再点一次收起
    await tester.tap(find.text('我的音乐'));
    await tester.pumpAndSettle();
    expect(find.text('添加目录 / 管理音乐来源'), findsNothing);

    // 边听边缓存整行 → 居中弹窗（不再是就地展开）
    await tester.tap(find.text('边听边缓存'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.textContaining('上限'), findsWidgets);

    // 弹窗在屏幕正中：中心点应接近屏幕中心
    final dlg = tester.getRect(find.byType(Dialog));
    expect((dlg.center.dx - 180).abs() < 20, isTrue);

    // 拖动滑条到 1G 档
    await tester.drag(find.byType(Slider), const Offset(-400, 0));
    await tester.pumpAndSettle();

    // 关掉弹窗
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('播放页：封面页渲染（含上下拖动切歌不崩）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const PlayerScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // 上下拖动封面区：只验证跟手位移 + 回弹不崩，
    // 拖动距离刻意小于切歌阈值（屏高 18%），避免触发 next() 带来的异步定时器
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 400));
    // 触控反馈/墨水动画会排一个短定时器，多泵一会儿让测试收尾干净
    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('全部歌曲：排序按钮从按钮位置弹出菜单', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const CategoryScreen(kind: CategoryKind.all)));
    await tester.pumpAndSettle();

    final btn = find.byIcon(Icons.sort_rounded);
    expect(btn, findsOneWidget);

    await tester.tap(btn);
    await tester.pumpAndSettle();

    // 菜单项渲染出来（每个维度只有一条），且落在按钮所在的右上区域（非全屏底部弹层）
    expect(find.text('创建时间'), findsOneWidget);
    final menuRect = tester.getRect(find.text('创建时间'));
    final btnRect = tester.getRect(btn);
    expect((menuRect.left - btnRect.left).abs() < 240, isTrue);

    // 点「歌名」一次 = 该维度默认方向（A→Z，菜单里显示升序箭头）
    await tester.tap(find.text('歌名'));
    await tester.pumpAndSettle();
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    // 再点同一维度一次 = 翻转成 Z→A（箭头掉头）
    await tester.tap(find.text('歌名'));
    await tester.pumpAndSettle();
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    await tester.tap(find.text('歌名'));
    await tester.pumpAndSettle();
  });

  testWidgets('收藏页不再有排序入口', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const CategoryScreen(kind: CategoryKind.favorites)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sort_rounded), findsNothing);
  });
}
