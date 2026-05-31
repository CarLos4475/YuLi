import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MathpixKeyStore {
  static const _appIdKey = 'mathpix_app_id_v1';
  static const _appKeyKey = 'mathpix_app_key_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> readAppId() => _storage.read(key: _appIdKey);

  Future<String?> readAppKey() => _storage.read(key: _appKeyKey);

  Future<void> write({required String appId, required String appKey}) async {
    await _storage.write(key: _appIdKey, value: appId.trim());
    await _storage.write(key: _appKeyKey, value: appKey.trim());
  }

  Future<void> clear() async {
    await _storage.delete(key: _appIdKey);
    await _storage.delete(key: _appKeyKey);
  }

  Future<bool> hasKeys() async {
    final appId = (await readAppId())?.trim();
    final appKey = (await readAppKey())?.trim();
    return appId != null &&
        appId.isNotEmpty &&
        appKey != null &&
        appKey.isNotEmpty;
  }
}
