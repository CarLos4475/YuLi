import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/services/ai_usage_limiter.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/domain/services/ai_assistant.dart';
import 'package:yuli/presentation/screens/flight/ai_chat_sheet.dart';
import 'package:yuli/presentation/screens/flight/ai_chat_session.dart';
import 'package:yuli/presentation/screens/flight/ai_chat_settings_dialog.dart';
import 'package:yuli/presentation/screens/flight/ai_chat_visuals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('savings is the default and survives serialization', () {
    const settings = AiChatSettings.savings();
    final decoded = AiChatSettings.fromJson(settings.toJson());

    expect(decoded, settings);
    expect(decoded.profile, AiChatProfile.savings);
    expect(decoded.model, AiModel.flash);
    expect(decoded.responseLength, AiResponseLength.brief);
    expect(decoded.historyDepth, AiHistoryDepth.recent);
    expect(decoded.includeImagesInHistory, isFalse);
    expect(decoded.useNoteContext, isTrue);
    expect(decoded.useRelatedSources, isFalse);
    expect(decoded.useTools, isFalse);
    expect(decoded.useInteractiveReplies, isFalse);
    expect(decoded.useMemory, isFalse);
    expect(decoded.useActionDrafts, isFalse);
  });

  test('chat dock keeps injected images until the composer takes them', () {
    final controller = AiChatDockController();
    const image = AiImageInput(
      path: 'temporary/lasso-selection.jpg',
      mediaType: 'image/jpeg',
    );

    const second = AiImageInput(
      path: 'temporary/lasso-selection-2.jpg',
      mediaType: 'image/jpeg',
    );
    controller.attachImages([image, second]);

    expect(controller.pendingImages, [image, second]);
    expect(controller.takeImages(), [image, second]);
    expect(controller.pendingImages, isEmpty);
    controller.dispose();
  });

  test('note chat settings are shared globally between sessions', () {
    final store = AiChatSettingsStore();
    final first = AiChatSession(81, settingsStore: store);
    final second = AiChatSession(82, settingsStore: store);
    final settings = const AiChatSettings.savings().copyWith(
      historyDepth: AiHistoryDepth.full,
      useRelatedSources: true,
      useTools: true,
    );

    first.setSettings(settings);

    expect(first.settings, settings);
    expect(second.settings, settings);
  });

  test(
    'clearing a conversation keeps context and returns attached images',
    () async {
      final session = AiChatSession(83)..setAnchor('CONTEXTO CONSERVADO');
      const image = AiImageInput(
        path: 'temporary/chat-image.jpg',
        mediaType: 'image/jpeg',
      );
      await session.send(
        _CapturingAssistant(),
        const AiUsageLimiter(dailyLimit: 50),
        'Pregunta puntual',
        images: [image],
      );

      final removedImages = session.clearConversation();

      expect(session.messages, isEmpty);
      expect(session.anchor, 'CONTEXTO CONSERVADO');
      expect(session.settings, const AiChatSettings.savings());
      expect(removedImages, [image]);
    },
  );

  testWidgets('thinking indicator renders and advances its animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: AiThinkingIndicator(accent: Color(0xFF2D3F8C))),
        ),
      ),
    );

    expect(find.text('Pensando'), findsNothing);
    expect(find.bySemanticsLabel('YuLi está pensando'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'savings caps output, keeps short history and omits related context',
    () async {
      final assistant = _CapturingAssistant();
      final session = AiChatSession(71);
      session.setSyncedContexts(primary: 'NOTA BASE', related: 'OTRA FUENTE');

      for (final prompt in ['Uno', 'Dos', 'Tres', 'Cuatro']) {
        await session.send(
          assistant,
          const AiUsageLimiter(dailyLimit: 50),
          prompt,
        );
      }

      expect(assistant.maxTokens, AiResponseLength.brief.maxTokens);
      expect(assistant.model, AiModel.flash);
      expect(
        assistant.messages.any((m) => m.content.contains('NOTA BASE')),
        isTrue,
      );
      expect(
        assistant.messages.any((m) => m.content.contains('OTRA FUENTE')),
        isFalse,
      );
      expect(assistant.messages.any((m) => m.content == 'Uno'), isFalse);
      expect(assistant.messages.any((m) => m.content == 'Dos'), isTrue);
      expect(assistant.messages.last.content, 'Cuatro');
    },
  );

  test(
    'enabled related context and detailed output reach the request',
    () async {
      final assistant = _CapturingAssistant();
      final session = AiChatSession(72);
      session.setSyncedContexts(primary: 'NOTA BASE', related: 'OTRA FUENTE');
      session.setSettings(
        const AiChatSettings.savings().copyWith(
          model: AiModel.pro,
          responseLength: AiResponseLength.detailed,
          useRelatedSources: true,
        ),
      );

      await session.send(
        assistant,
        const AiUsageLimiter(dailyLimit: 50),
        'Analiza',
      );

      expect(assistant.maxTokens, AiResponseLength.detailed.maxTokens);
      expect(assistant.model, AiModel.pro);
      expect(
        assistant.messages.any((m) => m.content.contains('OTRA FUENTE')),
        isTrue,
      );
    },
  );

  test(
    'response length policy is canonical and precedes the transcript',
    () async {
      for (final length in AiResponseLength.values) {
        final assistant = _CapturingAssistant();
        final session = AiChatSession(90 + length.index);
        session.setSettings(
          const AiChatSettings.savings().copyWith(responseLength: length),
        );

        await session.send(
          assistant,
          const AiUsageLimiter(dailyLimit: 50),
          'Explica el tema',
        );

        expect(assistant.messages.last.role, AiRole.user);
        expect(assistant.messages.last.content, 'Explica el tema');
        expect(
          assistant.messages[assistant.messages.length - 2].role,
          AiRole.system,
        );
        expect(
          assistant.messages[assistant.messages.length - 2].content,
          length.semanticInstruction,
        );

        await session.send(
          assistant,
          const AiUsageLimiter(dailyLimit: 50),
          'Continúa',
          knowledgeDocs: const ['DOCUMENTO DINÁMICO'],
        );
        final policyIndex = assistant.messages.indexWhere(
          (message) => message.content == length.semanticInstruction,
        );
        final previousTurnIndex = assistant.messages.indexWhere(
          (message) => message.content == 'Explica el tema',
        );
        final dynamicDocIndex = assistant.messages.indexWhere(
          (message) => message.content == 'DOCUMENTO DINÁMICO',
        );
        expect(policyIndex, greaterThan(0));
        expect(policyIndex, lessThan(dynamicDocIndex));
        expect(policyIndex, lessThan(previousTurnIndex));
        expect(assistant.messages.last.content, 'Continúa');
      }
    },
  );

  test(
    'a length finish keeps the partial answer and marks it incomplete',
    () async {
      final session = AiChatSession(94);

      await session.send(
        _TruncatedAssistant(),
        const AiUsageLimiter(dailyLimit: 50),
        'Respuesta larga',
      );

      final response = session.messages.last;
      expect(response.role, AiRole.assistant);
      expect(response.text, 'Parte útil de la respuesta');
      expect(response.truncated, isTrue);
    },
  );

  test(
    'image is sent with its flash turn but not repeated in history',
    () async {
      final assistant = _CapturingAssistant();
      final session = AiChatSession(75);
      const image = AiImageInput(
        path: 'temporary/image.jpg',
        mediaType: 'image/jpeg',
      );

      await session.send(
        assistant,
        const AiUsageLimiter(dailyLimit: 50),
        'Mira esta imagen',
        images: [image],
      );

      expect(assistant.messages.last.images, [image]);
      expect(
        session.messages.singleWhere((m) => m.role == AiRole.user).images,
        [image],
      );

      await session.send(
        assistant,
        const AiUsageLimiter(dailyLimit: 50),
        'Continúa',
      );

      final priorTurn = assistant.messages.singleWhere(
        (m) => m.content == 'Mira esta imagen',
      );
      expect(priorTurn.images, isEmpty);
      expect(assistant.messages.last.content, 'Continúa');
    },
  );

  test('enabled image history resends prior images with flash', () async {
    final assistant = _CapturingAssistant();
    final session = AiChatSession(95)..setSettings(
      const AiChatSettings.savings().copyWith(includeImagesInHistory: true),
    );
    const image = AiImageInput(
      path: 'temporary/image.jpg',
      mediaType: 'image/jpeg',
    );

    await session.send(
      assistant,
      const AiUsageLimiter(dailyLimit: 50),
      'Mira esta imagen',
      images: [image],
    );
    await session.send(
      assistant,
      const AiUsageLimiter(dailyLimit: 50),
      '¿Qué detalle ves?',
    );

    final priorTurn = assistant.messages.singleWhere(
      (message) => message.content == 'Mira esta imagen',
    );
    expect(priorTurn.images, [image]);
  });

  test(
    'empty length finish is retryable without inventing model text',
    () async {
      final session = AiChatSession(96);

      await session.send(
        _EmptyTruncatedAssistant(),
        const AiUsageLimiter(dailyLimit: 50),
        'Explica la imagen',
      );

      final response = session.messages.last;
      expect(response.text, 'No pude generar la respuesta.');
      expect(response.truncated, isTrue);
      expect(response.emptyTruncated, isTrue);
    },
  );

  test('internal retry stays hidden and resends source images', () async {
    final session = AiChatSession(97);
    const image = AiImageInput(
      path: 'temporary/image.jpg',
      mediaType: 'image/jpeg',
    );
    await session.send(
      _EmptyTruncatedAssistant(),
      const AiUsageLimiter(dailyLimit: 50),
      'Explica la imagen',
      images: [image],
    );
    final assistant = _CapturingAssistant();

    await session.send(
      assistant,
      const AiUsageLimiter(dailyLimit: 50),
      'Responde de nuevo a la petición anterior.',
      images: [image],
      displayUserMessage: false,
    );

    expect(session.messages.where((m) => m.role == AiRole.user), hasLength(1));
    expect(assistant.messages.last.images, [image]);
    expect(
      assistant.messages.any(
        (m) => m.content == 'No pude generar la respuesta.',
      ),
      isFalse,
    );
  });

  test('pro rejects image input before calling the assistant', () async {
    final assistant = _CapturingAssistant();
    final session = AiChatSession(
      76,
    )..setSettings(const AiChatSettings.savings().copyWith(model: AiModel.pro));

    await session.send(
      assistant,
      const AiUsageLimiter(dailyLimit: 50),
      'Mira esta imagen',
      images: const [
        AiImageInput(path: 'temporary/image.jpg', mediaType: 'image/jpeg'),
      ],
    );

    expect(assistant.messages, isEmpty);
    expect(session.messages, isEmpty);
  });

  testWidgets('dialog exposes profiles and returns the selected settings', (
    tester,
  ) async {
    AiChatMenuResult? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<AiChatMenuResult>(
                      context: context,
                      builder:
                          (_) => const AiChatSettingsDialog(
                            initial: AiChatSettings.savings(),
                            accent: Color(0xFF2D3F8C),
                            canSummarize: true,
                          ),
                    );
                  },
                  child: const Text('ABRIR'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    expect(find.text('CHAT Y CONSUMO'), findsOneWidget);
    expect(find.text('AHORRO'), findsOneWidget);
    expect(find.text('EQUILIBRADO'), findsOneWidget);
    expect(find.text('COMPLETO'), findsOneWidget);
    expect(
      find.text(
        'EL CUADRADO MARCA OPCIONES QUE PUEDEN AUMENTAR MUCHO EL GASTO',
      ),
      findsOneWidget,
    );
    expect(find.text('MÁS GASTO'), findsNWidgets(4));
    expect(find.text('RECORDAR IMÁGENES'), findsOneWidget);

    await tester.tap(find.text('EQUILIBRADO'));
    await tester.ensureVisible(find.text('CONTEXTO DE ESTA NOTA'));
    await tester.tap(find.text('CONTEXTO DE ESTA NOTA'));
    await tester.tap(find.text('APLICAR'));
    await tester.pumpAndSettle();

    expect(result?.settings.profile, AiChatProfile.custom);
    expect(result?.settings.useNoteContext, isFalse);
  });

  testWidgets('selector descriptions follow the selected values', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AiChatSettingsDialog(
              initial: AiChatSettings.savings(),
              accent: Color(0xFF2D3F8C),
              canSummarize: false,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Usa menos contexto y funciones para reducir el consumo.'),
      findsOneWidget,
    );
    expect(
      find.text('Genera respuestas cortas con el menor consumo.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Recuerda los últimos 2 intercambios y reduce el contexto enviado.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('EQUILIBRADO'));
    await tester.pump();

    expect(
      find.text('Equilibra contexto, calidad y consumo para el uso diario.'),
      findsOneWidget,
    );
    expect(
      find.text('Da el detalle suficiente con un consumo equilibrado.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Recuerda los últimos 4 intercambios para mantener más continuidad.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('PRO'));
    await tester.tap(find.text('PRO'));
    await tester.pump();
    expect(
      find.text(
        'Prioriza capacidad para tareas complejas y puede consumir más.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const ValueKey(AiHistoryDepth.full)));
    await tester.tap(find.byKey(const ValueKey(AiHistoryDepth.full)));
    await tester.pump();
    expect(
      find.text(
        'Recuerda todo el chat; las conversaciones largas consumen más contexto.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('dialog exposes the clear conversation action', (tester) async {
    AiChatMenuResult? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<AiChatMenuResult>(
                      context: context,
                      builder:
                          (_) => const AiChatSettingsDialog(
                            initial: AiChatSettings.savings(),
                            accent: Color(0xFF2D3F8C),
                            canSummarize: false,
                            canClearConversation: true,
                          ),
                    );
                  },
                  child: const Text('ABRIR'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LIMPIAR CONVERSACIÓN'));
    await tester.pumpAndSettle();

    expect(result?.clearConversation, isTrue);
    expect(result?.summarize, isFalse);
  });

  testWidgets('context label follows the host editor kind', (tester) async {
    Future<void> pumpKind(NoteKind kind) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AiChatSettingsDialog(
                initial: const AiChatSettings.savings(),
                accent: const Color(0xFF2D3F8C),
                canSummarize: false,
                hostKind: kind,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpKind(NoteKind.whiteboard);
    expect(find.text('CONTEXTO DE ESTA PIZARRA'), findsOneWidget);
    expect(find.text('CONTEXTO DE ESTA NOTA'), findsNothing);

    await pumpKind(NoteKind.notebook);
    expect(find.text('CONTEXTO DE ESTE CUADERNO'), findsOneWidget);
    expect(find.text('CONTEXTO DE ESTA PIZARRA'), findsNothing);
  });

  test('tool follow-up calls are counted against the daily limit', () async {
    final assistant = _ToolLoopAssistant();
    final session = AiChatSession(73);
    const limiter = AiUsageLimiter(dailyLimit: 50);

    await session.send(
      assistant,
      limiter,
      'Consulta',
      tools: const [
        AiToolDef(
          name: 'lookup',
          description: 'Consulta datos.',
          parameters: {'type': 'object', 'properties': <String, dynamic>{}},
        ),
      ],
      onToolCall: (_) async => '{"result":"ok"}',
    );

    expect(assistant.calls, 2);
    expect(await limiter.remaining(), 48);
  });

  test(
    'changing context access clears history from the next request',
    () async {
      final assistant = _CapturingAssistant();
      final session = AiChatSession(74);
      session.setAnchor('PRIVADO');
      await session.send(
        assistant,
        const AiUsageLimiter(dailyLimit: 50),
        'Primera pregunta',
      );

      session.setSettings(session.settings.copyWith(useNoteContext: false));

      expect(session.messages.where((m) => m.role == AiRole.user), isEmpty);
      expect(session.messages.single.text, contains('Contexto ajustado'));
    },
  );
}

class _CapturingAssistant extends AiAssistant {
  List<AiMessage> messages = const [];
  AiModel? model;
  int? maxTokens;

  @override
  Stream<String> streamReply(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async* {
    this.messages = List.of(messages);
    this.model = model;
    this.maxTokens = maxTokens;
    yield 'Listo';
  }

  @override
  Stream<AiStreamEvent> streamReplyWithTools(
    List<AiMessage> messages, {
    required List<AiToolDef> tools,
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async* {
    this.messages = List.of(messages);
    this.model = model;
    this.maxTokens = maxTokens;
    yield const AiTextDelta('Listo');
  }
}

class _ToolLoopAssistant extends _CapturingAssistant {
  int calls = 0;

  @override
  Stream<AiStreamEvent> streamReplyWithTools(
    List<AiMessage> messages, {
    required List<AiToolDef> tools,
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async* {
    calls++;
    if (calls == 1) {
      yield const AiToolCallRequest([
        AiToolCall(id: 'call_1', name: 'lookup', arguments: '{}'),
      ]);
      return;
    }
    yield const AiTextDelta('Listo');
  }
}

class _TruncatedAssistant extends _CapturingAssistant {
  @override
  Stream<AiStreamEvent> streamReplyEvents(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async* {
    yield const AiTextDelta('Parte útil de la respuesta');
    yield const AiStreamComplete(truncated: true, finishReason: 'length');
  }
}

class _EmptyTruncatedAssistant extends _CapturingAssistant {
  @override
  Stream<AiStreamEvent> streamReplyEvents(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async* {
    yield const AiStreamComplete(truncated: true, finishReason: 'length');
  }
}
