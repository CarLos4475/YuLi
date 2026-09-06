import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import 'backup_bundle.dart';

class GoogleBackupAuth {
  static const projectId = 'yuli-507723';
  static const serverClientId =
      '987248826398-ge206kj8r564q6md9cvlkqic6n0cqkj1.apps.googleusercontent.com';
  static const scopes = ['https://www.googleapis.com/auth/drive.file'];
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

  Future<void> disconnect() async {
    await initialize();
    await GoogleSignIn.instance.signOut();
    account = null;
  }
}
