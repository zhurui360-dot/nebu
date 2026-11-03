import 'package:cloudtune/services/tags/tag_reader.dart';
import 'package:cloudtune/services/tags/track_guesser.dart';
import 'package:flutter_test/flutter_test.dart';

/// 入库识别规则：用例都来自真实音乐库的命名习惯。
/// 目标是「标签缺失时，也能从文件名和目录把歌手/歌名认出来」。
void main() {
  TrackGuess g(String fileName, String path, {TagData? tag}) =>
      TrackGuesser.guess(fileName: fileName, path: path, tag: tag);

  group('基础：序号与格式标记', () {
    test('01. 歌手 - 歌名', () {
      final r = g('01. 周杰伦 - 晴天.flac', '/音乐/周杰伦/叶惠美/01. 周杰伦 - 晴天.flac');
      expect(r.title, '晴天');
      expect(r.artist, '周杰伦');
      expect(r.album, '叶惠美');
      expect(r.trackNo, 1);
    });

    test('[FLAC] 前缀与 [320K] 后缀', () {
      final r = g('[FLAC] 晴天 - 周杰伦[320K].flac', '/音乐/周杰伦/叶惠美/x.flac');
      expect(r.title, '晴天');
      expect(r.artist, '周杰伦');
    });

    test('只有序号时靠目录认歌手', () {
      final r = g('07 晴天.flac', '/音乐/周杰伦/叶惠美/07 晴天.flac');
      expect(r.title, '晴天');
      expect(r.trackNo, 7);
      expect(r.artist, '周杰伦');
      expect(r.album, '叶惠美');
    });

    test('(01) 序号 + 格式标记', () {
      final r = g('(01) [320K] 晴天.flac', '/音乐/周杰伦/叶惠美/x.flac');
      expect(r.trackNo, 1);
      expect(r.title, '晴天');
    });
  });

  group('歌名里的括号要保留', () {
    test('(Live) / (伴奏) / （钢琴版）', () {
      expect(g('晴天 (Live).flac', '/音乐/周杰伦/叶惠美/x.flac').title, '晴天 (Live)');
      expect(g('晴天 (伴奏).flac', '/音乐/周杰伦/叶惠美/x.flac').title, '晴天 (伴奏)');
      expect(g('晴天（钢琴版）.flac', '/音乐/周杰伦/叶惠美/x.flac').title, '晴天（钢琴版）');
    });
  });

  group('智能识别：多段 / 下划线 / 书名号 / 平台前后缀', () {
    test('歌手 - 专辑 - 序号 - 歌名', () {
      final r = g('周杰伦 - 叶惠美 - 01 - 晴天.mp3', '/音乐/周杰伦/叶惠美/x.mp3');
      expect(r.artist, '周杰伦');
      expect(r.album, '叶惠美');
      expect(r.title, '晴天');
    });

    test('平台前缀：网易云音乐 - 歌名 - 歌手', () {
      final r = g('网易云音乐 - 晴天 - 周杰伦.mp3', '/音乐/周杰伦/x.mp3');
      expect(r.title, '晴天');
      expect(r.artist, '周杰伦');
    });

    test('平台后缀：歌名 - 歌手 - 酷狗音乐', () {
      final r = g('晴天 - 周杰伦 - 酷狗音乐.mp3', '/音乐/周杰伦/x.mp3');
      expect(r.title, '晴天');
      expect(r.artist, '周杰伦');
    });

    test('下划线分隔', () {
      final r = g('周杰伦_晴天.mp3', '/音乐/周杰伦/x.mp3');
      expect(r.artist, '周杰伦');
      expect(r.title, '晴天');
    });

    test('无空格连字符', () {
      final r = g('周杰伦-晴天.flac', '/音乐/周杰伦/叶惠美/x.flac');
      expect(r.artist, '周杰伦');
      expect(r.title, '晴天');
    });

    test('书名号里是专辑名', () {
      final r = g('周杰伦《叶惠美》晴天.mp3', '/音乐/周杰伦/叶惠美/x.mp3');
      expect(r.artist, '周杰伦');
      expect(r.album, '叶惠美');
      expect(r.title, '晴天');
    });

    test('歌手尾巴上的 (Live版) 要去掉', () {
      final r = g('晴天 - 周杰伦 (Live版).mp3', '/音乐/周杰伦/叶惠美/x.mp3');
      expect(r.artist, '周杰伦');
      expect(r.title, '晴天');
    });

    test('英文歌名里的连字符不能被拆', () {
      final r = g('周杰伦 - B-Side.mp3', '/音乐/周杰伦/x.mp3');
      expect(r.artist, '周杰伦');
      expect(r.title, 'B-Side');
    });
  });

  group('标签优先', () {
    test('内嵌标签覆盖文件名推断', () {
      final tag = TagData()
        ..title = '真正的歌名'
        ..artist = '真正的歌手'
        ..album = '真正的专辑';
      final r = g('01. 错的 - 也错.flac', '/音乐/x/y/01. 错的 - 也错.flac', tag: tag);
      expect(r.title, '真正的歌名');
      expect(r.artist, '真正的歌手');
      expect(r.album, '真正的专辑');
    });

    test('标签不全时用文件名补齐', () {
      final tag = TagData()..title = '晴天';
      final r = g('周杰伦 - 晴天.flac', '/音乐/周杰伦/x.flac', tag: tag);
      expect(r.title, '晴天');
      expect(r.artist, '周杰伦');
    });
  });

  group('兜底', () {
    test('目录名是噪声时不当年专辑', () {
      final r = g('晴天.flac', '/音乐/未分类/晴天.flac');
      expect(r.title, '晴天');
      expect(r.album, isNot('未分类'));
    });

    test('根目录下没有目录信息', () {
      final r = g('晴天.flac', '/晴天.flac');
      expect(r.title, '晴天');
      expect(r.artist, isNull);
    });
  });
}
