import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/data/services/ai_key_store.dart';
import 'package:yuli/data/services/deepseek_assistant.dart';
import 'package:yuli/domain/services/ai_assistant.dart';

void main() {
  test('vision flash sends text and images in one user message', () async {
    final directory = await Directory.systemTemp.createTemp('yuli_vision_test');
    final file = File('${directory.path}/sample.jpg');
    final secondFile = File('${directory.path}/sample-2.jpg');
    await file.writeAsBytes([1, 2, 3, 4]);
    await secondFile.writeAsBytes([5, 6, 7, 8]);
    Map<String, dynamic>? requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        'data: {"choices":[{"delta":{"content":"Listo"}}]}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final assistant = DeepseekAssistant(_FakeAiKeyStore(), client: client);

    final result =
        await assistant.streamReply([
          AiMessage(
            AiRole.user,
            'Describe la imagen',
            images: [
              AiImageInput(path: file.path, mediaType: 'image/jpeg'),
              AiImageInput(path: secondFile.path, mediaType: 'image/jpeg'),
            ],
          ),
        ]).join();

    expect(result, 'Listo');
    expect(requestBody?['model'], 'deepseek-v4-flash-vision-exp');
    expect(requestBody?['thinking'], {'type': 'disabled'});
    expect(requestBody?.containsKey('reasoning_effort'), isFalse);
    expect(requestBody?['stream_options'], {'include_usage': true});
    final messages = requestBody?['messages'] as List;
    final content = (messages.single as Map)['content'] as List;
    expect(content.first, {'type': 'text', 'text': 'Describe la imagen'});
    expect(content[1], {
      'type': 'image_url',
      'image_url': {'url': 'data:image/jpeg;base64,AQIDBA==', 'detail': 'auto'},
    });
    expect(content[2], {
      'type': 'image_url',
      'image_url': {'url': 'data:image/jpeg;base64,BQYHCA==', 'detail': 'auto'},
    });

    await directory.delete(recursive: true);
  });

  test('stream reports when the provider stops because of length', () async {
    final client = MockClient((_) async {
      return http.Response(
        'data: {"choices":[{"delta":{"content":"Parcial"},'
        '"finish_reason":null}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final assistant = DeepseekAssistant(_FakeAiKeyStore(), client: client);

    final events =
        await assistant.streamReplyEvents([
          const AiMessage(AiRole.user, 'Explica'),
        ]).toList();

    expect(events.whereType<AiTextDelta>().single.text, 'Parcial');
    expect(events.whereType<AiStreamComplete>().single.truncated, isTrue);
    expect(events.whereType<AiStreamComplete>().single.finishReason, 'length');
  });

  test('deep reasoning is explicit and reports safe token metrics', () async {
    Map<String, dynamic>? requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        'data: {"choices":[{"delta":{"reasoning_content":"Analisis"},'
        '"finish_reason":null}],"usage":null}\n\n'
        'data: {"choices":[{"delta":{"content":"Respuesta"},'
        '"finish_reason":null}],"usage":null}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],'
        '"usage":{"prompt_tokens":120,"prompt_cache_hit_tokens":96,'
        '"prompt_cache_miss_tokens":24,"completion_tokens":40,'
        '"completion_tokens_details":{"reasoning_tokens":18}}}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final assistant = DeepseekAssistant(_FakeAiKeyStore(), client: client);

    final events =
        await assistant.streamReplyEvents([
          const AiMessage(AiRole.user, 'Analiza'),
        ], deepReasoning: true).toList();

    expect(requestBody?['thinking'], {'type': 'enabled'});
    expect(requestBody?['reasoning_effort'], 'high');
    expect(events.whereType<AiReasoningDelta>().single.text, 'Analisis');
    expect(events.whereType<AiTextDelta>().single.text, 'Respuesta');
    final complete = events.whereType<AiStreamComplete>().single;
    expect(complete.finishReason, 'stop');
    expect(complete.usage?.promptCacheHitTokens, 96);
    expect(complete.usage?.promptCacheMissTokens, 24);
    expect(complete.usage?.reasoningTokens, 18);
  });
}

class _FakeAiKeyStore extends AiKeyStore {
  @override
  Future<String?> read() async => 'test-key';
}
