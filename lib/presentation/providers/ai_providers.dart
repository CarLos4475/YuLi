import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ai_key_store.dart';
import '../../data/services/ai_usage_limiter.dart';
import '../../data/services/deepseek_assistant.dart';
import '../../data/services/web_reader.dart';
import '../../domain/services/ai_assistant.dart';
import '../screens/flight/ai_chat_session.dart';
import '../screens/flight/ai_modes.dart';

final aiKeyStoreProvider = Provider<AiKeyStore>((ref) => AiKeyStore());

/// Store for user-authored chat modes (custom personas). Reactive — the mode
/// catalog watches it so adding/removing a mode rebuilds. The module-level
/// mirror in ai_modes.dart is loaded at app start (so [aiModeById] resolves
/// persisted custom ids even before this provider is first read).
final customModesStoreProvider =
    ChangeNotifierProvider<CustomModesStore>((ref) => CustomModesStore());

/// Optional Jina Reader key + the URL→markdown reader (external context sources).
final jinaKeyStoreProvider = Provider<JinaKeyStore>((ref) => JinaKeyStore());
final webReaderProvider =
    Provider<WebReader>((ref) => WebReader(ref.read(jinaKeyStoreProvider)));

/// Whether an (optional) Jina key is stored. Invalidate after save/clear.
final jinaHasKeyProvider =
    FutureProvider<bool>((ref) => ref.read(jinaKeyStoreProvider).hasKey());

/// Per-note chat session, keyed by note id. Created lazily — only when the chat
/// (or an incoming OCR/context anchor) first reads it, NOT on every editor build.
/// NOT autoDispose → once created, the session (and its in-memory messages) lives
/// for the whole app run, so leaving the note/pizarra/cuaderno view and coming
/// back keeps the conversation. Only a full app close (process death) clears the
/// messages — they're in-memory; the context anchor is persisted separately
/// (SharedPreferences). The chat sheet is just a window over it.
final aiSessionProvider =
    Provider.family<AiChatSession, int>((ref, noteId) {
  final session = AiChatSession(noteId);
  ref.onDispose(session.dispose);
  return session;
});

/// Local daily request cap (150/day). See [AiUsageLimiter].
final aiUsageLimiterProvider =
    Provider<AiUsageLimiter>((ref) => const AiUsageLimiter(dailyLimit: 150));

final aiAssistantProvider = Provider<AiAssistant>(
    (ref) => DeepseekAssistant(ref.read(aiKeyStoreProvider)));

/// Whether a DeepSeek API key is stored → gates the AI feature in the UI.
/// Invalidate after the user saves/clears the key in Settings.
final aiHasKeyProvider =
    FutureProvider<bool>((ref) => ref.read(aiKeyStoreProvider).hasKey());
