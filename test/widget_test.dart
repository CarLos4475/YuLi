// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/main.dart';

void main() {
  testWidgets('App smoke test - shows title and loading indicator', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    // Build our app and trigger a frame, overriding the database with our in-memory one.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: const YuLiApp(),
      ),
    );

    // Verify that the title 'YuLi' is displayed during initialization.
    expect(find.text('YuLi'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Allow the initialization future to complete and rebuild the app shell
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await db.close();
  }, semanticsEnabled: false);
}
