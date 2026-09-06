import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../local/database.dart';
import 'backup_bundle.dart';
import 'backup_preferences.dart';
import 'backup_paths.dart';

class LocalBackupService {
  final AppDatabase database;
  final Directory documents;
  final SharedPreferences preferences;

  LocalBackupService(this.database, this.documents, this.preferences);

  Stream<void> get studyChanges => database.tableUpdates().map((_) {});

  Future<T> readConsistent<T>(Future<T> Function() read) =>
      database.transaction(read);

  Future<void> cleanupStudyExports() async {
    final root = Directory(p.join(documents.path, 'study_exports'));
    if (!await root.exists()) return;
    await for (final file in root.list(followLinks: false)) {
      if (file is File &&
          RegExp(r'^[0-9a-f-]{36}\.pdf$').hasMatch(p.basename(file.path))) {
        try {
          await file.delete();
        } on FileSystemException {
          /* Retry on next run. */
        }
      }
    }
  }

  Future<String> deviceId() async {
    final existing = preferences.getString('backup_device_id_v1');
    if (existing != null) return existing;
    final id = const Uuid().v4();
    if (!await preferences.setString('backup_device_id_v1', id)) {
      throw const BackupFailure('No se pudo identificar esta tablet.');
    }
    return id;
  }

  Future<File> create() async {
    final root = Directory(p.join(documents.path, 'backups'));
    await root.create(recursive: true);
    final work = await root.createTemp('work_');
    final output = File(
      p.join(
        root.path,
        'YuLi_${DateTime.now().toUtc().millisecondsSinceEpoch}_${const Uuid().v4()}.yuli',
      ),
    );
    try {
      await database.customStatement('VACUUM INTO ?', [
        p.join(work.path, 'yuli_db.sqlite'),
      ]);
      await File(p.join(work.path, 'preferences.json')).writeAsString(
        jsonEncode(exportBackupPreferences(preferences)),
        flush: true,
      );
      for (final name in BackupBundle.roots) {
        final from = Directory(p.join(documents.path, name));
        if (!await from.exists()) continue;
        await for (final entity in from.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is Link) {
            throw const BackupFailure('Adjunto no compatible.');
          }
          if (entity is! File) continue;
          final target = File(
            p.join(work.path, name, p.relative(entity.path, from: from.path)),
          );
          await target.parent.create(recursive: true);
          await entity.copy(target.path);
        }
      }
      final schema = database.schemaVersion;
      final device = await deviceId();
      final sourceRoot = documents.path;
      final expectedTables =
          database.allTables.map((t) => t.actualTableName).toSet();
      await Isolate.run(() async {
        final snapshot = sqlite3.open(
          p.join(work.path, 'yuli_db.sqlite'),
          mode: OpenMode.readOnly,
        );
        final counts = <String, int>{};
        try {
          for (final table in expectedTables) {
            counts[table] =
                snapshot.select('SELECT COUNT(*) AS n FROM "$table"').first['n']
                    as int;
          }
          _validateFiles(snapshot, work);
        } finally {
          snapshot.dispose();
        }
        await BackupBundle.create(
          source: work,
          destination: output,
          schema: schema,
          deviceId: device,
          documentsPath: sourceRoot,
          counts: counts,
        );
        final verified = Directory('${work.path}_verify');
        try {
          await BackupBundle.extract(output, verified);
        } finally {
          if (await verified.exists()) await verified.delete(recursive: true);
        }
      });
      return output;
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<Directory> prepareRestore(File bundle) async {
    final root = Directory(p.join(documents.path, 'backups'));
    await root.create(recursive: true);
    final stage = Directory(p.join(root.path, 'restore_${const Uuid().v4()}'));
    final schema = database.schemaVersion;
    final expected = {
      for (final t in database.allTables)
        t.actualTableName: t.$columns.map((c) => c.$name).toSet(),
    };
    final destinationRoot = documents.path;
    return Isolate.run(() async {
      try {
        final manifest = await BackupBundle.extract(bundle, stage);
        if (manifest['schema'] != schema) {
          throw const BackupFailure(
            'Este respaldo requiere la misma versión de datos de YuLi.',
          );
        }
        final file = p.join(stage.path, 'yuli_db.sqlite');
        final db = sqlite3.open(file);
        try {
          db.execute('PRAGMA trusted_schema = OFF');
          final objects = db.select(
            "SELECT name, type, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
          );
          final tables =
              objects
                  .where((o) => o['type'] == 'table')
                  .map((o) => o['name'] as String)
                  .toSet();
          if (objects.any(
                (o) => '${o['sql']}'.toUpperCase().contains('VIRTUAL TABLE'),
              ) ||
              objects.any(
                (o) => o['type'] != 'table' && o['type'] != 'index',
              ) ||
              tables.length != expected.length ||
              !tables.containsAll(expected.keys)) {
            throw const BackupFailure('Estructura de respaldo incompatible.');
          }
          for (final entry in expected.entries) {
            final actualCount =
                db
                    .select('SELECT COUNT(*) AS n FROM "${entry.key}"')
                    .single['n'];
            if ((manifest['counts'] as Map)[entry.key] != actualCount) {
              throw const BackupFailure(
                'El inventario no coincide con la base del respaldo.',
              );
            }
            final columns =
                db
                    .select('PRAGMA table_info("${entry.key}")')
                    .map((r) => r['name'] as String)
                    .toSet();
            if (columns.length != entry.value.length ||
                !columns.containsAll(entry.value)) {
              throw const BackupFailure('Estructura de respaldo incompatible.');
            }
          }
          if (db.userVersion != schema ||
              db
                  .select('PRAGMA integrity_check')
                  .any((r) => r.values.first != 'ok')) {
            throw const BackupFailure(
              'La base del respaldo no pasó la verificación.',
            );
          }
          _validateFiles(db, stage);
          final previousRoot = manifest['documentsPath'] as String;
          if (previousRoot.isEmpty) {
            throw const BackupFailure('Ruta de origen inválida.');
          }
          for (final field in [
            ('notes', 'raw_markdown'),
            ('note_versions', 'raw_markdown'),
            ('note_blocks', 'payload'),
            ('note_images', 'file_path'),
          ]) {
            for (final row in db.select(
              'SELECT id, ${field.$2} AS value FROM ${field.$1}',
            )) {
              final value = row['value'];
              if (value is! String) continue;
              final replacement =
                  field.$2 == 'payload'
                      ? jsonEncode(
                        rebaseBackupJson(
                          jsonDecode(value),
                          previousRoot,
                          destinationRoot,
                        ),
                      )
                      : rebaseBackupPaths(value, previousRoot, destinationRoot);
              if (replacement == value) continue;
              db.execute(
                'UPDATE ${field.$1} SET ${field.$2} = ? WHERE id = ?',
                [replacement, row['id']],
              );
            }
          }
        } finally {
          db.dispose();
        }
        final prefsFile = File(p.join(stage.path, 'preferences.json'));
        final prefs = jsonDecode(await prefsFile.readAsString());
        if (prefs is! Map<String, dynamic> ||
            prefs.entries.any(
              (e) =>
                  !isBackupPreference(e.key) ||
                  !(e.value is String ||
                      e.value is num ||
                      e.value is bool ||
                      (e.value is List &&
                          (e.value as List).every((v) => v is String))),
            )) {
          throw const BackupFailure('Preferencias de respaldo inválidas.');
        }
        for (final name in BackupBundle.roots) {
          await Directory(p.join(stage.path, name)).create(recursive: true);
        }
        await File(p.join(stage.path, 'restore_info.json')).writeAsString(
          jsonEncode({
            'createdAt': manifest['createdAt'],
            'counts': manifest['counts'],
          }),
          flush: true,
        );
        return stage;
      } catch (_) {
        if (await stage.exists()) await stage.delete(recursive: true);
        rethrow;
      }
    });
  }

  Future<void> scheduleRestore(Directory stage) async {
    final backupRoot = p.join(documents.path, 'backups');
    if (!p.isWithin(backupRoot, stage.path) || !await stage.exists()) {
      throw const BackupFailure('Restauración no preparada.');
    }
    final journal = File(p.join(documents.path, 'restore_pending.json'));
    if (await journal.exists()) {
      throw const BackupFailure('Ya hay una restauración pendiente.');
    }
    final previous = Directory(
      p.join(backupRoot, 'previous_${const Uuid().v4()}'),
    );
    await previous.create();
    await File(p.join(previous.path, 'preferences.json')).writeAsString(
      jsonEncode(exportBackupPreferences(preferences)),
      flush: true,
    );
    final pending = File('${journal.path}.tmp');
    await pending.writeAsString(
      jsonEncode({
        'stage': p.basename(stage.path),
        'previous': p.basename(previous.path),
      }),
      flush: true,
    );
    await pending.rename(journal.path);
  }

  // Runs before opening SQLite or starting expiry/GC. Each rename is replayable
  // after process death, and the previous data stays available on disk.
  static Future<void> applyPendingRestore(
    Directory documents,
    SharedPreferences prefs,
  ) async {
    final journal = File(p.join(documents.path, 'restore_pending.json'));
    if (!await journal.exists()) return;
    final data =
        jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    for (final key in ['stage', 'previous']) {
      final name = data[key];
      if (name is! String ||
          !RegExp(r'^(restore|previous)_[a-f0-9-]+$').hasMatch(name)) {
        throw const BackupFailure('Registro de restauración inválido.');
      }
    }
    final stage = Directory(
      p.join(documents.path, 'backups', data['stage'] as String),
    );
    final previous = Directory(
      p.join(documents.path, 'backups', data['previous'] as String),
    );
    for (final name in [
      'yuli_db.sqlite-wal',
      'yuli_db.sqlite-shm',
      'yuli_db.sqlite-journal',
    ]) {
      final file = File(p.join(documents.path, name));
      final old = File(p.join(previous.path, name));
      if (await file.exists() && !await old.exists()) {
        await file.rename(old.path);
      }
    }
    for (final name in ['yuli_db.sqlite', ...BackupBundle.roots]) {
      final directory = name != 'yuli_db.sqlite';
      final FileSystemEntity from =
          directory
              ? Directory(p.join(stage.path, name))
              : File(p.join(stage.path, name));
      final FileSystemEntity live =
          directory
              ? Directory(p.join(documents.path, name))
              : File(p.join(documents.path, name));
      final FileSystemEntity old =
          directory
              ? Directory(p.join(previous.path, name))
              : File(p.join(previous.path, name));
      if (await from.exists()) {
        if (await live.exists()) {
          if (await old.exists()) {
            throw const BackupFailure('Conflicto durante la restauración.');
          }
          await live.rename(old.path);
        }
        await from.rename(live.path);
      } else if (!await live.exists()) {
        throw const BackupFailure('Falta un archivo de la restauración.');
      }
    }
    await importBackupPreferences(
      prefs,
      jsonDecode(
            await File(p.join(stage.path, 'preferences.json')).readAsString(),
          )
          as Map<String, dynamic>,
    );
    if (!await prefs.remove('backup_auto_account_v1')) {
      throw const BackupFailure(
        'No se pudo desactivar el respaldo automático.',
      );
    }
    if (!await prefs.remove('study_auto_account_v1')) {
      throw const BackupFailure(
        'No se pudo desactivar la publicación automática.',
      );
    }
    await prefs.remove('backup_last_success_v1');
    await journal.delete();
  }

  static void _validateFiles(Database db, Directory root) {
    for (final row in db.select(
      "SELECT note_id, metadata_json FROM floating_pins WHERE kind IN ('image', 'pdf', 'video')",
    )) {
      final metadata = jsonDecode(row['metadata_json'] as String) as Map;
      final name = metadata['filename'];
      if (name == null) continue;
      final relative = 'floating_pins/${row['note_id']}/$name';
      if (name is! String ||
          !BackupBundle.validPath(relative) ||
          !File(p.join(root.path, relative)).existsSync()) {
        throw const BackupFailure('Falta un archivo de un pin.');
      }
    }
    for (final row in db.select('SELECT note_id, filename FROM note_images')) {
      final name = row['filename'] as String;
      if (p.basename(name) != name ||
          !File(
            p.join(root.path, 'note_images', '${row['note_id']}', name),
          ).existsSync()) {
        throw const BackupFailure('Falta una imagen del apunte.');
      }
    }
    for (final row in db.select(
      "SELECT note_id, payload FROM note_blocks WHERE type = 'drawing'",
    )) {
      final payload = jsonDecode(row['payload'] as String) as Map;
      for (final image in (payload['i'] as List? ?? const [])) {
        final name = image['f'] ?? image['filename'];
        if (name is! String ||
            !BackupBundle.validPath('note_images/${row['note_id']}/$name') ||
            !File(
              p.join(root.path, 'note_images', '${row['note_id']}', name),
            ).existsSync()) {
          throw const BackupFailure('Falta una imagen del lienzo.');
        }
      }
    }
  }
}
