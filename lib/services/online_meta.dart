import 'dart:convert';

import 'tags/lrc_parser.dart';

import 'package:http/http.dart' as http;

/// 一个在线元数据源（歌词 或 封面）
class MetaSource {
  const MetaSource({
    required this.id,
    required this.name,
    required this.kind, // 'lyric' | 'cover'
    required this.endpoint,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final String kind;
  final String endpoint;
  final bool builtIn;

  bool get isLyric => kind == 'lyric';

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'endpoint': endpoint,
        'builtIn': builtIn,
      };

  static MetaSource fromJson(Map<String, Object?> m) => MetaSource(
        id: '${m['id']}',
        name: '${m['name']}',
        kind: '${m['kind']}',
        endpoint: '${m['endpoint']}',
        builtIn: m['builtIn'] == true,
      );
}

/// 在线补全：歌词走 LRCLIB（免费公开、无需密钥），
/// 封面/曲目信息走 iTunes Search API（免费公开、无需密钥）。
///
/// 也可以自己加源：歌词源只要是「LRCLIB 兼容」的 get 接口，
/// 封面源只要是「iTunes Search 兼容」的 search 接口即可。
class OnlineMeta {
  static const builtIn = <MetaSource>[
    MetaSource(
      id: 'lrclib',
      name: 'LRCLIB 公开歌词库',
      kind: 'lyric',
      endpoint: 'https://lrclib.net/api',
      builtIn: true,
    ),
    MetaSource(
      id: 'itunes-cover',
      name: 'iTunes 封面库',
      kind: 'cover',
      endpoint: 'https://itunes.apple.com/search',
      builtIn: true,
    ),
  ];

  static const _ua = {'User-Agent': 'CloudTune/0.0.05 (music player)'};

  /// 自定义源可以直接写 URL 模板，接口里带上 {title} / {artist} / {album} / {duration}
  /// 就会被替换成实际值，例如：
  ///   https://api.example.com/lyric?q={artist} {title}
  /// 返回值仍然按内置源的格式解析（歌词取 syncedLyrics/plainLyrics 或纯 LRC，
  /// 封面取 results[].artworkUrl100）。
  static bool isTemplate(String endpoint) =>
      endpoint.contains('{') && endpoint.contains('}');

  static Uri templateUri(
    String tpl, {
    required String title,
    required String artist,
    String? album,
    int durationSec = 0,
  }) {
    var out = tpl
        .replaceAll('{title}', Uri.encodeQueryComponent(title))
        .replaceAll('{artist}', Uri.encodeQueryComponent(artist))
        .replaceAll('{album}', Uri.encodeQueryComponent(album ?? ''))
        .replaceAll('{duration}', '$durationSec')
        .replaceAll('{title_raw}', title)
        .replaceAll('{artist_raw}', artist);
    if (!out.startsWith('http')) out = 'https://$out';
    return Uri.parse(out);
  }

  /// 取歌词（返回 LRC 文本），失败返回 null
  static Future<String?> fetchLyric(
    MetaSource src, {
    required String title,
    required String artist,
    String? album,
    int durationSec = 0,
  }) async {
    try {
      final base = src.endpoint.replaceAll(RegExp(r'/+$'), '');
      final custom = isTemplate(src.endpoint);
      // 模板源：直接把参数替换进 URL；内置源走 LRCLIB 的精确匹配接口
      final uri = custom
          ? templateUri(src.endpoint,
              title: title, artist: artist, album: album, durationSec: durationSec)
          : Uri.parse(base).replace(queryParameters: {
              'track_name': title,
              'artist_name': artist,
              if (album != null && album.isNotEmpty) 'album_name': album,
              if (durationSec > 0) 'duration': '$durationSec',
            });

      final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 12));
      if (res.statusCode == 404) {
        return custom ? null : await _searchLyric(src, title, artist);
      }
      if (res.statusCode != 200) return null;

      final body = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (!body.trimLeft().startsWith('{') && !body.trimLeft().startsWith('[')) {
        // 有的源直接返回纯文本 LRC
        return body.contains('[') ? body : null;
      }

      final json = jsonDecode(body);
      if (json is List) {
        if (json.isEmpty) return null;
        final first = json.first as Map<String, dynamic>;
        return _lyricText(first);
      }
      if (json is Map<String, dynamic>) return _lyricText(json);
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _searchLyric(MetaSource src, String title, String artist) async {
    try {
      final base = src.endpoint.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse(base).replace(queryParameters: {
        'track_name': title,
        'artist_name': artist,
      });
      final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (json is List && json.isNotEmpty) {
        return _lyricText((json.first as Map).cast<String, dynamic>());
      }
    } catch (_) {}
    return null;
  }

  static String? _lyricText(Map<String, dynamic> m) {
    final synced = (m['syncedLyrics'] as String?)?.trim();
    if (synced != null && synced.isNotEmpty && synced.contains('[')) return synced;
    final plain = (m['plainLyrics'] as String?)?.trim();
    if (plain != null && plain.isNotEmpty) {
      final lrc = LrcParser.toLrc(plain);
      return lrc.isEmpty ? null : lrc;
    }
    return null;
  }

