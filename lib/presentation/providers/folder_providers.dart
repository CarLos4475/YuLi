import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/folder.dart';
import 'database_providers.dart';

final activeFoldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(folderRepositoryProvider).watchActive();
});

final folderByIdProvider = FutureProvider.family<Folder?, int>((ref, id) {
  return ref.watch(folderRepositoryProvider).getById(id);
});
