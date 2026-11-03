import 'package:cloudtune/data/repository.dart';
import 'package:cloudtune/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：v0.0.001 的「我的音乐 → 扫描」按钮把已经是百分数的 progress 又乘了 100，
/// 扫到 39% 就显示 3900%。进度必须始终落在 0–100。
void main() {
  setUp(() {
    // AppState 构造只碰 SharedPreferences，测试环境用 mock
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('scanProgress 永远是 0–100', () {
    final app = AppState(LibraryRepository());

    app.importJob = ImportJob(progress: 39);
    expect(app.scanProgress, closeTo(39, 0.001));
    expect(app.scanProgress.round().toString(), '39');

    // 脏数据也不能溢出
    app.importJob = ImportJob(progress: 3900);
    expect(app.scanProgress, 100);

    app.importJob = ImportJob(progress: -5);
    expect(app.scanProgress, 0);

    // 本地扫描：内部是 0–1，对外统一成 0–100
    app.importJob = null;
    app.localScanning = true;
    app.localProgress = 0.42;
    expect(app.scanProgress, closeTo(42, 0.001));

    app.localProgress = 1.0;
    expect(app.scanProgress, closeTo(100, 0.001));
  });

  test('isScanning 同时覆盖本地扫描与网盘导入', () {
    final app = AppState(LibraryRepository());
    expect(app.isScanning, isFalse);

    app.localScanning = true;
    expect(app.isScanning, isTrue);

    app.localScanning = false;
    app.importJob = ImportJob();
    app.importJob!.step = 3; // 结束态
    expect(app.isScanning, isFalse);
  });
}
