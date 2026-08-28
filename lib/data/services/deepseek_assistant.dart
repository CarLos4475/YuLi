import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/services/ai_assistant.dart';
import 'ai_key_store.dart';

/// DeepSeek chat assistant (OpenAI-compatible, streaming SSE). The API key is
/// read from [AiKeyStore] per request and used only in the Authorization
/// header — never logged or persisted elsewhere.
class DeepseekAssistant implements AiAssistant {
  final AiKeyStore keyStore;
  final http.Client _client;

  DeepseekAssistant(this.keyStore, {http.Client? client})
    : _client = client ?? http.Client();

  // Documented OpenAI-compatible path. Both `/chat/completions` and
  // `/v1/chat/completions` work; we use the documented `/v1` to be safe.
  static const _base = 'https://api.deepseek.com/v1';

  String _modelId(AiModel m) => switch (m) {
    AiModel.flash => 'deepseek-v4-flash-vision-exp',
    AiModel.pro => 'deepseek-v4-pro',
  };

  /// OpenAI-compatible message JSON, including tool-calling fields. A plain
  /// chat turn is just role+content; an assistant turn that requested tools
  /// carries `tool_calls`; a `tool` turn carries its `tool_call_id`.
  Future<Map<String, dynamic>> _msgJson(AiMessage m) async {
    if (m.role == AiRole.tool) {
      return {
        'role': 'tool',
        'tool_call_id': m.toolCallId ?? '',
        'content': m.content,
      };
    }
    if (m.toolCalls != null && m.toolCalls!.isNotEmpty) {
      return {
        'role': 'assistant',
        'content': m.content.isEmpty ? null : m.content,
        'tool_calls': [
          for (final c in m.toolCalls!)
            {
              'id': c.id,
              'type': 'function',
              'function': {'name': c.name, 'arguments': c.arguments},
            },
        ],
      };
    }
    if (m.images.isNotEmpty) {
      if (m.role != AiRole.user) {
        throw const AiException(
          'Las imágenes solo pueden enviarse en mensajes del usuario.',
        );
      }
      if (m.images.length > kMaxAiImagesPerMessage) {
        throw const AiException(
          'Solo puedes enviar hasta 4 imágenes a la vez.',
        );
      }
      final imageParts = <Map<String, dynamic>>[];
      var totalBytes = 0;
      for (final image in m.images) {
        final file = File(image.path);
        if (!await file.exists()) {
          throw const AiException('Una imagen adjunta ya no está disponible.');
        }
        final length = await file.length();
        if (length > 20 * 1024 * 1024) {
          throw const AiException('Una imagen adjunta es demasiado grande.');
        }
        totalBytes += length;
        if (totalBytes > 40 * 1024 * 1024) {
          throw const AiException(
            'Las imágenes adjuntas son demasiado grandes.',
          );
        }
        final encoded = base64Encode(await file.readAsBytes());
        imageParts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${image.mediaType};base64,$encoded',
            'detail': 'auto',
          },
        });
      }
      return {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': m.content},
          ...imageParts,
        ],
      };
    }
    return {'role': m.role.name, 'content': m.content};
  }

  @override
  Stream<String> streamReply(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async* {
    await for (final event in streamReplyEvents(
      messages,
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
    )) {
      if (event is AiTextDelta) yield event.text;
    }
  }

  @override
  Stream<AiStreamEvent> streamReplyEvents(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async* {
    final key = (await keyStore.read())?.trim();
    if (key == null || key.isEmpty) {
      throw const AiException('Falta la API key (configúrala en Ajustes).');
    }
    final messageJson = await Future.wait(messages.map(_msgJson));

    final req =
        http.Request('POST', Uri.parse('$_base/chat/completions'))
          ..headers['Authorization'] = 'Bearer $key'
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({
            'model': _modelId(model),
            'stream': true,
            'max_tokens': maxTokens,
            // Lower temperature → more deterministic (good for summarize/clean/
            // extract-tasks, less drift).
            'temperature': temperature,
            'messages': messageJson,
          });

    http.StreamedResponse resp;
    try {
      resp = await _client.send(req);
    } catch (_) {
      throw const AiException('Sin conexión o error de red.', retryable: true);
    }

    if (resp.statusCode != 200) {
      // Drain the body so we can map to a friendly message (never expose key).
      await resp.stream.drain<void>();
      // Transient: rate limit (429) and server errors (5xx) → retryable.
      final retryable = resp.statusCode == 429 || resp.statusCode >= 500;
      throw AiException(_friendlyError(resp.statusCode), retryable: retryable);
    }

    String? finishReason;
    await for (final line in resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final choice = choices.first as Map;
        final reason = choice['finish_reason'];
        if (reason is String && reason.isNotEmpty) finishReason = reason;
        final delta = choice['delta'] as Map?;
        final content = delta?['content'];
        if (content is String && content.isNotEmpty) {
          yield AiTextDelta(content);
        }
      } catch (_) {
        // Ignore keep-alive / malformed lines.
      }
    }
    yield AiStreamComplete(
      truncated: finishReason == 'length',
      finishReason: finishReason,
    );
  }

  @override
  Stream<AiStreamEvent> streamReplyWithTools(
    List<AiMessage> messages, {
    required List<AiToolDef> tools,
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async* {
    final key = (await keyStore.read())?.trim();
    if (key == null || key.isEmpty) {
      throw const AiException('Falta la API key (configúrala en Ajustes).');
    }
    final messageJson = await Future.wait(messages.map(_msgJson));

    final req =
        http.Request('POST', Uri.parse('$_base/chat/completions'))
          ..headers['Authorization'] = 'Bearer $key'
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({
            'model': _modelId(model),
            'stream': true,
            'max_tokens': maxTokens,
            'temperature': temperature,
            'messages': messageJson,
            'tools': tools.map((t) => t.toJson()).toList(),
            'tool_choice': 'auto',
          });

    http.StreamedResponse resp;
    try {
      resp = await _client.send(req);
    } catch (_) {
      throw const AiException('Sin conexión o error de red.', retryable: true);
    }
    if (resp.statusCode != 200) {
      await resp.stream.drain<void>();
      final retryable = resp.statusCode == 429 || resp.statusCode >= 500;
      throw AiException(_friendlyError(resp.statusCode), retryable: retryable);
    }

    // tool_calls stream in fragments keyed by `index`; assemble per index.
    final partial = <int, _PartialCall>{};
    String? finishReason;
    await for (final line in resp.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final choice = choices.first as Map;
        final reason = choice['finish_reason'];
        if (reason is String && reason.isNotEmpty) finishReason = reason;
        final delta = choice['delta'] as Map?;
        final content = delta?['content'];
        if (content is String && content.isNotEmpty) yield AiTextDelta(content);
        final tcs = delta?['tool_calls'] as List?;
        if (tcs != null) {
          for (final tc in tcs) {
            final m = tc as Map;
            final idx = (m['index'] as num?)?.toInt() ?? 0;
            final p = partial.putIfAbsent(idx, () => _PartialCall());
            if (m['id'] != null) p.id = m['id'] as String;
            final fn = m['function'] as Map?;
            if (fn != null) {
              if (fn['name'] != null) p.name = fn['name'] as String;
              if (fn['arguments'] != null) p.args.write(fn['arguments']);
            }
          }
        }
      } catch (_) {
        // Ignore keep-alive / malformed lines.
      }
    }

    yield AiStreamComplete(
      truncated: finishReason == 'length',
      finishReason: finishReason,
    );

    if (partial.isNotEmpty) {
      final keys = partial.keys.toList()..sort();
      yield AiToolCallRequest([
        for (final k in keys)
          AiToolCall(
            id: partial[k]!.id ?? 'call_$k',
            name: partial[k]!.name ?? '',
            arguments: partial[k]!.args.toString(),
          ),
      ]);
    }
  }

  String _friendlyError(int code) => switch (code) {
    401 => 'API key inválida (revísala en Ajustes).',
    402 => 'Sin saldo disponible para YuLi AI.',
    429 => 'Límite de uso alcanzado, intenta más tarde.',
    _ => 'Error de la API ($code).',
  };
}

/// Accumulator for one tool call streamed across SSE fragments.
class _PartialCall {
  String? id;
  String? name;
  final StringBuffer args = StringBuffer();
}
