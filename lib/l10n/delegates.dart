import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// 让 Material / Cupertino / Widgets 的内置文案在任何语言下都可用。
///
/// 我们自己的界面文案走 [L]（见 strings.dart），这里只负责撑住
/// Flutter 内部那些我们没法替换的字符串（文本选择菜单、语义标签等）。
/// 之所以不用 flutter_localizations：藏语、维吾尔语它都不支持，
/// 一旦 Locale 落在不支持的语种上，Localizations 会直接报错。
class AnyLocaleMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const AnyLocaleMaterialDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.load(const Locale('en', 'US'));

  @override
  bool shouldReload(AnyLocaleMaterialDelegate old) => false;
}

class AnyLocaleCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const AnyLocaleCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.load(const Locale('en', 'US'));

  @override
  bool shouldReload(AnyLocaleCupertinoDelegate old) => false;
}

class AnyLocaleWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const AnyLocaleWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<WidgetsLocalizations>(const DefaultWidgetsLocalizations());

  @override
  bool shouldReload(AnyLocaleWidgetsDelegate old) => false;
}

const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AnyLocaleMaterialDelegate(),
  AnyLocaleCupertinoDelegate(),
  AnyLocaleWidgetsDelegate(),
];
