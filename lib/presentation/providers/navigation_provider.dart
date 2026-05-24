import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pending navigation request: open a note by ID in Flight mode.
/// AppShell watches this; when non-null it switches to Flight and clears the value.
final pendingNoteNavigationProvider = StateProvider<int?>((ref) => null);

final pendingLabSpaceNavigationProvider = StateProvider<int?>((ref) => null);
