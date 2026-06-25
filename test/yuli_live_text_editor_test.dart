import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/domain/models/note_block.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/domain/models/folder.dart';
import 'package:yuli/domain/repositories/note_block_repository.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/screens/flight/format_toolbar.dart';
import 'package:yuli/presentation/screens/flight/note_block_widgets.dart';
import 'package:yuli/presentation/screens/flight/yuli_live_text_editor.dart';
import 'package:yuli/presentation/screens/flight/yuli_markdown_commands.dart';
import 'package:yuli/presentation/screens/flight/yuli_markdown_document.dart';
import 'package:yuli/presentation/theme/lab_icons.dart';

void main() {
  testWidgets('long text wraps without a horizontal editor scroll', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    final text = List.filled(100, 'palabra').join(' ');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: YuliLiveTextEditor(
                block: TextBlock(id: 1, noteId: 1, position: 0, markdown: text),
                accent: const Color(0xFF2D3F8C),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final horizontalScrolls = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((scroll) => scroll.scrollDirection == Axis.horizontal);
    expect(horizontalScrolls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap creates a selection and accepts keyboard input', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? activeState;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder:
                    (_, setHostState) => YuliLiveTextEditor(
                      block: const TextBlock(
                        id: 1,
                        noteId: 1,
                        position: 0,
                        markdown: '',
                      ),
                      accent: const Color(0xFF2D3F8C),
                      onFocusChanged:
                          (state, _) => setHostState(() => activeState = state),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(YuliLiveTextEditor));
    await tester.pump();

    expect(activeState?.selection, isNotNull);
    tester.testTextInput.enterText('Hola');
    await tester.pump();

    expect(
      activeState?.document.root.children.single.delta?.toPlainText(),
      'Hola',
    );
  });

  testWidgets('existing markdown remains editable and flushes on dispose', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? activeState;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: 'Texto anterior',
                ),
                accent: const Color(0xFF2D3F8C),
                onFocusChanged: (state, _) => activeState = state,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(YuliLiveTextEditor));
    await tester.pump();
    expect(activeState?.selection, isNotNull);

    tester.testTextInput.enterText('Texto editado');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(repository.lastPayload, {'md': 'Texto editado'});
  });

  testWidgets('autofocus activates a newly inserted text block', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? activeState;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 2,
                  noteId: 1,
                  position: 1,
                  markdown: '',
                ),
                accent: const Color(0xFF2D3F8C),
                autofocus: true,
                onFocusChanged: (state, _) => activeState = state,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(activeState?.selection, isNotNull);
    tester.testTextInput.enterText('Bloque nuevo');
    await tester.pump();

    expect(
      activeState?.document.root.children.single.delta?.toPlainText(),
      'Bloque nuevo',
    );
  });

  testWidgets('text remains interactive inside the reorderable block shell', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? activeState;
    final now = DateTime(2026);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: ReorderableListView(
              onReorder: (_, _) {},
              buildDefaultDragHandles: false,
              children: [
                BlockRouter(
                  key: const ValueKey('block_1'),
                  block: const TextBlock(
                    id: 1,
                    noteId: 1,
                    position: 0,
                    markdown: 'Contenido previo',
                  ),
                  note: Note(
                    id: 1,
                    folderId: 1,
                    rawMarkdown: '',
                    sizeBytes: 0,
                    createdAt: now,
                    updatedAt: now,
                  ),
                  folder: Folder(
                    id: 1,
                    name: 'Prueba',
                    color: const Color(0xFF2D3F8C),
                    createdAt: now,
                  ),
                  index: 0,
                  onTextBlockFocusChanged: (state, _) => activeState = state,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(YuliLiveTextEditor));
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('Contenido editable');
    await tester.pump();

    expect(
      activeState?.document.root.children.single.delta?.toPlainText(),
      'Contenido editable',
    );
  });

  testWidgets('typing one markdown marker creates a visible pair', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? activeState;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '',
                ),
                accent: const Color(0xFF2D3F8C),
                autofocus: true,
                onFocusChanged: (state, _) => activeState = state,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.enterText('*');
    await tester.pumpAndSettle();

    expect(
      activeState?.document.root.children.single.delta?.toPlainText(),
      '**',
    );
    expect(activeState?.selection?.start.offset, 1);
  });

  testWidgets('format toolbar inserts literal bold syntax', (tester) async {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [paragraphNode(delta: Delta()..insert('Texto'))],
        ),
      ),
    );
    state.selection = Selection.single(
      path: const [0],
      startOffset: 0,
      endOffset: 5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormatToolbar(
            editorState: state,
            accent: const Color(0xFF2D3F8C),
          ),
        ),
      ),
    );
    await tester.tap(find.text('B'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      state.document.root.children.single.delta?.toPlainText(),
      '**Texto**',
    );
    state.dispose();
  });

  testWidgets('format toolbar aligns image nodes with their own attribute', (
    tester,
  ) async {
    final state = EditorState(
      document: Document(
        root: pageNode(children: [imageNode(url: 'image.png')]),
      ),
    );
    state.selection = Selection.collapsed(Position(path: const [0]));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormatToolbar(
            editorState: state,
            accent: const Color(0xFF2D3F8C),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(YuLiIcons.textAlignStart));
    await tester.pump();

    final image = state.document.root.children.single;
    expect(image.attributes[ImageBlockKeys.align], 'left');
    expect(image.attributes[blockComponentAlign], 'left');
    state.dispose();
  });

  testWidgets('format toolbar aligns table nodes', (tester) async {
    final document = YuliMarkdownDocument.decode('''
| A | B |
| --- | --- |
| Uno | Dos |
''');
    final state = EditorState(document: document);
    state.selection = Selection.collapsed(Position(path: const [0]));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormatToolbar(
            editorState: state,
            accent: const Color(0xFF2D3F8C),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(YuLiIcons.textAlignEnd));
    await tester.pump();

    expect(
      state.document.root.children.single.attributes[blockComponentAlign],
      'right',
    );
    state.dispose();
  });

  test('live style reapplies markdown after the paragraph base style', () {
    const accent = Color(0xFF2D3F8C);
    const base = TextStyle(fontWeight: FontWeight.w400);

    final bold = applyYuliLiveTextStyle(base, {
      AppFlowyRichTextKeys.bold: true,
    }, accent);
    final code = applyYuliLiveTextStyle(base, {
      AppFlowyRichTextKeys.code: true,
    }, accent);
    final heading = applyYuliLiveTextStyle(base, {yuliHeadingLevel: 1}, accent);

    expect(bold.fontWeight, FontWeight.w700);
    expect(code.fontFamily, isNotNull);
    expect(code.backgroundColor, isNotNull);
    expect(heading.fontSize, 28);
    expect(heading.fontWeight, FontWeight.w700);
  });

  testWidgets('existing markdown is styled in the rendered RichText', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              child: YuliLiveTextEditor(
                block: TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '# Titulo\nTexto **fuerte**',
                ),
                accent: Color(0xFF2D3F8C),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final spans = <TextSpan>[
      for (final richText in tester.widgetList<RichText>(find.byType(RichText)))
        ..._flattenSpans(richText.text),
    ];
    final title = spans.firstWhere((span) => span.text == 'Titulo');
    final bold = spans.firstWhere((span) => span.text == 'fuerte');
    final headingMarker = spans.firstWhere((span) => span.text == '# ');

    expect(title.style?.fontSize, 28);
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(bold.style?.fontWeight, FontWeight.w700);
    expect(headingMarker.style?.color, Colors.transparent);
    expect(headingMarker.style?.fontSize, 0);
  });

  testWidgets('inline markers follow the cursor domain within one line', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? state;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: 'Antes **fuerte** despues',
                ),
                accent: const Color(0xFF2D3F8C),
                onFocusChanged: (editorState, _) => state = editorState,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(YuliLiveTextEditor));
    await tester.pumpAndSettle();

    state!.selection = Selection.collapsed(
      Position(path: const [0], offset: 10),
    );
    await tester.pumpAndSettle();
    var markers =
        _renderedSpans(tester).where((span) => span.text == '**').toList();
    expect(markers, hasLength(2));
    expect(markers.every((span) => span.style?.fontSize != 0), isTrue);

    state!.selection = Selection.collapsed(
      Position(path: const [0], offset: 2),
    );
    await tester.pumpAndSettle();
    markers =
        _renderedSpans(tester).where((span) => span.text == '**').toList();
    expect(markers, hasLength(2));
    expect(markers.every((span) => span.style?.fontSize == 0), isTrue);
  });

  testWidgets('quote uses an accent bar and normal text', (tester) async {
    final repository = _FakeNoteBlockRepository();
    const accent = Color(0xFF2D3F8C);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              child: YuliLiveTextEditor(
                block: TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '> Una cita',
                ),
                accent: accent,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bars = tester.widgetList<Container>(find.byType(Container)).where((
      container,
    ) {
      return container.color == accent &&
          container.constraints?.minWidth == 4 &&
          container.constraints?.maxWidth == 4;
    });
    final spans = <TextSpan>[
      for (final richText in tester.widgetList<RichText>(find.byType(RichText)))
        ..._flattenSpans(richText.text),
    ];

    expect(bars, isNotEmpty);
    expect(
      spans.any(
        (span) =>
            span.text?.contains('Una cita') == true &&
            span.style?.fontStyle != FontStyle.italic,
      ),
      isTrue,
    );
  });

  testWidgets('markdown styling updates while typing without reopening', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? activeState;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '',
                ),
                accent: const Color(0xFF2D3F8C),
                autofocus: true,
                onFocusChanged: (state, _) => activeState = state,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.testTextInput.enterText('**fuerte**');
    await tester.pumpAndSettle();

    final operations =
        activeState!.document.root.children.single.delta!
            .toList()
            .whereType<TextInsert>()
            .toList();
    expect(
      operations.any(
        (operation) =>
            operation.text == 'fuerte' &&
            operation.attributes?[AppFlowyRichTextKeys.bold] == true,
      ),
      isTrue,
    );
  });
}

Iterable<TextSpan> _flattenSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _flattenSpans(child);
  }
}

List<TextSpan> _renderedSpans(WidgetTester tester) => [
  for (final richText in tester.widgetList<RichText>(find.byType(RichText)))
    ..._flattenSpans(richText.text),
];

class _FakeNoteBlockRepository implements NoteBlockRepository {
  Map<String, dynamic>? lastPayload;

  @override
  Future<void> delete(int blockId) async {}

  @override
  Future<List<NoteBlock>> getByNote(int noteId) async => const [];

  @override
  Future<NoteBlock> insertAfter(
    int noteId,
    int afterPosition,
    NoteBlockType type, {
    Map<String, dynamic> payload = const {},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NoteBlock> insertAtEnd(
    int noteId,
    NoteBlockType type, {
    Map<String, dynamic> payload = const {},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> reorder(int noteId, List<int> orderedIds) async {}

  @override
  Future<void> updatePayload(int blockId, Map<String, dynamic> payload) async {
    lastPayload = payload;
  }

  @override
  Stream<List<NoteBlock>> watchByNote(int noteId) =>
      Stream.value(const <NoteBlock>[]);
}
