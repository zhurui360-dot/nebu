import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'cloud_provider.dart';

/// WebDAV 实现：群晖 / 坚果云 / Alist / NextCloud 都走这套。
///
/// 只用到两个动词：
///  - PROPFIND（列目录，Depth: 1）
///  - GET + Range（读文件头 256KB 解析标签）
class WebDavProvider implements CloudProvider {
  WebDavProvider({
    required this.sourceId,
    required this.baseUrl,
    required this.username,
    required this.password,
    this.displayName = 'WebDAV',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  final String sourceId;
  @override
  final String displayName;

  final String baseUrl;
  final String username;
  final String password;
  final http.Client _client;

  String get _auth => 'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final rel = path.startsWith('/') ? path.substring(1) : path;
    try {
      return Uri.parse(base).resolve(
        rel.split('/').map(Uri.encodeComponent).join('/'),
      );
    } on FormatException {
      throw CloudException('服务器地址格式不对，检查是否有多余字符');
    }
  }

  @override
  Future<List<CloudEntry>> list(String path) async {
    final req = http.Request('PROPFIND', _uri(path))
      ..headers.addAll({
        'Authorization': _auth,
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      })
      ..body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:resourcetype/>
    <d:getlastmodified/>
  </d:prop>
</d:propfind>''';

    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode == 401) {
      throw CloudException('账号或密码不正确', status: 401);
    }
    if (res.statusCode != 207 && res.statusCode != 200) {
      throw CloudException('列目录失败', status: res.statusCode);
    }

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(res.body);
    } catch (_) {
      throw CloudException('返回的内容不是 WebDAV 目录列表（状态码 ${res.statusCode}）');
    }
    final entries = <CloudEntry>[];

    for (final node in doc.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'response') continue;

      final href = _firstText(node, 'href');
      if (href == null) continue;

      // href 可能是绝对 URL，也可能以 / 开头，要按 baseUrl 的 path 前缀剥
      final rel = _toRelPath(href);
      if (rel == null) continue;

      // 跳过目录自身（两边都归一化后比较，去掉末尾 /）
      if (_normalize(rel) == _normalize(path)) continue;

      // 根目录本身没有名字可取
      final segs = rel.split('/').where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) continue;

      final isDir = node.descendants
          .whereType<XmlElement>()
          .any((e) => e.name.local == 'collection');

      final sizeText = _firstText(node, 'getcontentlength');
      final modText = _firstText(node, 'getlastmodified');

      entries.add(CloudEntry(
        path: rel,
        name: segs.last,
        isDir: isDir,
        size: int.tryParse(sizeText ?? '') ?? 0,
        modified: modText == null ? null : DateTime.tryParse(modText),
      ));
    }

    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return entries;
  }

  /// 尽可能解码，解不动就原样返回（绝不抛异常）
  static String _safeDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      // decodeComponent 遇到非法 % 会抛，退回原文
      return s;
    }
  }

  /// 去掉末尾斜杠，便于比较 `/a` 与 `/a/`
  static String _normalize(String s) {
    var t = s.trim();
    while (t.length > 1 && t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t.isEmpty ? '/' : t;
  }

  /// 把 PROPFIND 返回的 href 转成「相对 baseUrl 的路径」
  ///   <d:href>/dav/%E9%9F%B3%E4%B9%90/a.flac</d:href>  → /音乐/a.flac
  ///   <d:href>https://host/dav/b.flac</d:href>          → /b.flac
  String? _toRelPath(String href) {
    final raw = href.trim();
    if (raw.isEmpty) return null;

    // 服务器返回的 href 偶发非法 % 转义（中文名、特殊字符），
    // 解不出来就用原文，不能因为一个字符把整次列目录搞崩
    final decoded = _safeDecode(raw);

    // 取 path 部分（绝对 URL 时丢弃 scheme/host）
    var p = decoded;
    if (p.contains('://')) {
      final u = Uri.tryParse(p);
      if (u == null) return null;
      p = u.path;
    }
    if (!p.startsWith('/')) p = '/$p';

    // 剥掉 baseUrl 的路径前缀（如 /dav）
    String basePath;
    try {
      basePath = Uri.parse(baseUrl).path;
    } on FormatException {
      basePath = '';
    }
    if (basePath.endsWith('/') && basePath.length > 1) {
      basePath = basePath.substring(0, basePath.length - 1);
    }
    if (basePath.isNotEmpty && basePath != '/') {
      if (p == basePath) {
        p = '/';
      } else if (p.startsWith('$basePath/')) {
        p = p.substring(basePath.length);
      }
    }
    return _normalize(p);
  }

  String? _firstText(XmlElement node, String local) {
    for (final e in node.descendants.whereType<XmlElement>()) {
      if (e.name.local == local) {
        // 只取直接归属该 response 的，避免拿到嵌套结构
        return e.innerText;
      }
    }
    return null;
  }

  @override
  Future<Uint8List> fetchRange(String path, int start, int end) async {
    final res = await _client.get(_uri(path), headers: {
      'Authorization': _auth,
      'Range': 'bytes=$start-$end',
    });
    if (res.statusCode != 206 && res.statusCode != 200) {
      throw CloudException('读取文件失败', status: res.statusCode);
    }
    return res.bodyBytes;
  }

  @override
  Future<String> directUrl(String path) async => _uri(path).toString();

  @override
  Map<String, String> get playbackHeaders => {'Authorization': _auth};

  @override
  Future<void> close() async => _client.close();
}
