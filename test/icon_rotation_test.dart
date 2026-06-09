import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/services/launcher_icon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IconCycleRules.currentSlot', () {
    test('00:00–03:59 → slot1 (icon1)', () {
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 0, 0)), IconCycleSlot.slot1);
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 1, 30)), IconCycleSlot.slot1);
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 3, 59, 59)), IconCycleSlot.slot1);
    });

    test('04:00–07:59 → slot2 (icon2)', () {
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 4, 0)), IconCycleSlot.slot2);
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 6, 0)), IconCycleSlot.slot2);
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 7, 59, 59)), IconCycleSlot.slot2);
    });

    test('08:00–11:59 → slot3 (icon3)', () {
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 8, 0)), IconCycleSlot.slot3);
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 11, 59, 59)), IconCycleSlot.slot3);
    });

    test('12:00–15:59 → slot1 (ciclo 2)', () {
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 12, 0)), IconCycleSlot.slot1);
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 15, 59, 59)), IconCycleSlot.slot1);
    });

    test('16:00–19:59 → slot2 (ciclo 2)', () {
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 16, 0)), IconCycleSlot.slot2);
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 19, 59, 59)), IconCycleSlot.slot2);
    });

    test('20:00–23:59 → slot3 (ciclo 2)', () {
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 20, 0)), IconCycleSlot.slot3);
      expect(IconCycleRules.currentSlot(DateTime(2026, 6, 7, 23, 59, 59)), IconCycleSlot.slot3);
    });
  });

  group('IconCycleRules.iconFor', () {
    test('icon assignment follows slot, cycling icon1→icon2→icon3×2/day', () {
      expect(IconCycleRules.iconFor(DateTime(2026, 6, 7, 2)), LauncherIconVariant.icon1);
      expect(IconCycleRules.iconFor(DateTime(2026, 6, 7, 6)), LauncherIconVariant.icon2);
      expect(IconCycleRules.iconFor(DateTime(2026, 6, 7, 10)), LauncherIconVariant.icon3);
      expect(IconCycleRules.iconFor(DateTime(2026, 6, 7, 14)), LauncherIconVariant.icon1);
      expect(IconCycleRules.iconFor(DateTime(2026, 6, 7, 18)), LauncherIconVariant.icon2);
      expect(IconCycleRules.iconFor(DateTime(2026, 6, 7, 22)), LauncherIconVariant.icon3);
    });
  });

  group('IconCycleRules.nextSwapAfter', () {
    test('00:30 → today 04:00', () {
      final now = DateTime(2026, 6, 7, 0, 30);
      expect(IconCycleRules.nextSwapAfter(now), DateTime(2026, 6, 7, 4, 0));
    });

    test('03:59:59 → today 04:00', () {
      final now = DateTime(2026, 6, 7, 3, 59, 59);
      expect(IconCycleRules.nextSwapAfter(now), DateTime(2026, 6, 7, 4, 0));
    });

    test('04:00:00 → today 08:00', () {
      final now = DateTime(2026, 6, 7, 4, 0);
      expect(IconCycleRules.nextSwapAfter(now), DateTime(2026, 6, 7, 8, 0));
    });

    test('12:00:00 → today 16:00', () {
      final now = DateTime(2026, 6, 7, 12, 0);
      expect(IconCycleRules.nextSwapAfter(now), DateTime(2026, 6, 7, 16, 0));
    });

    test('20:00:00 → tomorrow 00:00', () {
      final now = DateTime(2026, 6, 7, 20, 0);
      expect(IconCycleRules.nextSwapAfter(now), DateTime(2026, 6, 8, 0, 0));
    });

    test('23:30 → tomorrow 00:00', () {
      final now = DateTime(2026, 6, 7, 23, 30);
      expect(IconCycleRules.nextSwapAfter(now), DateTime(2026, 6, 8, 0, 0));
    });
  });

  group('LauncherIconService.targetForNow (with mocked prefs)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    Future<LauncherIconService> newService(Map<String, Object> seed) async {
      SharedPreferences.setMockInitialValues(seed);
      return LauncherIconService();
    }

    test('default = auto mode, manual override null → cycle-based', () async {
      final svc = await newService({});
      expect(await svc.isAutoMode(), true);
    });

    test('auto mode ON, no override → uses cycle (returns one of 3 icons)', () async {
      final svc = await newService({});
      final t = await svc.targetForNow();
      expect([LauncherIconVariant.icon1, LauncherIconVariant.icon2, LauncherIconVariant.icon3], contains(t));
    });

    test('auto mode OFF, manual override = icon2 → returns icon2', () async {
      final svc = await newService({'auto_mode': false, 'manual_override': 'icon2'});
      expect(await svc.targetForNow(), LauncherIconVariant.icon2);
    });

    test('auto mode ON, manual override = icon3 (sticky) → returns icon3', () async {
      final svc = await newService({'auto_mode': true, 'manual_override': 'icon3'});
      expect(await svc.targetForNow(), LauncherIconVariant.icon3);
    });
  });
}
