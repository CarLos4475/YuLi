import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ai_key_store.dart';
import '../../data/services/deepseek_assistant.dart';
import '../../domain/services/ai_assistant.dart';

final aiKeyStoreProvider = Provider<AiKeyStore>((ref) => AiKeyStore());

final aiAssistantProvider = Provider<AiAssistant>(
    (ref) => DeepseekAssistant(ref.read(aiKeyStoreProvider)));

/// Whether a DeepSeek API key is stored → gates the AI feature in the UI.
/// Invalidate after the user saves/clears the key in Settings.
final aiHasKeyProvider =
    FutureProvider<bool>((ref) => ref.read(aiKeyStoreProvider).hasKey());
