import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/folder.dart';
import 'database_providers.dart';

final activeFoldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(folderRepositoryProvider).watchActive();
});

final folderByIdProvider = StreamProvider.family<Folder?, int>((ref, id) {
  return ref.watch(folderRepositoryProvider).watchActive().map(
    (folders) => folders.where((f) => f.id == id).firstOrNull,
  );
});
