import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/task.dart';
import 'database_providers.dart';

final pendingTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchPending();
});

final yesterdayTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchYesterday();
});

final vencidasTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchVencidas();
});

final doneTodayTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchDoneToday();
});

final pendingTasksForFolderProvider =
    StreamProvider.family<List<Task>, int>((ref, folderId) {
  return ref.watch(taskRepositoryProvider).watchPendingForFolder(folderId);
});
