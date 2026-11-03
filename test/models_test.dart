import 'fixtures.dart';
import 'package:cloudtune/data/source_catalog.dart';
import 'package:cloudtune/models/models.dart';
import 'package:cloudtune/utils/cover_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('曲库数据', () {
    test('空曲目只做 UI 占位，不冒充真实音乐', () {
      final t = Track.empty();
      expect(t.id, isEmpty);
      expect(t.duration, Duration.zero);
      expect(t.hasTags, isFalse);
    });

    test('封面兜底配色稳定且落在可用区间', () {
      final a = coverStyleOf('al-abc');
      expect(a, coverStyleOf('al-abc')); // 同一张专辑每次都一样
      expect(a, inInclusiveRange(1, 6));
      expect(coverStyleOf(''), inInclusiveRange(1, 6));
    });

    test('正式版只开放 WebDAV，来源清单里没有示例曲目', () {
      expect(SourceCatalog.sources.map((s) => s.id), ['webdav']);
      expect(SourceCatalog.sources.first.kind, SourceKind.webdav);
    });

    test('种子曲目 14 首，路径与 id 稳定', () {
      final tracks = Fixtures.seedTracks();
      expect(tracks.length, 14);
      for (final t in tracks) {
        expect(t.path, isNotNull);
        expect(t.id, Track.idOf(t.sourceId!, t.path!));
      }
    });

    test('种子曲目里保留了"缺标签"样本，用于验证补全流程', () {
      expect(Fixtures.seedTracks().where((t) => !t.hasTags), isNotEmpty);
    });

    test('copyWith 只改标签状态', () {
      final t = Fixtures.seedTracks().first;
      final fixed = t.copyWith(hasTags: true);
      expect(fixed.hasTags, isTrue);
      expect(fixed.id, t.id);
      expect(fixed.duration, t.duration);
    });
  });

  group('格式', () {
    test('每种格式都有扩展名与短名', () {
      for (final f in MusicFormat.values) {
        expect(f.extensions, isNotEmpty);
        expect(f.label.isNotEmpty, isTrue);
      }
    });

    test('无损判定', () {
      expect(MusicFormat.flac.lossless, isTrue);
      expect(MusicFormat.ape.lossless, isTrue);
      expect(MusicFormat.mp3.lossless, isFalse);
    });
  });

  group('歌词', () {
    test('时间戳递增', () {
      for (var i = 1; i < Fixtures.lyrics.length; i++) {
        expect(Fixtures.lyrics[i].time > Fixtures.lyrics[i - 1].time, isTrue);
      }
    });
  });
}
