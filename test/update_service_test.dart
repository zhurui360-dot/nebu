import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cloudtune/services/update_service.dart';
import 'package:cloudtune/app_meta.dart';

/// 本地起一个真实 HTTP 服务来测 UpdateService.check 的各条分支，
/// 不打真实网络。
void main() {
  late HttpServer server;
  late String baseUrl;

  /// 下一批响应（每次请求消费一份）
  String responseBody = '';
  int statusCode = 200;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}/version.json';
    server.listen((req) async {
      req.response.statusCode = statusCode;
      req.response.headers.contentType = ContentType.json;
      req.response.write(responseBody);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  void serve(Map<String, Object?> json, {int code = 200}) {
    responseBody = jsonEncode(json);
    statusCode = code;
  }

  test('远端 versionCode 更大 → 返回 UpdateResult', () async {
    serve({
      'version': '0.0.39',
      'versionCode': 39,
      'url': 'http://x/a.apk',
      'size': 1024,
      'notes': ['a', 'b'],
    });
    final r = await UpdateService.check(baseUrl, currentVersionCode: 38);
    expect(r, isNotNull);
    expect(r!.version, '0.0.39');
    expect(r.downloadUrl, 'http://x/a.apk');
    expect(r.notes, ['a', 'b']);
  });

  test('versionCode 相同 → 返回 null（已是最新）', () async {
    serve({'version': '0.0.38', 'versionCode': 38, 'url': 'http://x/a.apk'});
    final r = await UpdateService.check(baseUrl, currentVersionCode: 38);
    expect(r, isNull);
  });

  test('HTTP 非 200 → 抛异常（silent 模式靠它静默吞掉）', () async {
    serve({'version': '0.0.39', 'versionCode': 39}, code: 500);
    expect(
      () => UpdateService.check(baseUrl, currentVersionCode: 38),
      throwsA(isA<UpdateException>()),
    );
  });

  test('返回非法 JSON → 抛异常而不是崩溃', () async {
    responseBody = '<html>not json</html>';
    statusCode = 200;
    expect(
      () => UpdateService.check(baseUrl, currentVersionCode: 38),
      throwsA(isA<UpdateException>()),
    );
  });

  test('地址无效（无 scheme）→ 抛异常', () {
    expect(
      () => UpdateService.check('not a url', currentVersionCode: 38),
      throwsA(isA<UpdateException>()),
    );
  });

  test('缺 version 字段 → 抛异常', () async {
    serve({'versionCode': 39, 'url': 'http://x/a.apk'});
    expect(
      () => UpdateService.check(baseUrl, currentVersionCode: 38),
      throwsA(isA<UpdateException>()),
    );
  });

  test('连接不存在的端口 → 抛异常（网络失败分支）', () {
    // 先占一个端口再关掉，拿到一个必然连不上的端口号
    expect(
      () => UpdateService.check(
        'http://127.0.0.1:1/version.json',
        currentVersionCode: 38,
      ),
      throwsA(isA<UpdateException>()),
    );
  });

  test('versionCode 规则与 AppMeta 一致（0.0.XX → XX）', () {
    expect(AppMeta.versionCode, int.parse(AppMeta.version.split('.')[2]));
  });
}
