import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/l10n/lang.dart';
import 'package:cloudtune/l10n/strings.dart';
import 'package:cloudtune/screens/me.dart';
import 'package:cloudtune/services/download_service.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:cloudtune/state/player_state.dart';
import 'package:cloudtune/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _wrap(AppState app, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<PlayerState>.value(value: PlayerState()),
    ],
    child: MaterialApp(
      theme: AppTheme.build(Brightness.dark),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('语言解析', () {
    test('简体 / 繁体 / 日语 / 韩语', () {
      expect(AppLang.fromLocale(const Locale('zh', 'CN')), AppLang.zhHans);
      expect(AppLang.fromLocale(const Locale('zh', 'TW')), AppLang.zhHant);
      expect(AppLang.fromLocale(const Locale('zh', 'HK')), AppLang.zhHant);
      expect(
        AppLang.fromLocale(
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
        AppLang.zhHant,
      );
      expect(AppLang.fromLocale(const Locale('ja', 'JP')), AppLang.ja);
      expect(AppLang.fromLocale(const Locale('ko', 'KR')), AppLang.ko);
    });

    test('藏语 / 维吾尔语 / 兜底英文', () {
      expect(AppLang.fromLocale(const Locale('bo')), AppLang.bo);
      expect(AppLang.fromLocale(const Locale('ug')), AppLang.ug);
      // 不认识的语言一律英文，不要留空
      expect(AppLang.fromLocale(const Locale('fr', 'FR')), AppLang.en);
      expect(AppLang.fromLocale(null), AppLang.zhHans);
    });

    test('语言码往返', () {
      for (final l in AppLang.values) {
        expect(AppLang.byCode(l.code), l);
      }
      expect(AppLang.byCode(''), isNull); // 空 = 跟随系统
      expect(AppLang.byCode('xx'), isNull);
    });
  });

  group('文案回退', () {
    test('藏语没翻译的条目回退英文，再回退中文', () {
      const bo = L(AppLang.bo);
      // 'lang.title' 有藏语
      expect(bo.t('lang.title'), 'སྐད་ཡིག');
      // 'lib.byTime' 没有藏语 → 英文
      expect(bo.t('lib.byTime'), 'Newest first');
      // 'unit.artists' 藏语/维语都空 → 英文
      expect(bo.artists(3), '3 artists');
    });

    test('占位符替换', () {
      expect(const L(AppLang.en).songs(12), '12 songs');
      expect(const L(AppLang.ja).songs(12), '12 曲');
      expect(const L(AppLang.zhHant).songs(3), '3 首');
      expect(const L(AppLang.ko).t('me.upToDate', {'v': '0.0.65'}),
          contains('0.0.65'));
    });

    test('未知 key 原样返回（不会崩）', () {
      expect(const L(AppLang.en).t('no.such.key'), 'no.such.key');
    });

    test('七种语言都有导航文案', () {
      for (final l in AppLang.values) {
        final t = L(l);
        expect(t.tabHome.isNotEmpty, isTrue);
        expect(t.tabMe.isNotEmpty, isTrue);
        expect(t.tabSearch.isNotEmpty, isTrue);
      }
    });
  });

  group('设置项', () {
    test('语言：默认跟随系统，选过就固定', () async {
      final app = AppState(LibraryRepository());
      expect(app.followSystemLang, isTrue);

      await app.setLang(AppLang.ja);
      expect(app.followSystemLang, isFalse);
      expect(app.lang, AppLang.ja);

      await app.setLang(null);
      expect(app.followSystemLang, isTrue);
    });

    test('主题支持「自动」', () async {
      final app = AppState(LibraryRepository());
      await app.setTheme(ThemeMode.system);
      expect(app.themeMode, ThemeMode.system);
      expect(app.isDark, isFalse); // system 不等于深色
    });

    test('保存目录默认公共音乐目录，可切换', () async {
      final app = AppState(LibraryRepository());
      expect(app.downloadDir, DownloadDir.publicMusic);

      await app.setDownloadDir(DownloadDir.appPrivate);
      expect(app.downloadDir, DownloadDir.appPrivate);
      expect(app.downloadDir.isPublic, isFalse);
    });
  });

  testWidgets('切语言后「我的」页整页跟着变', (tester) async {
    // 屏幕给高一点：整页内容一次铺开，不用滚动就能断言到「语言」行
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = AppState(LibraryRepository());
    await app.setLang(AppLang.zhHans);

    await tester.pumpWidget(_wrap(app, const MeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);

    // 切英文
    await app.setLang(AppLang.en);
    await tester.pumpAndSettle();
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    // 切日语
    await app.setLang(AppLang.ja);
    await tester.pumpAndSettle();
    expect(find.text('マイ'), findsOneWidget);
    expect(find.text('言語'), findsOneWidget);
  });

  testWidgets('语言弹窗列出「跟随系统」+ 7 种语言', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = AppState(LibraryRepository());
    await tester.pumpWidget(_wrap(app, const MeScreen()));
    await tester.pumpAndSettle();

    // 点语言行打开居中弹窗
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
          of: find.byType(Dialog), matching: find.text('跟随系统')),
      findsOneWidget,
    );
    for (final l in AppLang.values) {
      // 页面上也会显示当前语言名，这里只认弹窗里的那一条
      expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text(l.nativeName)),
        findsOneWidget,
      );
    }

    // 选日语：弹窗里的语言行、页面标题都要立刻变
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(app.lang, AppLang.ja);
    expect(find.text('マイ'), findsOneWidget);
  });
}
