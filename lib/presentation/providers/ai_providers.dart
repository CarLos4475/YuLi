import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ai_key_store.dart';
import '../../data/services/ai_usage_limiter.dart';
import '../../data/services/deepseek_assistant.dart';
import '../../domain/services/ai_assistant.dart';
import '../screens/flight/ai_chat_session.dart';

final aiKeyStoreProvider = Provider<AiKeyStore>((ref) => AiKeyStore());

/// Per-note chat session, keyed by note id. autoDispose → lives while the
/// note/pizarra/cuaderno view keeps it alive (the screen watches it) and is
/// discarded when you leave that view. The chat sheet is just a window over it.
final aiSessionProvider =
    Provider.autoDispose.family<AiChatSession, int>((ref, noteId) {
  final session = AiChatSession();
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
