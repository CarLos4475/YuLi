import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/services/ai_memory_store.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_knowledge_contracts.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_widget_contracts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiKnowledgeRetriever', () {
    test('retrieves app overview without exposing internals', () {
      const retriever = AiKnowledgeRetriever();

      final docs = retriever.retrieve(
        'Que puedes hacer en esta app?',
        surface: AiKnowledgeSurface.yuli,
      );
      final prompt = aiKnowledgePrompt(docs, surface: AiKnowledgeSurface.yuli);

      expect(docs.map((d) => d.id), contains('yuli_overview'));
      expect(prompt, contains('No menciones tablas'));
      expect(prompt, contains('Fight'));
      expect(prompt, contains('Flight'));
      expect(prompt, contains('Lab'));
    });

    test('retrieves user-facing visual widget capabilities', () {
      const retriever = AiKnowledgeRetriever();

      final docs = retriever.retrieve(
        'Que widgets tienes en tu arsenal? puedes hacer quiz?',
        surface: AiKnowledgeSurface.flight,
      );
      final prompt = aiKnowledgePrompt(
        docs,
        surface: AiKnowledgeSurface.flight,
      );

      expect(docs.map((d) => d.id), contains('visual_widgets'));
      expect(prompt, contains('quiz interactivo'));
      expect(prompt, contains('No enumeres nombres internos'));
    });
  });

  group('AiMemoryStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves, dedupes and injects relevant confirmed memories', () async {
      const store = AiMemoryStore();

      await store.saveFromWidgetItem({
        'key': 'name',
        'label': 'Nombre',
        'value': 'Carlos',
        'scope': 'global',
      });
      await store.saveFromWidgetItem({
        'key': 'name',
        'label': 'Nombre',
        'value': 'Carlos',
        'scope': 'global',
      });

      final memories = await store.load();
      final prompt = await store.promptForTurn('Como me llamo?');

      expect(memories, hasLength(1));
      expect(prompt, contains('Nombre: Carlos'));
      expect(prompt, contains('<user_memory>'));
    });

    test('prunes expired temporary memories', () async {
      const store = AiMemoryStore();

      await store.saveFromWidgetItem({
        'key': 'task_context',
        'label': 'Pendiente temporal',
        'value': 'Tiene tarea manana',
        'scope': 'temp',
        'expiresAt': '2020-01-01T00:00:00',
      });

      expect(await store.load(), isEmpty);
      expect(await store.promptForTurn('tarea'), isEmpty);
    });
  });

  group('AiWidgetRetriever contextual triggers', () {
    test('uses recent context for vague follow up prompts', () {
      const retriever = AiWidgetRetriever();

      final specs = retriever.retrieve(
        'Haz uno interactivo',
        surface: AiWidgetSurface.flight,
        context: 'Estabamos repasando derivadas para examen y practica',
      );

      expect(specs.map((s) => s.type), contains('QUIZ'));
    });
  });
}
