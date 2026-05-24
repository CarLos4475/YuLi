import 'package:drift/drift.dart';

@DataClassName('OnboardingFlagRow')
class OnboardingFlags extends Table {
  // fight_intro | fight_modes | flight_intro | lab_intro | fight_at_mention | block_insert
  TextColumn get key => text()();
  DateTimeColumn get seenAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}
