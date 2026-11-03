import 'package:cloudtune/models/models.dart';

/// 测试专用数据（**只在 test/ 里用，不参与打包**）。
///
/// 正式版的曲库必须来自真实导入，所以这些示例曲目只用来跑单元测试，
/// 不会被写进数据库、也不会出现在任何界面上。
class Fixtures {
  static const albums = <String, Album>{
    'xbh': Album(id: 'xbh', name: '学不会', year: 2011, coverStyle: 0),
    'ynz': Album(id: 'ynz', name: '因你而在', year: 2013, coverStyle: 1),
    'xdq': Album(id: 'xdq', name: '新地球', year: 2014, coverStyle: 2),
    'ts': Album(id: 'ts', name: '她说', year: 2010, coverStyle: 3),
    'hzjd': Album(id: 'hzjd', name: '和自己对话', year: 2015, coverStyle: 4),
    'wddmx': Album(id: 'wddmx', name: '伟大的渺小', year: 2017, coverStyle: 5),
    'jjlu': Album(id: 'jjlu', name: 'JJ陆', year: 2008, coverStyle: 6),
    'cc': Album(id: 'cc', name: '曹操', year: 2006, coverStyle: 1),
  };

  static Album albumOf(String id) =>
      albums[id] ?? Album(id: id, name: '未知专辑', year: 0, coverStyle: 1);

  static List<Track> seedTracks() {
    const seed = <List<Object>>[
      // [title, albumId, seconds, format, quality, hiRes, hasTags]
      ['不存在的情人', 'xbh', 246, MusicFormat.flac, '24bit/96kHz', true, true],
      ['学不会', 'xbh', 262, MusicFormat.flac, '16bit/44.1kHz', false, true],
      ['那些你很冒险的梦', 'xbh', 253, MusicFormat.ape, '无损', false, true],
      ['她说', 'ts', 320, MusicFormat.flac, '16bit/44.1kHz', false, false],
      ['修炼爱情', 'ynz', 275, MusicFormat.flac, '24bit/96kHz', true, true],
      ['可惜没如果', 'xdq', 288, MusicFormat.m4a, 'ALAC 无损', false, true],
      ['不为谁而作的歌', 'hzjd', 284, MusicFormat.flac, '24bit/96kHz', true, false],
      ['江南', 'jjlu', 271, MusicFormat.mp3, '320kbps', false, true],
      ['曹操', 'cc', 236, MusicFormat.wav, 'PCM 16bit/44.1kHz', false, true],
      ['一千年以后', 'cc', 263, MusicFormat.mp3, '320kbps', false, false],
      ['伟大的渺小', 'wddmx', 280, MusicFormat.dsf, 'DSD64', true, true],
      ['醉赤壁', 'jjlu', 255, MusicFormat.ogg, 'Vorbis q10', false, true],
      ['我还想她', 'ts', 263, MusicFormat.aac, '256kbps', false, false],
      ['Love U U', 'xbh', 240, MusicFormat.flac, '16bit/44.1kHz', false, true],
    ];

    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (var i = 0; i < seed.length; i++)
        buildSeed(
          title: seed[i][0] as String,
          albumId: seed[i][1] as String,
          seconds: seed[i][2] as int,
          format: seed[i][3] as MusicFormat,
          quality: seed[i][4] as String,
          hiRes: seed[i][5] as bool,
          hasTags: seed[i][6] as bool,
          index: i,
          addedAt: now,
        ),
    ];
  }

  static Track buildSeed({
    required String title,
    required String albumId,
    required int seconds,
    required MusicFormat format,
    required String quality,
    required bool hiRes,
    required bool hasTags,
    required int index,
    required int addedAt,
  }) {
    final album = albumOf(albumId);
    final path = '音乐/测试歌手/${album.name}/$title.${format.extensions.first}';
    return Track(
      id: Track.idOf('webdav', path),
      title: title,
      albumId: albumId,
      albumName: album.name,
      artist: '测试歌手',
      year: album.year,
      duration: Duration(seconds: seconds),
      format: format,
      quality: quality,
      hiRes: hiRes,
      hasTags: hasTags,
      sourceId: 'webdav',
      path: path,
      sizeBytes: seconds * 40000,
      addedAt: addedAt + index,
    );
  }

  static const lyrics = <LyricLine>[
    LyricLine(Duration(seconds: 0), '他们都说爱有回响'),
    LyricLine(Duration(seconds: 17), '我的回声落在空房间'),
    LyricLine(Duration(seconds: 36), '我在人群里练习想你'),
    LyricLine(Duration(seconds: 58), '像一个不存在的情人'),
    LyricLine(Duration(seconds: 82), '名字写进空白的信'),
    LyricLine(Duration(seconds: 106), '寄给一个不会来的人'),
    LyricLine(Duration(seconds: 130), '我数着你留下的话'),
    LyricLine(Duration(seconds: 154), '每一句都没有落点'),
    LyricLine(Duration(seconds: 178), '像一个不存在的情人'),
    LyricLine(Duration(seconds: 204), '只剩我一个人的房间'),
    LyricLine(Duration(seconds: 228), '雨停之前 别急着说再见'),
  ];
}
