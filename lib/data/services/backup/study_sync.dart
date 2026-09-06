import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'backup_bundle.dart';
import 'drive_backup_client.dart';

class StudyItem {
  final String key, folderKey, folderName, name, hash;
  final Future<File> Function() render;
  StudyItem({
    required this.key,
    required this.folderKey,
    required this.folderName,
    required this.name,
    required this.hash,
    required this.render,
  });
}

class StudySyncInterrupted implements Exception {}

class StudySync {
  final SharedPreferences prefs;
  final DriveBackupClient drive;
  final String account;
  StudySync(this.prefs, this.drive, this.account);

  Future<void> _save(String key, String value) async {
    if (!await prefs.setString(key, value)) {
      throw const BackupFailure('No se pudo guardar el progreso de los PDF.');
    }
  }

  Future<void> run(
    Stream<StudyItem> items,
    bool Function() canContinue,
    void Function(String) status,
  ) async {
    void check() {
      if (!canContinue()) throw StudySyncInterrupted();
    }

    var library = prefs.getString('study_library_id_v1');
    if (library == null) {
      library = const Uuid().v4();
      await _save('study_library_id_v1', library);
    }
    if (!RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(library)) {
      throw const BackupFailure('Identidad de biblioteca inválida.');
    }
    final indexKey = 'study_index_v1_${account}_$library';
    final ids = Map<String, dynamic>.from(
      jsonDecode(prefs.getString(indexKey) ?? '{}') as Map,
    );
    check();
    final remote = <String, Map<String, dynamic>>{};
    for (final file in await drive.studyFiles(library)) {
      final key = (file['appProperties'] as Map?)?['studyKey'] as String?;
      if (key != null) remote.putIfAbsent(key, () => file);
    }
    Future<({String id, Map<String, dynamic>? file})> identity(
      String key,
    ) async {
      check();
      var file = remote[key];
      var id = file?['id'] as String? ?? ids[key] as String?;
      if (file == null && id != null) {
        file = await drive.studyFile(id);
        if (file != null) {
          final properties = file['appProperties'] as Map?;
          if (properties?['library'] != library ||
              properties?['studyKey'] != key) {
            throw const BackupFailure(
              'El archivo de Drive no pertenece a esta biblioteca.',
            );
          }
          if (file['trashed'] == true) {
            file = null;
            id = null;
          }
        }
      }
      id ??= await drive.reserveId();
      ids[key] = id;
      await _save(indexKey, jsonEncode(ids));
      return (id: id, file: file);
    }

    Future<String> folder(String key, String name, String? parent) async {
      final existing = await identity(key);
      check();
      if (existing.file == null) {
        await drive.createStudyFolder(existing.id, name, library!, key, parent);
      } else {
        await drive.moveStudyFile(existing.file!, name, parent);
      }
      return existing.id;
    }

    final root = await folder('root', 'Respaldo', null);
    final folders = <String, String>{};
    var failedRenders = false;
    await for (final item in items) {
      check();
      final parent =
          folders[item.folderKey] ??= await folder(
            item.folderKey,
            item.folderName,
            root,
          );
      final existing = await identity(item.key);
      final properties = existing.file?['appProperties'] as Map?;
      if (existing.file != null) {
        await drive.moveStudyFile(existing.file!, item.name, parent);
      }
      if (properties?['hash'] == item.hash &&
          properties?['state'] == 'complete') {
        continue;
      }
      check();
      status('Actualizando ${item.name}');
      final File file;
      try {
        file = await item.render();
      } on StudySyncInterrupted {
        rethrow;
      } catch (_) {
        failedRenders = true;
        continue;
      }
      try {
        check();
        await drive.upload(
          file,
          library,
          study: true,
          targetId: existing.id,
          parentId: parent,
          name: item.name,
          update: existing.file != null,
          studyProperties: {
            'library': library,
            'studyKey': item.key,
            'hash': item.hash,
          },
        );
      } finally {
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          /* Retried by startup cleanup. */
        }
      }
    }
    check();
    if (failedRenders) {
      throw const BackupFailure(
        'Algunos PDF no se pudieron generar y siguen pendientes.',
      );
    }
    status('PDF actualizados en Drive');
  }
}
