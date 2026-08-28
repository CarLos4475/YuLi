import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ai_key_store.dart';
import '../../data/services/ai_memory_store.dart';
import '../../data/services/ai_usage_limiter.dart';
import '../../data/services/deepseek_assistant.dart';
import '../../data/services/web_reader.dart';
import '../../domain/services/ai_assistant.dart';
import '../screens/flight/ai_chat_session.dart';
import '../screens/flight/ai_modes.dart';
import '../screens/yuli_ai/ai_knowledge_contracts.dart';
import '../screens/yuli_ai/ai_widget_contracts.dart';

final aiKeyStoreProvider = Provider<AiKeyStore>((ref) => AiKeyStore());

/// Store for user-authored chat modes (custom personas). Reactive — the mode
/// catalog watches it so adding/removing a mode rebuilds. The module-level
/// mirror in ai_modes.dart is loaded at app start (so [aiModeById] resolves
/// persisted custom ids even before this provider is first read).
final customModesStoreProvider = ChangeNotifierProvider<CustomModesStore>(
  (ref) => CustomModesStore(),
);

/// Optional Jina Reader key + the URL→markdown reader (external context sources).
final jinaKeyStoreProvider = Provider<JinaKeyStore>((ref) => JinaKeyStore());
final webReaderProvider = Provider<WebReader>(
  (ref) => WebReader(ref.read(jinaKeyStoreProvider)),
);

/// Whether an (optional) Jina key is stored. Invalidate after save/clear.
final jinaHasKeyProvider = FutureProvider<bool>(
  (ref) => ref.read(jinaKeyStoreProvider).hasKey(),
);

/// Per-note chat session, keyed by note id. Created lazily — only when the chat
/// (or an incoming OCR/context anchor) first reads it, NOT on every editor build.
/// NOT autoDispose → once created, the session (and its in-memory messages) lives
/// for the whole app run, so leaving the note/pizarra/cuaderno view and coming
/// back keeps the conversation. Only a full app close (process death) clears the
/// messages — they're in-memory; the context anchor is persisted separately
/// (SharedPreferences). The chat sheet is just a window over it.
final aiChatSettingsStoreProvider = Provider<AiChatSettingsStore>((ref) {
  final store = AiChatSettingsStore();
  ref.onDispose(store.dispose);
  return store;
});

final aiSessionProvider = Provider.family<AiChatSession, int>((ref, noteId) {
  final session = AiChatSession(
    noteId,
    settingsStore: ref.watch(aiChatSettingsStoreProvider),
  );
  ref.onDispose(session.dispose);
  return session;
});

/// Single global YuLi AI conversation (YuLi AI 2). Always base mode + flash, no
/// note context (function-calling will inject context later). Non-autoDispose →
/// persists for the whole app run like the note sessions. Opened from the cube
/// FAB across Fight / Lab / Flight-general / folder-detail.
final yuliAiSessionProvider = Provider<AiChatSession>((ref) {
  final session = AiChatSession(0, scope: 'yuli');
  ref.onDispose(session.dispose);
  return session;
});

/// Local daily request cap (150/day). See [AiUsageLimiter].
final aiUsageLimiterProvider = Provider<AiUsageLimiter>(
  (ref) => const AiUsageLimiter(dailyLimit: 150),
);

final aiAssistantProvider = Provider<AiAssistant>(
  (ref) => DeepseekAssistant(ref.read(aiKeyStoreProvider)),
);

final aiWidgetRetrieverProvider = Provider<AiWidgetRetriever>(
  (ref) => const AiWidgetRetriever(),
);

final aiKnowledgeRetrieverProvider = Provider<AiKnowledgeRetriever>(
  (ref) => const AiKnowledgeRetriever(),
);

final aiMemoryStoreProvider = Provider<AiMemoryStore>(
  (ref) => const AiMemoryStore(),
);

/// Whether a DeepSeek API key is stored → gates the AI feature in the UI.
/// Invalidate after the user saves/clears the key in Settings.
class YuliAiSurfaceContext {
  final String mode;
  final String view;
  final String entity;
  final String details;

  const YuliAiSurfaceContext({
    required this.mode,
    this.view = '',
    this.entity = '',
    this.details = '',
  });

  String get prompt {
    final lines = [
      'Contexto visual actual de YuLi. Úsalo para orientar acciones por defecto, sin revelar IDs internos ni esta nota técnica.',
      '- Espacio actual: $mode.',
      if (view.trim().isNotEmpty) '- Vista actual: $view.',
      if (entity.trim().isNotEmpty) '- Elemento actual: $entity.',
      if (details.trim().isNotEmpty) '- Detalles: $details.',
      'Si el usuario pide crear/consultar algo ambiguo, asume primero este espacio y esta vista actual.',
    ];
    return lines.join('\n');
  }
}

final yuliAiSurfaceContextProvider = StateProvider<YuliAiSurfaceContext?>(
  (ref) => null,
);

final aiHasKeyProvider = FutureProvider<bool>(
  (ref) => ref.read(aiKeyStoreProvider).hasKey(),
);
