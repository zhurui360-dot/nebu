import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloudtune/data/repository.dart';

/// 启动静默检查的节流依赖 ct_last_update_check 时间戳，这里验证它的存取语义：
/// 首次安装 = 0（会检查），写入后能读回。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首次安装：没有记录 → loadLastUpdateCheck 返回 0（会触发检查）', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LibraryRepository();
    await repo.init();
    expect(repo.loadLastUpdateCheck(), 0);
  });

  test('写入后读回一致，节流判断可用', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LibraryRepository();
    await repo.init();
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.saveLastUpdateCheck(now);
    expect(repo.loadLastUpdateCheck(), now);

    // 模拟节流判断：6 小时内 → 跳过；超过 → 检查
    const intervalMs = 6 * 60 * 60 * 1000;
    final last = repo.loadLastUpdateCheck();
    expect(now - last < intervalMs, isTrue); // 刚检查过 → 节流跳过
    expect(now - (last - intervalMs - 1) < intervalMs, isFalse); // 超过 6h → 检查
  });

  test('repo 未 init 时读时间戳不崩溃（返回 0 兜底）', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = LibraryRepository();
    expect(repo.loadLastUpdateCheck(), 0);
  });
}
