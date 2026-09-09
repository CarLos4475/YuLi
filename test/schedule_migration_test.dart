import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_schedule_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'v26 conserva bloques y fusiona configuración y notas semanales',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'yuli_schedule_migration_',
      );
      final file = File('${directory.path}/legacy.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
      CREATE TABLE schedule_blocks (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        lab_space_id INTEGER NOT NULL,
        folder_id INTEGER,
        title TEXT NOT NULL,
        location TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        days TEXT NOT NULL,
        color TEXT NOT NULL,
        use_folder_color INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
      legacy.execute('''
      CREATE TABLE schedule_settings (
        lab_space_id INTEGER NOT NULL PRIMARY KEY,
        show_saturday INTEGER,
        show_sunday INTEGER,
        day_start_time TEXT NOT NULL DEFAULT '07:00',
        day_end_time TEXT NOT NULL DEFAULT '22:00'
      )
    ''');
      legacy.execute('''
      CREATE TABLE schedule_week_notes (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        lab_space_id INTEGER NOT NULL,
        week_start_date TEXT NOT NULL,
        note TEXT NOT NULL
      )
    ''');
      legacy.execute(
        "INSERT INTO schedule_blocks VALUES "
        "(1, 9, 4, 'Sistemas', 'Aula 12', '08:00', '09:00', "
        "'[\"Lun\"]', '#112233', 1, 1750000000)",
      );
      legacy.execute(
        "INSERT INTO schedule_settings VALUES "
        "(9, 0, 0, '08:00', '20:00'), "
        "(10, 1, 0, '07:00', '22:00')",
      );
      legacy.execute(
        "INSERT INTO schedule_week_notes VALUES "
        "(1, 9, '2026-09-07', 'Examen'), "
        "(2, 10, '2026-09-07', 'Entrega')",
      );
      legacy.execute('PRAGMA user_version = 26');
      legacy.dispose();

      final db = AppDatabase.forTesting(NativeDatabase(file));
      final repo = LocalScheduleRepository(db);
      addTearDown(() async {
        await db.close();
        directory.deleteSync(recursive: true);
      });

      final blocks = await repo.watchAll().first;
      expect(blocks, hasLength(1));
      expect(blocks.single.labSpaceId, 9);
      expect(blocks.single.folderId, 4);
      expect(blocks.single.title, 'Sistemas');

      final settings = await repo.getOrCreateSettings();
      expect(settings.showSaturday, isTrue);
      expect(settings.dayStartTime, '07:00');
      expect(settings.dayEndTime, '22:00');

      final note = await repo.getWeekNote(DateTime(2026, 9, 7));
      expect(note, isNotNull);
      expect(note!.note, contains('Examen'));
      expect(note.note, contains('Entrega'));
    },
  );
}
