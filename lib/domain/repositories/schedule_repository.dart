import '../models/schedule_block.dart';
import '../models/schedule_settings.dart';
import '../models/schedule_week_note.dart';

abstract class ScheduleRepository {
  Stream<List<ScheduleBlock>> watchBySpace(int labSpaceId);
  Future<ScheduleBlock> createBlock({
    required int labSpaceId,
    int? folderId,
    required String title,
    String? location,
    required String startTime,
    required String endTime,
    required List<String> days,
    required String color,
    bool useFolderColor = false,
  });
  Future<void> updateBlock(ScheduleBlock block);
  Future<void> deleteBlock(int id);

  Future<ScheduleSettings> getOrCreateSettings(int labSpaceId);
  Future<void> updateSettings(ScheduleSettings settings);

  Future<ScheduleWeekNote?> getWeekNote(int labSpaceId, DateTime weekStart);
  Stream<ScheduleWeekNote?> watchWeekNote(int labSpaceId, DateTime weekStart);
  Future<void> setWeekNote(int labSpaceId, DateTime weekStart, String note);
  Future<void> deleteWeekNote(int id);
  Future<List<ScheduleBlock>> getByFolderId(int folderId);
}
