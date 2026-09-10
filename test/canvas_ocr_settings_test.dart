import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/presentation/providers/canvas_ocr_settings_provider.dart';
import 'package:yuli/presentation/screens/settings/settings_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'settings default on and persist independently across containers',
    () async {
      final first = ProviderContainer();
      final defaults = await first.read(canvasOcrSettingsProvider.future);
      expect(defaults.automatic, true);
      expect(defaults.spelling, true);
      await first
          .read(canvasOcrSettingsProvider.notifier)
          .setOptions(automatic: false);
      first.dispose();
      final second = ProviderContainer();
      addTearDown(second.dispose);
      final restored = await second.read(canvasOcrSettingsProvider.future);
      expect(restored.automatic, false);
      expect(restored.spelling, true);
      await second
          .read(canvasOcrSettingsProvider.notifier)
          .setOptions(spelling: false);
      expect(
        second.read(canvasOcrSettingsProvider).requireValue.automatic,
        false,
      );
      expect(
        second.read(canvasOcrSettingsProvider).requireValue.spelling,
        false,
      );
    },
  );

  for (final width in [320.0, 1024.0]) {
    testWidgets('OCR settings toggles work at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CanvasOcrSettingsBlock())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reconocimiento automático'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CanvasOcrSettingsBlock)),
      );
      expect(
        container.read(canvasOcrSettingsProvider).requireValue.automatic,
        false,
      );
      expect(
        container.read(canvasOcrSettingsProvider).requireValue.spelling,
        true,
      );
      await tester.tap(find.text('Revisión ortográfica'));
      await tester.pumpAndSettle();
      expect(
        container.read(canvasOcrSettingsProvider).requireValue.spelling,
        false,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
