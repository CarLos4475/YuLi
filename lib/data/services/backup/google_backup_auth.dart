import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'backup_bundle.dart';

class GoogleBackupAuth {
  static const projectId = 'yuli-507723';
  static const serverClientId =
      '987248826398-ge206kj8r564q6md9cvlkqic6n0cqkj1.apps.googleusercontent.com';
  static const scopes = ['https://www.googleapis.com/auth/drive.file'];
  static const _backgroundTokenPrefix = 'study_drive_token_v1_';
  static const _secureStorage = FlutterSecureStorage();
  Future<void>? _initializing;
  GoogleSignInAccount? account;

  Future<void> initialize() {
    if (!Platform.isAndroid) {
      throw const BackupFailure(
        'Conecta Google Drive desde tu tablet Android.',
      );
    }
    return _initializing ??= GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
    );
  }

  Future<void> connect() async {
    await initialize();
    account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    await account!.authorizationClient.authorizeScopes(scopes);
  }

  Future<void> reconnectSilently() async {
    await initialize();
    account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
  }

  Future<Map<String, String>> headers() async {
    final headers = await account?.authorizationClient.authorizationHeaders(
      scopes,
    );
    if (headers == null) {
      throw const BackupFailure('Conecta Google Drive y autoriza el respaldo.');
    }
    return headers;
  }

  Future<void> cacheBackgroundAuthorization(String accountId) async {
    if (account?.id != accountId) {
      throw const BackupFailure('La cuenta de Google cambió.');
    }
    final values = await headers();
    final authorization =
        values.entries
            .where((entry) => entry.key.toLowerCase() == 'authorization')
            .map((entry) => entry.value)
            .firstOrNull;
    if (!_validAuthorization(authorization)) {
      throw const BackupFailure('Google no entregó una autorización válida.');
    }
    await _secureStorage.write(
      key: '$_backgroundTokenPrefix$accountId',
      value: jsonEncode({
        'authorization': authorization,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<Map<String, String>?> backgroundHeaders(
    String accountId,
  ) async {
    try {
      final encoded = await _secureStorage.read(
        key: '$_backgroundTokenPrefix$accountId',
      );
      if (encoded == null) return null;
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic>) return null;
      final authorization = data['authorization'];
      final savedAt = DateTime.tryParse('${data['savedAt']}');
      if (!_validAuthorization(authorization) ||
          savedAt == null ||
          DateTime.now().toUtc().difference(savedAt) >=
              const Duration(minutes: 50)) {
        await clearBackgroundAuthorization(accountId);
        return null;
      }
      return {'Authorization': authorization! as String};
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearBackgroundAuthorization(String accountId) =>
      _secureStorage.delete(key: '$_backgroundTokenPrefix$accountId');

  static bool _validAuthorization(Object? value) =>
      value is String &&
      value.length <= 4096 &&
      RegExp(r'^Bearer [A-Za-z0-9._~+\-/]+=*$').hasMatch(value);

  Future<void> disconnect() async {
    final accountId = account?.id;
    await initialize();
    await GoogleSignIn.instance.signOut();
    account = null;
    if (accountId != null) await clearBackgroundAuthorization(accountId);
  }
}
