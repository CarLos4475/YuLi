import 'dart:async';
import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/services/ai_usage_limiter.dart';
import 'package:yuli/presentation/screens/flight/yuli_markdown_commands.dart';
import 'package:yuli/domain/models/note_block.dart';
import 'package:yuli/domain/services/ai_assistant.dart';
import 'package:yuli/domain/services/fast_typing.dart';
import 'package:yuli/presentation/screens/flight/yuli_block_actions.dart';
import 'package:yuli/presentation/screens/flight/yuli_markdown_document.dart';
import 'package:yuli/presentation/screens/flight/yuli_table_tools.dart';

String response(List<Map<String, Object>> edits) => jsonEncode({
  'blocks': [
    {'id': 0, 'edits': edits},
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent corrections reserve the last request only once', () async {
    SharedPreferences.setMockInitialValues({});
    const limiter = AiUsageLimiter(dailyLimit: 1);
    final results = await Future.wait([
      limiter.tryRecord(),
      limiter.tryRecord(),
    ]);
    expect(results.where((result) => result).length, 1);
    expect(await limiter.remaining(), 0);
  });

  test('code newline and tab preserve the block and indentation', () async {
    final state = EditorState(
      document: YuliMarkdownDocument.decode('```dart\n  value();\n```'),
    );
    final node = state.document.root.children.single;
    state.selection = Selection.collapsed(
      Position(path: node.path, offset: node.delta!.length),
    );
    yuliMarkdownCommandShortcuts
        .firstWhere((event) => event.key == 'YuLi code enter')
        .handler(state);
    await Future<void>.delayed(Duration.zero);
    expect(state.document.root.children.length, 1);
    expect(node.delta!.toPlainText(), '  value();\n  ');
    yuliMarkdownCommandShortcuts
        .firstWhere((event) => event.key == 'YuLi code tab')
        .handler(state);
    await Future<void>.delayed(Duration.zero);
    expect(node.delta!.toPlainText(), '  value();\n    ');
    state.dispose();
  });

  test('accepts typos but protects links code numbers and ambiguous matches', () {
    const source =
        'Los ususarios escriben rapdio `codgio` https://rapdio.com 123 gato gato';
    final result = FastTyping.validate(
      [source],
      response([
        {'before': 'ususarios', 'after': 'usuarios'},
        {'before': 'codgio', 'after': 'codigo'},
        {'before': 'rapdio', 'after': 'rápido'},
        {'before': '123', 'after': '124'},
        {'before': 'gato', 'after': 'pato'},
      ]),
    );
    expect(
      result.edits.single.map((edit) => edit.after),
      containsAll(['usuarios', 'rápido']),
    );
    expect(result.rejected, 3);
  });

  test('uses offsets to correct repeated and heavily mistyped words', () {
    const source = 'eel machine vcanazar eel computacuon';
    final result = FastTyping.validate(
      [source],
      response([
        {'start': 0, 'before': 'eel', 'after': 'el'},
        {'start': 12, 'before': 'vcanazar', 'after': 'avanzar'},
        {'start': 21, 'before': 'eel', 'after': 'el'},
        {'start': 25, 'before': 'computacuon', 'after': 'computación'},
      ]),
    );
    expect(result.rejected, 0);
    expect(result.edits.single, hasLength(4));
  });

  test(
    'uses occurrence without model-counted offsets and accepts fenced JSON',
    () {
      const source = '`rapdio` rapdio queda rapdio';
      final result = FastTyping.validate(
        [source],
        '''```json
{"blocks":[{"id":0,"edits":[{"before":"rapdio","after":"rápido","occurrence":1}]}]}
```''',
      );

      expect(result.rejected, 0);
      expect(result.edits.single.single.start, 22);
      expect(result.edits.single.single.after, 'rápido');
    },
  );

  test('prompt tells YuLi to fix strong but clear typing errors', () {
    expect(FastTyping.systemPrompt, contains('funncionando'));
    expect(FastTyping.systemPrompt, contains('vcanazar'));
    expect(FastTyping.systemPrompt, contains('occurrence'));
  });

  test('rejects rephrasing missing blocks and malformed responses', () {
    expect(FastTyping.plausibleTypo('rápido', 'veloz'), isFalse);
    expect(FastTyping.plausibleTypo('hola', 'hola mundo'), isFalse);
    expect(FastTyping.plausibleTypo('te clado', 'teclado'), isTrue);
    expect(
      () => FastTyping.validate(['Uno', 'Dos'], response([])),
      throwsA(isA<AiException>()),
    );
    expect(
      () => FastTyping.validate(['Uno'], 'Texto limpio'),
      throwsA(isA<AiException>()),
    );
  });

  test('does not use incomplete streamed responses', () async {
    final ai = _FakeAi()..truncated = true;
    ai.reply.complete(
      response([
        {'before': 'rapdio', 'after': 'rápido'},
      ]),
    );
    await expectLater(
      FastTyping(ai).correct(['rapdio']),
      throwsA(isA<AiException>()),
    );
  });

  test('manual correction preserves formatting and is reversible', () async {
    final paragraph = paragraphNode(
      delta: Delta()..insert('rapdio', attributes: {'bold': true}),
    );
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraph])),
    );
    final actions = YuliBlockActions(state)..toggle(paragraph);
    final ai = _FakeAi();
    ai.reply.complete(
      response([
        {'before': 'rapdio', 'after': 'rápido'},
      ]),
    );
    await actions.correct(ai, () async => true);
    expect(paragraph.delta!.toPlainText(), 'rápido');
    expect(paragraph.delta!.sliceAttributes(0)?['bold'], true);
    expect(ai.messages.last.content, contains('rapdio'));
    await actions.undoCorrection();
    expect(paragraph.delta!.toPlainText(), 'rapdio');
    actions.dispose();
    state.dispose();
  });

  test(
    'sends one existing text block even when it contains paragraphs',
    () async {
      final state = EditorState(
        document: YuliMarkdownDocument.decode(
          'eel machine vcanazar\n\ncomputacuon',
        ),
      );
      final actions = YuliBlockActions(state)..selectWholeBlock();
      final ai = _FakeAi();
      ai.reply.complete(
        response([
          {'start': 0, 'before': 'eel', 'after': 'el'},
          {'start': 12, 'before': 'vcanazar', 'after': 'avanzar'},
          {'start': 22, 'before': 'computacuon', 'after': 'computación'},
        ]),
      );
      await actions.correct(ai, () async => true);
      final payload =
          jsonDecode(ai.messages.last.content) as Map<String, dynamic>;
      expect(payload['blocks'], hasLength(1));
      expect(
        YuliMarkdownDocument.encode(state.document),
        'el machine avanzar\ncomputación',
      );
      actions.dispose();
      state.dispose();
    },
  );

  test('late correction cannot overwrite edits or removed blocks', () async {
    final state = EditorState(document: YuliMarkdownDocument.decode('rapdio'));
    final paragraph = state.document.root.children.single;
    final actions = YuliBlockActions(state)..toggle(paragraph);
    final ai = _FakeAi();
    final future = actions.correct(ai, () async => true);
    await Future<void>.delayed(Duration.zero);
    await state.apply(state.transaction..insertText(paragraph, 6, ' nuevo'));
    ai.reply.complete(
      response([
        {'before': 'rapdio', 'after': 'rápido'},
      ]),
    );
    await future;
    expect(paragraph.delta!.toPlainText(), 'rapdio nuevo');
    expect(actions.changes, isEmpty);
    actions.dispose();
    state.dispose();
  });

  test('cancel keeps text intact and excluded blocks never reach AI', () async {
    final state = EditorState(
      document: YuliMarkdownDocument.decode(
        'rapdio\n\n```dart\nsecretCode\n```\n\n![Imagen](secret.png)',
      ),
    );
    final actions = YuliBlockActions(state);
    for (final node in state.document.root.children) {
      actions.toggle(node);
    }
    expect(actions.eligible.length, 1);
    final ai = _FakeAi();
    final future = actions.correct(ai, () async => true);
    await Future<void>.delayed(Duration.zero);
    actions.cancel();
    ai.reply.complete(
      response([
        {'before': 'rapdio', 'after': 'rápido'},
      ]),
    );
    await future;
    expect(ai.messages.last.content, isNot(contains('secret')));
    expect(state.document.root.children.first.delta!.toPlainText(), 'rapdio');
    actions.dispose();
    state.dispose();
  });

  test(
    'moves nonadjacent blocks in order and undo restores the document',
    () async {
      final state = EditorState(
        document: YuliMarkdownDocument.decode('Uno\nDos\nTres\nCuatro'),
      );
      final nodes = state.document.root.children.toList();
      final actions =
          YuliBlockActions(state)
            ..toggle(nodes[0])
            ..toggle(nodes[2]);
      await actions.moveBefore(null);
      expect(
        YuliMarkdownDocument.encode(state.document),
        'Dos\nCuatro\nUno\nTres',
      );
      state.undoManager.undo();
      await Future<void>.delayed(Duration.zero);
      expect(
        YuliMarkdownDocument.encode(state.document),
        'Uno\nDos\nTres\nCuatro',
      );
      actions.dispose();
      state.dispose();
    },
  );

  test(
    'rich document payload retains widths and falls back after external edit',
    () {
      final document = YuliMarkdownDocument.decode(
        '| A | B |\n|---|---|\n| C | D |',
      );
      final table = document.root.children.single;
      TableNode(node: table).setColWidth(0, 270);
      final markdown = YuliMarkdownDocument.encode(document);
      final block = TextBlock(
        id: 1,
        noteId: 1,
        position: 0,
        markdown: markdown,
        document: document.toJson(),
      );
      final decoded =
          NoteBlock.fromPayload(
                id: 1,
                noteId: 1,
                position: 0,
                type: NoteBlockType.text,
                payload: block.payloadString,
              )
              as TextBlock;
      final restored = YuliMarkdownDocument.restore(
        decoded.markdown,
        decoded.document,
      );
      expect(
        TableNode(node: restored.root.children.single).getColWidth(0),
        270,
      );
      expect(block.copyWith(markdown: 'Nuevo').document, isNull);
      expect(
        YuliMarkdownDocument.encode(
          YuliMarkdownDocument.restore('Nuevo', block.document),
        ),
        'Nuevo',
      );
    },
  );

  test(
    'table clipboard supports quoted multiline cells and preserves neighbors',
    () {
      final values = yuliParseTableClipboard(
        '"Uno\nDos"\tTres\nCuatro\t"Cinco"\n',
      );
      expect(values, [
        ['Uno\nDos', 'Tres'],
        ['Cuatro', 'Cinco'],
      ]);
      final table =
          YuliMarkdownDocument.decode(
            '| A | B |\n|---|---|\n| C | D |',
          ).root.children.single;
      final result = yuliPasteTableCells(table, 1, 1, values);
      expect(
        yuliTableCell(result, 0, 0).children.first.delta!.toPlainText(),
        'A',
      );
      expect(
        yuliTableCell(result, 1, 1).children.first.delta!.toPlainText(),
        'Uno\nDos',
      );
      expect(result.attributes[TableBlockKeys.colsLen], 3);
      final reordered = yuliReorderTableAxis(result, TableDirection.col, 0, 2);
      expect(
        yuliTableCell(reordered, 0, 2).children.first.delta!.toPlainText(),
        'A',
      );
    },
  );
}

class _FakeAi extends AiAssistant {
  final reply = Completer<String>();
  List<AiMessage> messages = [];
  bool truncated = false;
  @override
  Stream<AiStreamEvent> streamReplyEvents(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
    bool deepReasoning = false,
  }) async* {
    this.messages = messages;
    yield AiTextDelta(await reply.future);
    yield AiStreamComplete(truncated: truncated);
  }

  @override
  Stream<String> streamReply(
    List<AiMessage> messages, {
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
    bool deepReasoning = false,
  }) => throw UnimplementedError();
  @override
  Stream<AiStreamEvent> streamReplyWithTools(
    List<AiMessage> messages, {
    required List<AiToolDef> tools,
    AiModel model = AiModel.flash,
    int maxTokens = 2048,
    double temperature = 0.3,
    bool deepReasoning = false,
  }) => throw UnimplementedError();
}
