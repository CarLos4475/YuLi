import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_widget_contracts.dart';

void main() {
  group('AiWidgetParser', () {
    test('parses one widget with surrounding markdown', () {
      final parts = AiWidgetParser.parse(
        'Antes\n'
        '<!--YULI_WIDGET:QUIZ v=1\n'
        '{"question":"Q","options":[],"answer":"a"}\n'
        '-->\n'
        'Después',
      );

      expect(parts, hasLength(3));
      expect(parts[0], isA<AiWidgetTextPart>());
      expect(parts[1], isA<AiWidgetBlockPart>());
      expect(parts[2], isA<AiWidgetTextPart>());
      final widget = parts[1] as AiWidgetBlockPart;
      expect(widget.type, 'QUIZ');
      expect(widget.version, 1);
      expect(widget.data['question'], 'Q');
    });

    test('parses multiple widgets in order', () {
      final parts = AiWidgetParser.parse(
        '<!--YULI_WIDGET:QUIZ v=1\n'
        '{"question":"Q","options":[],"answer":"a"}-->'
        '<!--YULI_WIDGET:OPTIONS v=1\n'
        '{"title":"T","options":[]}-->',
      );

      expect(parts.whereType<AiWidgetBlockPart>().map((p) => p.type), [
        'QUIZ',
        'OPTIONS',
      ]);
    });

    test('keeps invalid json as text fallback', () {
      final parts = AiWidgetParser.parse(
        '<!--YULI_WIDGET:QUIZ v=1\n'
        '{bad json}-->',
      );

      expect(parts, hasLength(1));
      expect(parts.first, isA<AiWidgetTextPart>());
      expect(
        AiWidgetParser.hasWidgets(
          '<!--YULI_WIDGET:QUIZ v=1\n'
          '{bad json}-->',
        ),
        isFalse,
      );
    });

    test('ignores incomplete blocks', () {
      final text = 'Hola <!--YULI_WIDGET:QUIZ v=1 {"question":"Q"}';
      final parts = AiWidgetParser.parse(text);

      expect(parts, hasLength(1));
      expect(parts.first, isA<AiWidgetTextPart>());
    });

    test('parses bare widget blocks with trailing explanation', () {
      final parts = AiWidgetParser.parse(
        'Ahí va:\n'
        'YULI_WIDGET:LAB_CARD_DRAFT v=1\n'
        '{"title":"Investigar APIs","space":"Hello"}\n'
        'Eso sería un borrador.',
      );

      final widget = parts.whereType<AiWidgetBlockPart>().single;
      expect(widget.type, 'LAB_CARD_DRAFT');
      expect(widget.data['title'], 'Investigar APIs');
    });

    test('strips widget drafts while streaming', () {
      final visible = AiWidgetParser.stripStreamingWidgetDraft(
        'Ahí va:\n'
        'YULI_WIDGET:TASK_DRAFT v=1\n'
        '{"content":"Estudiar"}',
      );

      expect(visible, 'Ahí va:');
      expect(AiWidgetParser.isStreamingWidgetDraft(visible), isFalse);
    });
  });

  group('AiWidgetRetriever', () {
    const retriever = AiWidgetRetriever();

    test('retrieves quiz for study intent in Flight', () {
      final specs = retriever.retrieve(
        'Hazme un quiz de esta nota',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('QUIZ'));
    });

    test('retrieves concept card for explanation intent', () {
      final specs = retriever.retrieve(
        'Explicame que es una derivada',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('CONCEPT_CARD'));
    });

    test('retrieves steps for process intent', () {
      final specs = retriever.retrieve(
        'Explicame el proceso paso a paso',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('STEPS'));
    });

    test('retrieves comparison for compare intent', () {
      final specs = retriever.retrieve(
        'Compara derivada vs integral',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('COMPARISON'));
    });

    test('retrieves flashcards for review intent', () {
      final specs = retriever.retrieve(
        'Hazme flashcards para repasar',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('FLASHCARDS'));
    });

    test('retrieves checklist for study plan intent', () {
      final specs = retriever.retrieve(
        'Dame una checklist para preparar el examen',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('CHECKLIST'));
    });

    test('does not retrieve app data in Flight without explicit intent', () {
      final specs = retriever.retrieve(
        'Hazme una pregunta de opción múltiple',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), isNot(contains('TASK_LIST')));
    });

    test('retrieves task widgets in Flight with explicit Fight intent', () {
      final specs = retriever.retrieve(
        'Qué tareas pendientes tengo en Fight hoy',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('TASK_LIST'));
    });

    test('retrieves task draft for natural create task wording', () {
      final specs = retriever.retrieve(
        'Crea una tarea para mañana de estudiar límites',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('TASK_DRAFT'));
    });

    test('retrieves lab card draft for card wording', () {
      final specs = retriever.retrieve(
        'Crea una tarjeta en Lab para el proyecto Hello',
        surface: AiWidgetSurface.yuli,
      );

      expect(specs.map((s) => s.type), contains('LAB_CARD_DRAFT'));
    });

    test('global YuLi can retrieve memory suggestions proactively', () {
      final specs = retriever.retrieve(
        'Me llamo Dylan y estudio cálculo',
        surface: AiWidgetSurface.yuli,
      );

      expect(specs.map((s) => s.type), contains('MEMORY_SUGGESTION'));
    });

    test('retrieves memory suggestion for save that as memory wording', () {
      final specs = retriever.retrieve(
        'Guarda eso como memoria',
        surface: AiWidgetSurface.yuli,
      );

      expect(specs.map((s) => s.type), contains('MEMORY_SUGGESTION'));
    });

    test('retrieves memory suggestion proactively for user name', () {
      final specs = retriever.retrieve(
        'Mi nombre es Carlos por cierto',
        surface: AiWidgetSurface.yuli,
      );

      expect(specs.map((s) => s.type), contains('MEMORY_SUGGESTION'));
    });

    test('allows proactive memory suggestions in Flight', () {
      final specs = retriever.retrieve(
        'Prefiero que me hagas quizzes cortos',
        surface: AiWidgetSurface.flight,
      );

      expect(specs.map((s) => s.type), contains('MEMORY_SUGGESTION'));
    });
  });
}
