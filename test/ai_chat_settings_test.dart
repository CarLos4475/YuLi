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
    expect(find.text('MÁS GASTO'), findsNWidgets(3));

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

class _CapturingAssistant implements AiAssistant {
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
