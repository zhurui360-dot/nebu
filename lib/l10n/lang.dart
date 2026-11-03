import 'package:flutter/widgets.dart';

/// 支持的界面语言。
///
/// 顺序即 `_dict` 里每条翻译的列顺序（见 strings.dart），
/// 改动顺序会让所有翻译错位，别随便调。
enum AppLang {
  zhHans('zh', '简体中文'),
  zhHant('zh_Hant', '繁體中文'),
  en('en', 'English'),
  ja('ja', '日本語'),
  ko('ko', '한국어'),
  // 藏语 / 维吾尔语：核心界面已翻译，长尾文案回退英文
  bo('bo', 'བོད་ཡིག'),
  ug('ug', 'ئۇيغۇرچە');

  const AppLang(this.code, this.nativeName);

  /// 存储用的语言码（空字符串 = 跟随系统）
  final String code;

  /// 语言选择器里显示的名字：一律用该语言自己的写法
  final String nativeName;

  /// 切给 MaterialApp 的 Locale。
  /// 繁体中文要带 script，否则系统会当成简体。
  Locale get locale => code == 'zh_Hant'
      ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
      : Locale(code);

  static AppLang? byCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final l in AppLang.values) {
      if (l.code == code) return l;
    }
    return null;
  }

  /// 设备语言 → App 语言。认不出的一律英文。
  static AppLang fromLocale(Locale? l) {
    if (l == null) return zhHans;
    switch (l.languageCode) {
      case 'zh':
        // 繁体：带 Hant script，或地区是台港澳
        final script = l.scriptCode ?? '';
        final region = l.countryCode ?? '';
        if (script == 'Hant' ||
            script == 'HK' ||
            const ['TW', 'HK', 'MO'].contains(region)) {
          return zhHant;
        }
        return zhHans;
      case 'ja':
        return AppLang.ja;
      case 'ko':
        return AppLang.ko;
      case 'bo':
      case 'ti':
        return AppLang.bo;
      case 'ug':
        return AppLang.ug;
      case 'en':
        return AppLang.en;
      default:
        return AppLang.en;
    }
  }
}
