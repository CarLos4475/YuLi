class ScheduleSettings {
  final int labSpaceId;
  final bool showSaturday;
  final bool showSunday;
  final String dayStartTime;
  final String dayEndTime;

  const ScheduleSettings({
    required this.labSpaceId,
    this.showSaturday = false,
    this.showSunday = false,
    this.dayStartTime = '07:00',
    this.dayEndTime = '22:00',
  });

  int get startMinutes {
    final parts = dayStartTime.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int get endMinutes {
    final parts = dayEndTime.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int get totalMinutes => endMinutes - startMinutes;

  ScheduleSettings copyWith({
    int? labSpaceId,
    bool? showSaturday,
    bool? showSunday,
    String? dayStartTime,
    String? dayEndTime,
  }) =>
      ScheduleSettings(
        labSpaceId: labSpaceId ?? this.labSpaceId,
        showSaturday: showSaturday ?? this.showSaturday,
        showSunday: showSunday ?? this.showSunday,
        dayStartTime: dayStartTime ?? this.dayStartTime,
        dayEndTime: dayEndTime ?? this.dayEndTime,
      );
}
