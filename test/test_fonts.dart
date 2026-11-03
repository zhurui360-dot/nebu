import 'dart:io';

import 'package:flutter/services.dart';

/// 预览类测试需要真实字形（中文字体 + Material 图标），否则截图全是方框。
///
/// 这些字体在每台机器上的位置都不同，CI 上更是完全没有中文字体，
/// 所以这里只做「能找到就用」，找不到就安静跳过——断言不依赖字形，
/// 只有本地生成截图时才有意义。
Future<void> loadTestFonts() async {
  final icons = _findMaterialIcons();
  if (icons != null) await _load(icons, const ['MaterialIcons']);
  await _loadCjk();
}

/// Material 图标在 Flutter SDK 的 bin/cache/artifacts/material_fonts 下。
/// `flutter test` 跑的是 flutter_tester，可执行文件在很深的 engine 目录里，
/// 所以这里从几个起点向上逐级探测，而不是假设一个固定层数。
File? _findMaterialIcons() {
  const names = ['materialicons-regular.otf', 'materialicons-regular.ttf'];
  final roots = <String>[
    Platform.environment['FLUTTER_ROOT'] ?? '',
    File(Platform.resolvedExecutable).parent.path,
    Directory.current.path,
  ];

  for (final root in roots) {
    if (root.isEmpty) continue;
    var dir = Directory(root);
    for (var i = 0; i < 8; i++) {
      for (final sub in const ['', 'bin/cache/']) {
        for (final name in names) {
          final dir2 = _join(dir.path, '${sub}artifacts/material_fonts');
          final f = File(_join(dir2, name));
          if (f.existsSync()) return f;
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  return null;
}

Future<void> _loadCjk() async {
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

String _join(String a, String b) =>
    '${a.replaceAll('\\', '/')}/${b.replaceAll('\\', '/')}';

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
