import 'package:cloudtune/services/online_meta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('联网修正：名称归一化', () {
    test('去掉括号注记、空白与标点，保留中英数字', () {
      expect(OnlineMeta.norm('晴天 (Live)'), '晴天'); // Live 版和原曲名能配上
      expect(OnlineMeta.norm('Love U U (伴奏）'), 'loveuu');
      expect(OnlineMeta.norm('不为谁而作的歌 [Official MV]'), '不为谁而作的歌');
      expect(OnlineMeta.norm('Twilight - 320k'), 'twilight320k');
    });

    test('大小写与空格不影响一致性', () {
      expect(OnlineMeta.norm('Rise Without A Sound'),
          OnlineMeta.norm('rise  without a  sound'));
    });
  });
}
