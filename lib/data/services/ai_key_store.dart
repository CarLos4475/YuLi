import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the DeepSeek API key in OS-secure storage (Keychain / encrypted
/// SharedPreferences). The key NEVER leaves the device, is NEVER logged, and is
/// NEVER written anywhere that touches git. The UI only ever asks "is a key
/// set?" — it does not read the value back for display.
class AiKeyStore {
  static const _key = 'deepseek_api_key_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String value) =>
      _storage.write(key: _key, value: value.trim());

  Future<void> clear() => _storage.delete(key: _key);

  Future<bool> hasKey() async => ((await read())?.trim().isNotEmpty) ?? false;
}
