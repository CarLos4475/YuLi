/// Chat roles, mirroring the OpenAI/DeepSeek message schema.
enum AiRole { system, user, assistant }

class AiMessage {
  final AiRole role;
  final String content;
  const AiMessage(this.role, this.content);
}

/// DeepSeek model tier. [flash] = cheap/fast (default chat, light tasks);
/// [pro] = heavier reasoning.
enum AiModel { flash, pro }

/// Streaming chat assistant. **v2 is read-only**: it talks (and you copy); it
/// does not edit notes/tasks — those "apply" actions are v3.
abstract class AiAssistant {
  /// Stream the assistant's reply token-by-token for [messages].
  /// [maxTokens] caps each reply's length/cost.
  /// Throws [AiException] on missing key / network / API errors.
  Stream<String> streamReply(List<AiMessage> messages,
      {AiModel model = AiModel.flash, int maxTokens = 2048,
      double temperature = 0.3});
}

class AiException implements Exception {
  final String message;

  /// True for transient failures (network, 429, 5xx) where an automatic retry
  /// with backoff makes sense. False for permanent ones (bad key, no balance).
  final bool retryable;

  const AiException(this.message, {this.retryable = false});
  @override
  String toString() => message;
}
