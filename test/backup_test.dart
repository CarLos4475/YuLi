import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/services/backup/backup_bundle.dart';
import 'package:yuli/data/services/backup/backup_paths.dart';
import 'package:yuli/data/services/backup/local_backup_service.dart';
import 'package:yuli/domain/services/pending_saves.dart';

void main() {
  test(
    'portable paths normalize Windows separators without rewriting prose',
    () {
      expect(
        rebaseBackupPaths(
          r'![Foto](C:\Docs\note_images\1\a.jpg)',
          r'C:\Docs',
          '/data/yuli',
        ),
        '![Foto](/data/yuli/note_images/1/a.jpg)',
      );
      expect(
        rebaseBackupPaths('Texto C:/Docs de ejemplo', 'C:/Docs', '/data/yuli'),
        'Texto C:/Docs de ejemplo',
      );
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppDatabase db;
  late SharedPreferences prefs;
  late LocalBackupService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('yuli_backup_test_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'deepseek_api_key': 'excluded-test-value',
      'backup_auto_account_v1': 'old-account',
      'yuli_user_memory_v1': 'Memory',
    });
    prefs = await SharedPreferences.getInstance();
    service = LocalBackupService(db, root, prefs);
    final folder = await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(name: 'Curso', color: '#123456'));
    final note = await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            folderId: folder,
            title: const drift.Value('Cuaderno'),
          ),
        );
    final block = await db
        .into(db.noteBlocks)
        .insert(
          NoteBlocksCompanion.insert(
            noteId: note,
            position: 0,
            type: 'drawing',
            payload: const drift.Value('{"i":[{"f":"photo.jpg"}]}'),
          ),
        );
    await db
        .into(db.drawingStrokes)
        .insert(
          DrawingStrokesCompanion.insert(
            blockId: block,
            position: 0,
            data: Uint8List.fromList([0, 1, 254, 255]),
            minX: 0,
            minY: 0,
            maxX: 1,
            maxY: 1,
            pointCount: 2,
          ),
        );
    final image = File(p.join(root.path, 'note_images', '$note', 'photo.jpg'));
    await image.parent.create(recursive: true);
    await image.writeAsBytes([1, 2, 3]);
    await db
        .into(db.noteImages)
        .insert(
          NoteImagesCompanion.insert(
            noteId: note,
            filename: 'photo.jpg',
            filePath: image.path,
            sizeBytes: 3,
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            folderId: folder,
            rawMarkdown: drift.Value('![Imagen](${image.path})'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'round trip includes binary strokes, files, preferences and all tables',
    () async {
      final file = await service.create();
      final manifest = await BackupBundle.inspect(file);
      expect((manifest['counts'] as Map).length, db.allTables.length);
      expect((manifest['counts'] as Map)['drawing_strokes'], 1);
      final stage = await service.prepareRestore(file);
      final restored = sqlite3.open(p.join(stage.path, 'yuli_db.sqlite'));
      try {
        expect(
          restored.select('SELECT data FROM drawing_strokes').single['data'],
          [0, 1, 254, 255],
        );
        expect(
          restored.select('SELECT title FROM notes WHERE id=1').single['title'],
          'Cuaderno',
        );
      } finally {
        restored.dispose();
      }
      final preferences =
          jsonDecode(
                await File(
                  p.join(stage.path, 'preferences.json'),
                ).readAsString(),
              )
              as Map;
      expect(preferences['theme_mode'], 'dark');
      expect(preferences['yuli_user_memory_v1'], 'Memory');
      expect(preferences.containsKey('deepseek_api_key'), isFalse);
      expect(preferences.containsKey('backup_auto_account_v1'), isFalse);
      expect(
        await File(p.join(stage.path, 'note_images/1/photo.jpg')).readAsBytes(),
        [1, 2, 3],
      );
    },
  );

  test(
    'restoring to a different documents root rebases note image paths',
    () async {
      final file = await service.create();
      final other = Directory(p.join(root.path, 'other'))..createSync();
      final destination = LocalBackupService(db, other, prefs);
      final stage = await destination.prepareRestore(file);
      final restored = sqlite3.open(p.join(stage.path, 'yuli_db.sqlite'));
      try {
        final expected =
            '${other.path.replaceAll('\\', '/')}/note_images/1/photo.jpg';
        final value =
            restored
                    .select('SELECT file_path FROM note_images')
                    .single['file_path']
                as String;
        expect(value.replaceAll('\\', '/'), expected);
        expect(
          (restored
                      .select('SELECT raw_markdown FROM notes WHERE id=2')
                      .single['raw_markdown']
                  as String)
              .replaceAll('\\', '/'),
          contains(expected),
        );
      } finally {
        restored.dispose();
      }
    },
  );

  test('truncated and modified bundles never restore', () async {
    final file = await service.create();
    final bytes = await file.readAsBytes();
    final truncated = File(p.join(root.path, 'short.yuli'));
    await truncated.writeAsBytes(bytes.sublist(0, bytes.length - 1));
    await expectLater(
      service.prepareRestore(truncated),
      throwsA(isA<BackupFailure>()),
    );
    bytes[bytes.length - 1] ^= 0xff;
    final corrupted = File(p.join(root.path, 'bad.yuli'));
    await corrupted.writeAsBytes(bytes);
    await expectLater(
      service.prepareRestore(corrupted),
      throwsA(isA<BackupFailure>()),
    );
    expect(await db.select(db.notes).get(), hasLength(2));
  });

  test('rejects path traversal, duplicate paths and extra bytes', () async {
    final file = await service.create();
    final manifest = await BackupBundle.inspect(file);
    for (final path in [
      '../escape',
      '/tmp/file',
      'note_images/1/../../escape',
      'note_images/1/C:secret',
      'note_images/1/file.',
    ]) {
      expect(BackupBundle.validPath(path), isFalse);
    }
    final bytes = await file.readAsBytes();
    final headerSize = ByteData.sublistView(bytes, 8, 12).getUint32(0);
    final payload = bytes.sublist(12 + headerSize);
    (manifest['files'] as List).first['path'] = '../outside';
    final header = utf8.encode(jsonEncode(manifest));
    final malicious = File(p.join(root.path, 'path.yuli'));
    await malicious.writeAsBytes([
      ...BackupBundle.magic,
      ...(ByteData(4)..setUint32(0, header.length)).buffer.asUint8List(),
      ...header,
      ...payload,
    ]);
    await expectLater(
      service.prepareRestore(malicious),
      throwsA(isA<BackupFailure>()),
    );
    await file.writeAsBytes([0], mode: FileMode.append);
    await expectLater(
      BackupBundle.inspect(file),
      throwsA(isA<BackupFailure>()),
    );
  });

  test(
    'missing attachments abort backup instead of reporting success',
    () async {
      await File(p.join(root.path, 'note_images/1/photo.jpg')).delete();
      await expectLater(service.create(), throwsA(isA<BackupFailure>()));
    },
  );

  test(
    'startup restore preserves previous files and survives a partial rename',
    () async {
      final backup = await service.create();
      final stage = await service.prepareRestore(backup);
      final liveDb = File(p.join(root.path, 'yuli_db.sqlite'));
      await liveDb.writeAsString('Old database');
      await File(
        p.join(root.path, 'note_images/1/photo.jpg'),
      ).writeAsBytes([9]);
      await service.scheduleRestore(stage);
      final journal =
          jsonDecode(
                await File(
                  p.join(root.path, 'restore_pending.json'),
                ).readAsString(),
              )
              as Map;
      final previous = Directory(
        p.join(root.path, 'backups', journal['previous'] as String),
      );
      await liveDb.rename(p.join(previous.path, 'yuli_db.sqlite'));
      await LocalBackupService.applyPendingRestore(root, prefs);
      expect(
        await File(p.join(root.path, 'note_images/1/photo.jpg')).readAsBytes(),
        [1, 2, 3],
      );
      expect(
        await File(
          p.join(previous.path, 'note_images/1/photo.jpg'),
        ).readAsBytes(),
        [9],
      );
      expect(
        await File(p.join(previous.path, 'yuli_db.sqlite')).readAsString(),
        'Old database',
      );
      expect(prefs.getString('backup_auto_account_v1'), isNull);
      expect(prefs.getString('deepseek_api_key'), 'excluded-test-value');
      await LocalBackupService.applyPendingRestore(root, prefs);
      expect(
        await File(p.join(root.path, 'restore_pending.json')).exists(),
        isFalse,
      );
    },
  );

  test(
    'backup barrier waits for scheduled and running editor writes',
    () async {
      var saved = false;
      PendingSaves.schedule(Object(), () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        saved = true;
      });
      await PendingSaves.flush();
      expect(saved, isTrue);
    },
  );
}
