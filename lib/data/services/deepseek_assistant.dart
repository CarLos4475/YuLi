import 'dart:convert';

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
        AiModel.flash => 'deepseek-v4-flash',
        AiModel.pro => 'deepseek-v4-pro',
      };

  @override
  Stream<String> streamReply(List<AiMessage> messages,
      {AiModel model = AiModel.flash, int maxTokens = 1024}) async* {
    final key = (await keyStore.read())?.trim();
    if (key == null || key.isEmpty) {
      throw const AiException('Falta la API key (configúrala en Ajustes).');
    }

    final req = http.Request('POST', Uri.parse('$_base/chat/completions'))
      ..headers['Authorization'] = 'Bearer $key'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': _modelId(model),
        'stream': true,
        'max_tokens': maxTokens,
        // Lower temperature → more deterministic (good for summarize/clean/
        // extract-tasks, less drift).
        'temperature': 0.3,
        'messages': messages
            .map((m) => {'role': m.role.name, 'content': m.content})
            .toList(),
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
        final delta = (choices.first as Map)['delta'] as Map?;
        final content = delta?['content'];
        if (content is String && content.isNotEmpty) yield content;
      } catch (_) {
        // Ignore keep-alive / malformed lines.
      }
    }
  }

  String _friendlyError(int code) => switch (code) {
        401 => 'API key inválida (revísala en Ajustes).',
        402 => 'Sin saldo en la cuenta de DeepSeek.',
        429 => 'Límite de uso alcanzado, intenta más tarde.',
        _ => 'Error de la API ($code).',
      };
}