  /// 取封面（返回图片字节），失败返回 null
  static Future<List<int>?> fetchCover(
    MetaSource src, {
    required String title,
    required String artist,
  }) async {
    try {
      final uri = isTemplate(src.endpoint)
          ? templateUri(src.endpoint, title: title, artist: artist)
          : Uri.parse(src.endpoint).replace(queryParameters: {
              'term': '$artist $title',
              'entity': 'song',
              'limit': '5',
            });
      final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;

      final json = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (json is! Map<String, dynamic>) return null;
      final results = (json['results'] as List?) ?? const [];
      if (results.isEmpty) return null;

      // 优先挑标题/歌手都对得上的那条
      Map<String, dynamic>? pick;
      for (final r in results) {
        final m = (r as Map).cast<String, dynamic>();
        final t = '${m['trackName'] ?? m['collectionName'] ?? ''}'.toLowerCase();
        final a = '${m['artistName'] ?? ''}'.toLowerCase();
        if (t.contains(title.toLowerCase()) || a.contains(artist.toLowerCase())) {
          pick = m;
          break;
        }
      }
      pick ??= (results.first as Map).cast<String, dynamic>();

      final art = '${pick['artworkUrl100'] ?? pick['artworkUrl60'] ?? ''}';
      if (art.isEmpty) return null;
      // 100x100 → 600x600
      final big = art.replaceAll(RegExp(r'\d+x\d+bb?'), '600x600bb');
      final img = await http.get(Uri.parse(big), headers: _ua).timeout(const Duration(seconds: 15));
      if (img.statusCode != 200 || img.bodyBytes.length < 200) return null;
      return img.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// 联网修正曲目信息：用文件名猜出来的 title/artist 去搜，
  /// 标题一致 + （歌手对上 或 时长接近）才敢返回，避免张冠李戴。
  /// 没有足够把握返回 null（保持文件名展示）。
  static Future<TrackMatch?> fetchTrackMatch({
    required String title,
    String artist = '',
    int durationMs = 0,
  }) async {
    try {
      final term = artist.trim().isEmpty ? title : '$artist $title';
      final uri = Uri.parse('https://itunes.apple.com/search').replace(queryParameters: {
        'term': term,
        'entity': 'song',
        'limit': '8',
      });
      final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (json is! Map<String, dynamic>) return null;
      final results = (json['results'] as List?) ?? const [];

      final nTitle = norm(title);
      final nArtist = norm(artist);
      if (nTitle.isEmpty) return null;

      Map<String, dynamic>? best;
      var bestScore = 0;
      for (final r in results) {
        final m = (r as Map).cast<String, dynamic>();
        final cTitle = norm('${m['trackName'] ?? ''}');
        final cArtist = norm('${m['artistName'] ?? ''}');
        if (cTitle.isEmpty) continue;

        var score = 0;
        // 标题：完全一致最强，互相包含次之
        if (cTitle == nTitle) {
          score += 5;
        } else if (nTitle.length >= 2 &&
            (cTitle.contains(nTitle) || nTitle.contains(cTitle))) {
          score += 3;
        }
        // 歌手线索：对上加分；对不上不硬扣（文件名猜的歌手经常不准）
        if (nArtist.isNotEmpty) {
          if (cArtist == nArtist) {
            score += 3;
          } else if (cArtist.contains(nArtist) || nArtist.contains(cArtist)) {
            score += 2;
          }
        }
        // 时长：接近是强佐证；差太远明显不是同一首
        final cDur = (m['trackTimeMillis'] as num?)?.toInt() ?? 0;
        if (durationMs > 0 && cDur > 0) {
          final diff = (cDur - durationMs).abs();
          if (diff <= 8000) {
            score += 4;
          } else if (diff <= 25000) {
            score += 1;
          } else {
            score -= 3;
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = m;
        }
      }

      // 至少要「标题一致(5) + 一条佐证(歌手或时长)」才返回
      if (best == null || bestScore < 6) return null;

      final album = '${best['collectionName'] ?? ''}'.trim();
      final date = '${best['releaseDate'] ?? ''}';
      return TrackMatch(
        title: '${best['trackName'] ?? ''}'.trim(),
        artist: '${best['artistName'] ?? ''}'.trim(),
        album: album.isEmpty ? null : album,
        year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 归一化用于比对：小写、去括号注记、去空白与标点（保留中英数字）
  static String norm(String s) {
    var t = s.toLowerCase().trim();
    // 括号注记整个去掉（兼容中英文括号混用，如 "(伴奏）"）
    t = t.replaceAll(RegExp(r'[\(（][^)）]*[\)）]'), '');
    t = t.replaceAll(RegExp(r'\[.*?\]|【.*?】'), '');
    t = t.replaceAll(RegExp(r'[^\w\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]'), '');
    return t;
  }
}

/// 联网查到的曲目信息（用来修正「标签缺失、只有文件名」的歌）
class TrackMatch {
  const TrackMatch({
    required this.title,
    required this.artist,
    this.album,
    this.year,
  });

  final String title;
  final String artist;
  final String? album;
  final int? year;
}
