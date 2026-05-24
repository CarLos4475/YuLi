import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/data/local/database.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DateTime SQLite transition check', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final twoDaysAgo = now.subtract(const Duration(days: 2));
    final eightDaysAgo = now.subtract(const Duration(days: 8));

    // 1. Task created yesterday (should move pending -> yesterday)
    await db.into(db.tasks).insert(TasksCompanion.insert(
      content: 'Pending from yesterday',
      status: 'pending',
      createdAt: Value(yesterday),
      expiresAt: now,
    ));

    // 2. Task created 2 days ago (which was yesterday -> archived_failed)
    await db.into(db.tasks).insert(TasksCompanion.insert(
      content: 'Yesterday task from 2 days ago',
      status: 'yesterday',
      createdAt: Value(twoDaysAgo),
      expiresAt: now,
    ));

    // 3. Task already in archived_failed (should move archived_failed -> trash, count towards archivedCount)
    await db.into(db.tasks).insert(TasksCompanion.insert(
      content: 'Failed task ready for trash',
      status: 'archived_failed',
      createdAt: Value(twoDaysAgo),
      expiresAt: now,
    ));

    // 4. Task in trash for 8 days (should be permanently deleted)
    await db.into(db.tasks).insert(TasksCompanion.insert(
      content: 'Old trash task',
      status: 'trash',
      createdAt: Value(eightDaysAgo),
      expiresAt: now,
      trashedAt: Value(eightDaysAgo),
    ));

    // Run the actual expiry queries
    final count = await db.runExpiryQueries();
    print('Expiry queries run, count: $count');

    // Check status of all remaining tasks
    final afterResult = await db.customSelect('SELECT content, status FROM tasks').get();
    for (final row in afterResult) {
      print('After: content="${row.read<String>('content')}", status="${row.read<String>('status')}"');
    }

    await db.close();
  });
}
