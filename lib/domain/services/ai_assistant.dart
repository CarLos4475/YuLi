/// Chat roles, mirroring the OpenAI/DeepSeek message schema. [tool] carries a
/// function-call result back to the model (paired with a prior assistant turn
/// that requested it via [AiMessage.toolCalls]).
enum AiRole { system, user, assistant, tool }

class AiImageInput {
  final String path;
  final String mediaType;

  const AiImageInput({required this.path, required this.mediaType});
}

const kMaxAiImagesPerMessage = 4;

class AiMessage {
  final AiRole role;
  final String content;
  final List<AiImageInput> images;
  final String? reasoningContent;

  /// Assistant turn requesting one or more tool calls (function calling).
  final List<AiToolCall>? toolCalls;

  /// For [AiRole.tool] messages: the id of the call this answers + the tool name.
  final String? toolCallId;
  final String? name;

  const AiMessage(
    this.role,
    this.content, {
    this.images = const [],
    this.reasoningContent,
    this.toolCalls,
    this.toolCallId,
    this.name,
  });
}

/// A tool the model may call. [parameters] is a JSON-schema object describing the
/// arguments. Serialized into the OpenAI `tools` array.
class AiToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const AiToolDef({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

/// A function call requested by the model. [arguments] is a raw JSON string.
class AiToolCall {
  final String id;
  final String name;
  final String arguments;

  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// Streaming events from a tool-aware turn: either a text delta to render, or a
/// batch of tool calls the caller must execute and feed back.
sealed class AiStreamEvent {
  const AiStreamEvent();
}

class AiTextDelta extends AiStreamEvent {
  final String text;
  const AiTextDelta(this.text);
}

class AiReasoningDelta extends AiStreamEvent {
  final String text;
  const AiReasoningDelta(this.text);
}

class AiTokenUsage {
  final int promptTokens;
  final int promptCacheHitTokens;
  final int promptCacheMissTokens;
  final int completionTokens;
  final int reasoningTokens;

  const AiTokenUsage({
    required this.promptTokens,
    required this.promptCacheHitTokens,
    required this.promptCacheMissTokens,
    required this.completionTokens,
    required this.reasoningTokens,
  });
}

class AiStreamComplete extends AiStreamEvent {
  final bool truncated;
  final String? finishReason;
  final AiTokenUsage? usage;

  const AiStreamComplete({
    this.truncated = false,
    this.finishReason,
    this.usage,
  });
}

class AiToolCallRequest extends AiStreamEvent {
  final List<AiToolCall> calls;
  const AiToolCallRequest(this.calls);
}

/// DeepSeek model tier. [flash] = cheap/fast (default chat, light tasks);
/// [pro] = heavier reasoning.
enum AiModel { flash, pro }

/// Streaming chat assistant.
abstract class AiAssistant {
  /// Stream the assistant's reply token-by-token for [messages].
  /// [maxTokens] caps each reply's length/cost.
  /// Throws [AiException] on missing key / network / API errors.
  Stream<String> streamReply(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
    bool deepReasoning = false,
  });

  Stream<AiStreamEvent> streamReplyEvents(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
    bool deepReasoning = false,
  }) async* {
    await for (final text in streamReply(
      messages,
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
      deepReasoning: deepReasoning,
    )) {
      yield AiTextDelta(text);
    }
    yield const AiStreamComplete();
  }

  /// Like [streamReply] but with function calling: the model may emit text
  /// (as [AiTextDelta]) and/or request [tools] (as [AiToolCallRequest] at the
  /// end of the turn). The caller runs the tools and re-invokes with the results
  /// appended as [AiRole.tool] messages, looping until no more calls are made.
  Stream<AiStreamEvent> streamReplyWithTools(
    List<AiMessage> messages, {
    required List<AiToolDef> tools,
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
    bool deepReasoning = false,
  });
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
