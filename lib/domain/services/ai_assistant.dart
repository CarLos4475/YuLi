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
  /// Throws [AiException] on missing key / network / API errors.
  Stream<String> streamReply(List<AiMessage> messages,
      {AiModel model = AiModel.flash});
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}
