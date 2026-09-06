import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../domain/services/pending_saves.dart';
import 'backup_bundle.dart';
import 'drive_backup_client.dart';
import 'google_backup_auth.dart';
import 'local_backup_service.dart';

class BackupManager extends ChangeNotifier {
  final LocalBackupService local;
  final GoogleBackupAuth auth;
  final http.Client _http;
  late final DriveBackupClient drive = DriveBackupClient(_http, auth.headers);
  bool busy = false;
  bool restorePending = false;
  String status = '';
  String? error;
  List<DriveBackup> backups = [];
  BackupManager(this.local, this.auth, this._http);

  String? get email => auth.account?.email;
  bool get automatic =>
      auth.account != null &&
      local.preferences.getString('backup_auto_account_v1') == auth.account!.id;
  String get _successKey =>
      'backup_last_success_v1_${auth.account?.id ?? local.preferences.getString('backup_auto_account_v1') ?? 'disconnected'}';
  String? get lastSuccess => local.preferences.getString(_successKey);

  Future<T> _run<T>(String label, Future<T> Function() operation) async {
    if (busy || restorePending) {
      throw const BackupFailure('Hay otra operación pendiente.');
    }
    busy = true;
    status = label;
    error = null;
    notifyListeners();
    try {
      return await operation();
    } catch (e) {
      error =
          e is BackupFailure
              ? e.message
              : e is GoogleSignInException
              ? 'Google no completó la conexión (${e.code.name}). Revisa el cliente Android, la huella SHA-1 y los usuarios de prueba.'
              : 'No se pudo completar la operación. Revisa la conexión, el espacio libre y la configuración de Google.';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> connect() => _run('Conectando Google Drive', () async {
    await auth.connect();
    backups = await drive.list();
  });

  Future<void> refresh() => _run('Buscando respaldos', () async {
    await auth.reconnectSilently();
    if (auth.account != null) backups = await drive.list();
  });

  Future<void> disconnect() => _run('Desconectando Google Drive', () async {
    await setAutomatic(false);
    await auth.disconnect();
    backups = [];
  });

  Future<void> setAutomatic(bool enabled) async {
    final bool saved;
    if (enabled) {
      if (auth.account == null) {
        throw const BackupFailure('Conecta tu cuenta primero.');
      }
      saved = await local.preferences.setString(
        'backup_auto_account_v1',
        auth.account!.id,
      );
    } else {
      saved = await local.preferences.remove('backup_auto_account_v1');
    }
    if (!saved) {
      throw const BackupFailure(
        'No se pudo guardar la preferencia de respaldo.',
      );
    }
    notifyListeners();
  }

  Future<File> exportLocal() => _run('Preparando respaldo', () async {
    await PendingSaves.flush();
    return local.create();
  });

  Future<void> uploadStudy(File file) =>
      _run('Guardando apunte en Drive', () async {
        await auth.reconnectSilently();
        await auth.headers();
        await drive.upload(file, await local.deviceId(), study: true);
        status = 'Apunte guardado en YuLi — Apuntes';
      });

  Future<void> backupNow() => _run('Preparando respaldo', () async {
    await auth.headers();
    await PendingSaves.flush();
    final file = await local.create();
    try {
      final manifest = await BackupBundle.inspect(file);
      final counts = manifest['counts'] as Map;
      if ([
        'notes',
        'tasks',
        'lab_spaces',
        'folders',
      ].every((k) => counts[k] == 0)) {
        throw const BackupFailure(
          'Esta instalación está vacía. Puedes restaurar un respaldo existente.',
        );
      }
      status = 'Subiendo respaldo';
      notifyListeners();
      final uploaded = await drive.upload(
        file,
        await local.deviceId(),
        progress: (value) {
          status = 'Subiendo respaldo ${(value * 100).round()} %';
          notifyListeners();
        },
      );
      backups = [uploaded, ...backups];
      await local.preferences.setString(
        _successKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      status = 'Respaldo verificado en Google Drive';
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Transport cleanup must not mask the upload result.
      }
    }
  });

  Future<Directory> prepareLocal(File file) =>
      _run('Verificando respaldo', () => local.prepareRestore(file));

  Future<Directory> prepareDrive(DriveBackup backup) =>
      _run('Descargando y verificando respaldo', () async {
        final root = Directory(p.join(local.documents.path, 'backups'));
        await root.create(recursive: true);
        final file = File(
          p.join(root.path, 'download_${const Uuid().v4()}.yuli'),
        );
        try {
          await drive.download(backup, file);
          return await local.prepareRestore(file);
        } finally {
          if (await file.exists()) await file.delete();
        }
      });

  Future<void> restore(Directory stage) => _run(
    'Preparando restauración',
    () async {
      await PendingSaves.flush();
      await local.scheduleRestore(stage);
      restorePending = true;
      status =
          'Respaldo preparado. Cierra YuLi y vuelve a abrirla para restaurar.';
    },
  );

  Future<void> automaticIfDue({bool Function()? canRun}) async {
    if (!Platform.isAndroid ||
        busy ||
        restorePending ||
        local.preferences.getString('backup_auto_account_v1') == null) {
      return;
    }
    final last = DateTime.tryParse(lastSuccess ?? '');
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 24)) {
      return;
    }
    try {
      await auth.reconnectSilently();
      if (automatic && (canRun?.call() ?? true)) await backupNow();
    } catch (_) {
      error ??=
          'No se pudo respaldar automáticamente. Abre Respaldos y revisa la conexión con Google Drive.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
