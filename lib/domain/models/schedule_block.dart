import 'dart:convert';

class ScheduleBlock {
  final int id;
  final int labSpaceId;
  final int? folderId;
  final String title;
  final String? location;
  final String startTime;
  final String endTime;
  final List<String> days;
  final String color;
  final bool useFolderColor;
  final DateTime createdAt;

  const ScheduleBlock({
    required this.id,
    required this.labSpaceId,
    this.folderId,
    required this.title,
    this.location,
    required this.startTime,
    required this.endTime,
    required this.days,
    required this.color,
    this.useFolderColor = false,
    required this.createdAt,
  });

  static String daysToJson(List<String> days) => jsonEncode(days);
  String get daysJson => jsonEncode(days);

  static List<String> daysFromJson(String json) =>
      List<String>.from(jsonDecode(json) as List<dynamic>);

  static int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int get startMinutes => _timeToMinutes(startTime);
  int get endMinutes => _timeToMinutes(endTime);
  int get durationMinutes => endMinutes - startMinutes;

  bool overlaps(ScheduleBlock other) =>
      startMinutes < other.endMinutes && endMinutes > other.startMinutes;

  ScheduleBlock copyWith({
    int? id,
    int? labSpaceId,
    int? folderId,
    bool clearFolderId = false,
    String? title,
    String? location,
    bool clearLocation = false,
    String? startTime,
    String? endTime,
    List<String>? days,
    String? color,
    bool? useFolderColor,
    DateTime? createdAt,
  }) =>
      ScheduleBlock(
        id: id ?? this.id,
        labSpaceId: labSpaceId ?? this.labSpaceId,
        folderId:
            clearFolderId ? null : (folderId ?? this.folderId),
        title: title ?? this.title,
        location:
            clearLocation ? null : (location ?? this.location),
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        days: days ?? this.days,
        color: color ?? this.color,
        useFolderColor: useFolderColor ?? this.useFolderColor,
        createdAt: createdAt ?? this.createdAt,
      );
}
