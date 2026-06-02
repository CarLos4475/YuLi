enum ReminderPreset {
  atDue,
  before30m,
  before1d,
  custom;

  static ReminderPreset? fromDb(String? value) => switch (value) {
    null => null,
    'at_due' => atDue,
    'before_30m' => before30m,
    'before_1d' => before1d,
    'custom' => custom,
    _ => null,
  };

  String toDbString() => switch (this) {
    atDue => 'at_due',
    before30m => 'before_30m',
    before1d => 'before_1d',
    custom => 'custom',
  };
}

DateTime? reminderTimeForPreset(ReminderPreset preset, DateTime? dueDate) {
  if (preset == ReminderPreset.custom) return null;
  if (dueDate == null) return null;
  return switch (preset) {
    ReminderPreset.atDue => dueDate,
    ReminderPreset.before30m => dueDate.subtract(const Duration(minutes: 30)),
    ReminderPreset.before1d => dueDate.subtract(const Duration(days: 1)),
    ReminderPreset.custom => null,
  };
}
