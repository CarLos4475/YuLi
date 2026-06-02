// Smoke test: la app arranca, muestra el splash durante la inicialización y
// transiciona sin excepciones. El scheduler de recordatorios se sustituye por
// un no-op para no tocar el plugin nativo (no disponible en el harness).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/domain/services/reminder_scheduler.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/providers/theme_provider.dart';
import 'package:yuli/presentation/widgets/yuli_splash_screen.dart';
import 'package:yuli/main.dart';

void main() {
  testWidgets('App smoke test - muestra el splash al iniciar', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final themeOverride = await initThemeModeOverride();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          themeOverride,
          reminderSchedulerProvider.overrideWithValue(_NoopReminderScheduler()),
        ],
        child: const YuLiApp(),
      ),
    );

    // Durante la inicialización (expiry) se muestra el splash con el título.
    expect(find.text('YuLi'), findsOneWidget);
    expect(find.byType(YuliSplashScreen), findsOneWidget);

    // Desmonta el árbol (cancela la animación del splash) y cierra la BD.
    await tester.pumpWidget(const SizedBox());
    await db.close();
  }, semanticsEnabled: false);
}

class _NoopReminderScheduler implements ReminderScheduler {
  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestNotificationPermission() async => false;

  @override
  Future<bool> requestExactPermission() async => false;

  @override
  Future<void> schedule(ReminderRequest request) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<List<int>> pendingIds() async => const [];

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<void> openNotificationSettings() async {}
}
