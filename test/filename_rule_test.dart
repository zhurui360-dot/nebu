import 'package:cloudtune/services/online_meta.dart';
import 'package:cloudtune/services/tags/track_guesser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => TrackGuesser.pattern = '');

  group('文件名识别：智能模式', () {
    test('歌手 - 歌名', () {
      TrackGuesser.pattern = '';
      final g = TrackGuesser.guess(
        fileName: '周杰伦 - 晴天.flac',
        path: '/音乐/周杰伦/叶惠美/周杰伦 - 晴天.flac',
      );
      expect(g.title, '晴天');
      expect(g.artist, '周杰伦');
    });

    test('开头序号会被去掉', () {
      TrackGuesser.pattern = '';
      final g = TrackGuesser.guess(
        fileName: '01. 周杰伦 - 晴天.flac',
        path: '/音乐/周杰伦/叶惠美/01. 周杰伦 - 晴天.flac',
      );
      expect(g.title, '晴天');
      expect(g.artist, '周杰伦');
    });
  });

  group('文件名识别：自定义模板', () {
    test('{artist} - {title}', () {
      TrackGuesser.pattern = '{artist} - {title}';
      final g = TrackGuesser.guess(
        fileName: '周杰伦 - 晴天.flac',
        path: '/下载/周杰伦 - 晴天.flac',
      );
      expect(g.artist, '周杰伦');
      expect(g.title, '晴天');
    });

    test('{title} - {artist} 反着写也能切对', () {
      TrackGuesser.pattern = '{title} - {artist}';
      final g = TrackGuesser.guess(
        fileName: '晴天 - 周杰伦.flac',
        path: '/下载/晴天 - 周杰伦.flac',
      );
      expect(g.title, '晴天');
      expect(g.artist, '周杰伦');
    });

    test('带序号和专辑的模板', () {
      TrackGuesser.pattern = '{track}. {artist} - {album} - {title}';
      final g = TrackGuesser.guess(
        fileName: '03. 陈一禾 - 冬 - 雪落下的声音.flac',
        path: '/音乐/03. 陈一禾 - 冬 - 雪落下的声音.flac',
      );
      expect(g.trackNo, 3);
      expect(g.artist, '陈一禾');
      expect(g.album, '冬');
      expect(g.title, '雪落下的声音');
    });

    test('分隔符宽松：下划线也能命中', () {
      TrackGuesser.pattern = '{artist} - {title}';
      final g = TrackGuesser.guess(
        fileName: '周杰伦_晴天.flac',
        path: '/下载/周杰伦_晴天.flac',
      );
      expect(g.artist, '周杰伦');
      expect(g.title, '晴天');
    });

    test('模板不匹配时退回智能识别，不会把歌名弄丢', () {
      TrackGuesser.pattern = '{artist} - {album} - {title}';
      final g = TrackGuesser.guess(
        fileName: '周杰伦 - 晴天.flac',
        path: '/音乐/周杰伦/叶惠美/周杰伦 - 晴天.flac',
      );
      expect(g.title, '晴天');
      expect(g.artist, '周杰伦');
    });

    test('预览用的是传入的模板，不影响全局设置', () {
      TrackGuesser.pattern = '';
      final g = TrackGuesser.previewWith('{title} - {artist}', '晴天 - 周杰伦.mp3');
      expect(g?.title, '晴天');
      expect(g?.artist, '周杰伦');
      expect(TrackGuesser.pattern, '');
    });
  });

  group('自定义源：URL 模板', () {
    test('占位符会被替换并编码', () {
      final uri = OnlineMeta.templateUri(
        'https://api.example.com/lyric?q={artist} {title}&d={duration}',
        title: '晴天',
        artist: '周杰伦',
        durationSec: 269,
      );
      expect(uri.host, 'api.example.com');
      expect(uri.queryParameters['d'], '269');
      expect(Uri.decodeFull(uri.query), contains('周杰伦'));
      expect(Uri.decodeFull(uri.query), contains('晴天'));
    });

    test('没写协议时补 https', () {
      final uri = OnlineMeta.templateUri('api.example.com/x?t={title}',
          title: 'A', artist: 'B');
      expect(uri.scheme, 'https');
    });

    test('只有花括号才算模板源', () {
      expect(OnlineMeta.isTemplate('https://lrclib.net/api'), isFalse);
      expect(OnlineMeta.isTemplate('https://x.com/?q={title}'), isTrue);
    });
  });
}
