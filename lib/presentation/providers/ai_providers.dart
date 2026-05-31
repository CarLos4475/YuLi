import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ai_key_store.dart';
import '../../data/services/ai_usage_limiter.dart';
import '../../data/services/deepseek_assistant.dart';
import '../../domain/services/ai_assistant.dart';

final aiKeyStoreProvider = Provider<AiKeyStore>((ref) => AiKeyStore());

/// Local daily request cap (150/day). See [AiUsageLimiter].
final aiUsageLimiterProvider =
    Provider<AiUsageLimiter>((ref) => const AiUsageLimiter(dailyLimit: 150));

final aiAssistantProvider = Provider<AiAssistant>(
    (ref) => DeepseekAssistant(ref.read(aiKeyStoreProvider)));

/// Whether a DeepSeek API key is stored → gates the AI feature in the UI.
/// Invalidate after the user saves/clears the key in Settings.
final aiHasKeyProvider =
    FutureProvider<bool>((ref) => ref.read(aiKeyStoreProvider).hasKey());
