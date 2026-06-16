import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/floating_pin_storage.dart';
import 'database_providers.dart';

/// Garbage-collects floating-pin media: folders of notes with no rows and any
/// file no row references. Fired once at startup (after the expiry sweep),
/// SEPARATE from the note-image GC so it never touches `note_images/`.
/// Fire-and-forget — never blocks the UI.
final floatingPinCleanupProvider = FutureProvider<void>((ref) async {
  final referenced =
      await ref.read(floatingPinRepositoryProvider).referencedFilesByNote();
  await cleanupOrphanedFloatingPins(referenced);
});
