import 'dart:io';

import 'package:flutter/services.dart';

/// 预览类测试需要真实字形（中文字体 + Material 图标），否则截图全是方框。
///
/// 这些字体在每台机器上的位置都不同，CI 上更是完全没有中文字体，
/// 所以这里只做「能找到就用」，找不到就安静跳过——断言不依赖字形，
/// 只有本地生成截图时才有意义。
Future<void> loadTestFonts() async {
  final cache = _flutterCacheDir();

  // 1) Material 图标：Flutter SDK 自带，路径可以从当前 dart 可执行文件推出来
  if (cache != null) {
    for (final name in const [
      'materialicons-regular.otf',
      'materialicons-regular.ttf',
    ]) {
      final f = File('$cache/artifacts/material_fonts/$name');
      if (await _load(f, const ['MaterialIcons'])) return _loadCjk(cache);
    }
  }
  await _loadCjk(cache);
}

Future<void> _loadCjk(String? cache) async {
  for (final path in _cjkCandidates) {
    final f = File(path);
    if (f.existsSync()) {
      await _load(f, const ['Roboto', 'SimHei']);
      return;
    }
  }
}

Future<bool> _load(File file, List<String> families) async {
  if (!file.existsSync()) return false;
  try {
    final bytes = await file.readAsBytes();
    for (final family in families) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
      await loader.load();
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Flutter 的 bin/cache 目录：<flutter>/bin/cache/dart-sdk/bin/dart
String? _flutterCacheDir() {
  try {
    final exe = File(Platform.resolvedExecutable);
    final cache = exe.parent.parent.parent;
    return cache.path.replaceAll('\\', '/');
  } catch (_) {
    return null;
  }
}

const _cjkCandidates = <String>[
  // Windows
  'C:/Windows/Fonts/simhei.ttf',
  'C:/Windows/Fonts/msyh.ttc',
  'C:/Windows/Fonts/msyh.ttf',
  // macOS
  '/System/Library/Fonts/PingFang.ttc',
  '/System/Library/Fonts/Hiragino Sans GB.ttc',
  // Linux（CI 上装了 noto 才有）
  '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
];
