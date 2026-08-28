import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/data/services/ai_key_store.dart';
import 'package:yuli/data/services/deepseek_assistant.dart';
import 'package:yuli/domain/services/ai_assistant.dart';

void main() {
  test('vision flash sends text and image in one user message', () async {
    final directory = await Directory.systemTemp.createTemp('yuli_vision_test');
    final file = File('${directory.path}/sample.jpg');
    await file.writeAsBytes([1, 2, 3, 4]);
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
            image: AiImageInput(path: file.path, mediaType: 'image/jpeg'),
          ),
        ]).join();

    expect(result, 'Listo');
    expect(requestBody?['model'], 'deepseek-v4-flash-vision-exp');
    final messages = requestBody?['messages'] as List;
    final content = (messages.single as Map)['content'] as List;
    expect(content.first, {'type': 'text', 'text': 'Describe la imagen'});
    expect(content.last, {
      'type': 'image_url',
      'image_url': {'url': 'data:image/jpeg;base64,AQIDBA==', 'detail': 'auto'},
    });

    await directory.delete(recursive: true);
  });
}

class _FakeAiKeyStore extends AiKeyStore {
  @override
  Future<String?> read() async => 'test-key';
}
