import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ai_key_store.dart';
import '../../data/services/ai_usage_limiter.dart';
import '../../data/services/deepseek_assistant.dart';
import '../../data/services/web_reader.dart';
import '../../domain/services/ai_assistant.dart';
import '../screens/flight/ai_chat_session.dart';

final aiKeyStoreProvider = Provider<AiKeyStore>((ref) => AiKeyStore());

/// Optional Jina Reader key + the URL→markdown reader (external context sources).
final jinaKeyStoreProvider = Provider<JinaKeyStore>((ref) => JinaKeyStore());
final webReaderProvider =
    Provider<WebReader>((ref) => WebReader(ref.read(jinaKeyStoreProvider)));

/// Whether an (optional) Jina key is stored. Invalidate after save/clear.
final jinaHasKeyProvider =
    FutureProvider<bool>((ref) => ref.read(jinaKeyStoreProvider).hasKey());

/// Per-note chat session, keyed by note id. autoDispose → lives while the
/// note/pizarra/cuaderno view keeps it alive (the screen watches it) and is
/// discarded when you leave that view. The chat sheet is just a window over it.
final aiSessionProvider =
    Provider.autoDispose.family<AiChatSession, int>((ref, noteId) {
  final session = AiChatSession(noteId);
  ref.onDispose(session.dispose);
  return session;
});

/// Per-LAB-space chat session (scope 'lab' → no collision with note sessions).
/// Context = the serialized board, set by the chat on open.
final aiLabSessionProvider =
    Provider.autoDispose.family<AiChatSession, int>((ref, labSpaceId) {
  final session = AiChatSession(labSpaceId, scope: 'lab');
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
