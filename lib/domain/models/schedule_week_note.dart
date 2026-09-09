class ScheduleWeekNote {
  final int id;
  final DateTime weekStartDate;
  final String note;

  const ScheduleWeekNote({
    required this.id,
    required this.weekStartDate,
    required this.note,
  });

  String get weekStartDateStr =>
      '${weekStartDate.year}-${weekStartDate.month.toString().padLeft(2, '0')}-${weekStartDate.day.toString().padLeft(2, '0')}';

  ScheduleWeekNote copyWith({int? id, DateTime? weekStartDate, String? note}) =>
      ScheduleWeekNote(
        id: id ?? this.id,
        weekStartDate: weekStartDate ?? this.weekStartDate,
        note: note ?? this.note,
      );
}
