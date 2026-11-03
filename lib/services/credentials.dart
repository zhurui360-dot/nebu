import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 网盘凭证：存系统钥匙串（Android Keystore / iOS Keychain），不落明文。
/// 服务器地址与账号不是秘密，放数据库；密码只在这里。
class Credentials {
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String _key(String sourceId, String field) => 'ct_${sourceId}_$field';

  static Future<void> savePassword(String sourceId, String password) =>
      _store.write(key: _key(sourceId, 'password'), value: password);

  static Future<String?> readPassword(String sourceId) =>
      _store.read(key: _key(sourceId, 'password'));

  static Future<void> saveToken(String sourceId, String token) =>
      _store.write(key: _key(sourceId, 'token'), value: token);

  static Future<String?> readToken(String sourceId) =>
      _store.read(key: _key(sourceId, 'token'));

  static Future<void> clear(String sourceId) async {
    await _store.delete(key: _key(sourceId, 'password'));
    await _store.delete(key: _key(sourceId, 'token'));
  }
}
