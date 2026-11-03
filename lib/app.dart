import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/root_shell.dart';
import 'widgets/common.dart' show GlassBackdrop;
import 'l10n/delegates.dart';
import 'services/audio_handler.dart';
import 'state/app_state.dart';
import 'state/player_state.dart';
import 'theme/app_theme.dart';

class CloudTuneApp extends StatelessWidget {
  const CloudTuneApp({super.key, required this.app, this.handler});

  final AppState app;

  /// 系统播放控件（通知栏 / 锁屏 / 耳机按键）
  final CloudTuneHandler? handler;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProxyProvider<AppState, PlayerState>(
          create: (_) => PlayerState(handler),
          update: (_, state, player) => (player ?? PlayerState())..attach(state),
        ),
      ],
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final dark = state.themeMode == ThemeMode.dark ||
              (state.themeMode == ThemeMode.system &&
                  MediaQuery.platformBrightnessOf(context) == Brightness.dark);
          // 状态栏 / 手势条保持全透明，图标颜色跟随明暗主题
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  dark ? Brightness.light : Brightness.dark,
              statusBarBrightness: dark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness:
                  dark ? Brightness.light : Brightness.dark,
            ),
            child: MaterialApp(
              title: 'Nebu',
              debugShowCheckedModeBanner: false,
              // 界面语言：跟随系统时用设备语言（AppState 已解析好）
              locale: state.lang.locale,
              supportedLocales: const [
                Locale('zh', 'CN'),
                Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
                Locale('en', 'US'),
                Locale('ja', 'JP'),
                Locale('ko', 'KR'),
                Locale('bo', 'CN'),
                Locale('ug', 'CN'),
              ],
              localizationsDelegates: appLocalizationsDelegates,
              theme: AppTheme.build(Brightness.light),
              darkTheme: AppTheme.build(Brightness.dark),
              themeMode: state.themeMode,
              // 全局毛玻璃底：所有页面背景透明，浮在这层之上
              builder: (context, child) => Stack(
                children: [
                  const Positioned.fill(child: GlassBackdrop()),
                  if (child != null) child,
                ],
              ),
              home: const RootShell(),
            ),
          );
        },
      ),
    );
  }
}
