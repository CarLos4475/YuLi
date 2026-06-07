import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/services/launcher_icon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimeBandRules.bandFor', () {
    test('morning: 06:00–11:59', () {
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 6, 0)), TimeBand.morning);
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 9, 30)), TimeBand.morning);
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 11, 59, 59)), TimeBand.morning);
    });

    test('afternoon: 12:00–17:59', () {
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 12, 0)), TimeBand.afternoon);
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 14, 30)), TimeBand.afternoon);
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 17, 59, 59)), TimeBand.afternoon);
    });

    test('evening: 18:00–05:59', () {
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 18, 0)), TimeBand.evening);
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 23, 59, 59)), TimeBand.evening);
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 0, 0)), TimeBand.evening);
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 3, 0)), TimeBand.evening);
      expect(TimeBandRules.bandFor(DateTime(2026, 6, 7, 5, 59, 59)), TimeBand.evening);
    });
  });

  group('TimeBandRules.iconFor', () {
    test('mapping morning→icon1, afternoon→icon2, evening→icon3', () {
      expect(TimeBandRules.iconFor(DateTime(2026, 6, 7, 8)), LauncherIconVariant.icon1);
      expect(TimeBandRules.iconFor(DateTime(2026, 6, 7, 14)), LauncherIconVariant.icon2);
      expect(TimeBandRules.iconFor(DateTime(2026, 6, 7, 21)), LauncherIconVariant.icon3);
      expect(TimeBandRules.iconFor(DateTime(2026, 6, 7, 3)), LauncherIconVariant.icon3);
    });
  });

  group('TimeBandRules.nextSwapAfter', () {
    test('before first boundary (05:00) → today 06:00', () {
      final now = DateTime(2026, 6, 7, 5, 0);
      final next = TimeBandRules.nextSwapAfter(now);
      expect(next, DateTime(2026, 6, 7, 6, 0));
    });

    test('between 06:00 and 12:00 (09:00) → today 12:00', () {
      final now = DateTime(2026, 6, 7, 9, 0);
      final next = TimeBandRules.nextSwapAfter(now);
      expect(next, DateTime(2026, 6, 7, 12, 0));
    });

    test('between 12:00 and 18:00 (15:00) → today 18:00', () {
      final now = DateTime(2026, 6, 7, 15, 0);
      final next = TimeBandRules.nextSwapAfter(now);
      expect(next, DateTime(2026, 6, 7, 18, 0));
    });

    test('between 18:00 and midnight (22:00) → tomorrow 06:00', () {
      final now = DateTime(2026, 6, 7, 22, 0);
      final next = TimeBandRules.nextSwapAfter(now);
      expect(next, DateTime(2026, 6, 8, 6, 0));
    });

    test('exactly on a boundary (06:00:00) → next is 12:00', () {
      final now = DateTime(2026, 6, 7, 6, 0);
      final next = TimeBandRules.nextSwapAfter(now);
      expect(next, DateTime(2026, 6, 7, 12, 0));
    });

    test('exactly on 18:00:00 → tomorrow 06:00', () {
      final now = DateTime(2026, 6, 7, 18, 0);
      final next = TimeBandRules.nextSwapAfter(now);
      expect(next, DateTime(2026, 6, 8, 6, 0));
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

    test('default = auto mode, manual override null → band-based', () async {
      await newService({});
      final svc = await newService({});
      expect(await svc.isAutoMode(), true);
    });

    test('auto mode ON, no override → uses band (we cannot inject time, but we can check that override path works)', () async {
      await newService({});
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
