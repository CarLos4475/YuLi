import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_math_fork/flutter_math.dart';
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

  testWidgets('format toolbar applies markdown block prefixes', (tester) async {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [paragraphNode(delta: Delta()..insert('Titulo'))],
        ),
      ),
    );
    state.selection = Selection.collapsed(Position(path: const [0], offset: 6));

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
    await tester.tap(find.text('H1'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      state.document.root.children.single.delta?.toPlainText(),
      '# Titulo',
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

  testWidgets('format toolbar preserves selection and requests focus', (
    tester,
  ) async {
    final document = YuliMarkdownDocument.decode('''
| A | B |
| --- | --- |
| Uno | Dos |
''');
    final state = EditorState(document: document);
    final selection = Selection.single(
      path: const [0],
      startOffset: 0,
      endOffset: 1,
    );
    var focusRequests = 0;
    state.selection = selection;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormatToolbar(
            editorState: state,
            accent: const Color(0xFF2D3F8C),
            onRequestFocus: () => focusRequests++,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(YuLiIcons.textAlignCenter));
    await tester.pumpAndSettle();

    expect(state.selection, selection);
    expect(focusRequests, greaterThanOrEqualTo(2));
    state.dispose();
  });

  testWidgets('tapping a table selects its atomic node and keeps focus', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? state;
    FocusNode? focusNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '''
| A | B |
| --- | --- |
| Uno | Dos |
''',
                ),
                accent: const Color(0xFF2D3F8C),
                onFocusChanged: (editorState, node) {
                  state = editorState;
                  focusNode = node;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('yuli_atomic_table_0')));
    await tester.pumpAndSettle();

    expect(state?.selection?.start.path, [0]);
    expect(state?.selection?.start.offset, 0);
    expect(state?.selection?.end.offset, 1);
    expect(focusNode?.hasFocus, isTrue);
  });

  testWidgets('tapping an image selects its atomic node and keeps focus', (
    tester,
  ) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? state;
    FocusNode? focusNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '![Imagen](C:\\notes\\missing.png)',
                ),
                accent: const Color(0xFF2D3F8C),
                onFocusChanged: (editorState, node) {
                  state = editorState;
                  focusNode = node;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('yuli_atomic_image_0')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(state?.selection?.start.path, [0]);
    expect(state?.selection?.start.offset, 0);
    expect(state?.selection?.end.offset, 1);
    expect(focusNode?.hasFocus, isTrue);
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

  testWidgets('inline and display latex render as Math while inactive', (
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
              width: 360,
              child: YuliLiveTextEditor(
                block: TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: 'Inline \$1=1\$\n\$\$\nx^2\n\$\$',
                ),
                accent: Color(0xFF2D3F8C),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsNWidgets(2));
    expect(find.text('LATEX'), findsNothing);
    expect(_renderedSpans(tester).any((span) => span.text == r'$$'), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('multiple inline formulas render together without offset spans', (
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
              width: 360,
              child: YuliLiveTextEditor(
                block: TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: r'Hola $1+2$ y $1*3$',
                ),
                accent: Color(0xFF2D3F8C),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsNWidgets(2));
    expect(_renderedSpans(tester).where((span) => span.text == r'$'), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('latex returns to editable source inside its domain', (
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
              width: 360,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: 'Formula \$1=1\$',
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
    expect(find.byType(Math), findsOneWidget);

    await tester.tap(find.byType(Math), warnIfMissed: false);
    await tester.pumpAndSettle();
    state!.selection = Selection.collapsed(
      Position(path: const [0], offset: 10),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsNothing);
    final dollars =
        _renderedSpans(tester).where((span) => span.text == r'$').toList();
    expect(dollars, hasLength(2));
    expect(dollars.every((span) => span.style?.fontSize != 0), isTrue);
  });

  testWidgets('inline latex keeps body size and paragraph alignment', (
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
              width: 360,
              child: YuliLiveTextEditor(
                block: TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: r'Hola $1+2$',
                ),
                accent: Color(0xFF2D3F8C),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final math = tester.widget<Math>(find.byType(Math));
    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((widget) => _containsWidgetSpan(widget.text));

    expect(math.textStyle?.fontSize, 16);
    expect(richText.textAlign, TextAlign.left);
    expect(tester.getSize(find.byWidget(richText)).width, greaterThan(320));
  });

  testWidgets('table requires explicit cell edit mode', (tester) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? state;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '''
| A | B |
| --- | --- |
| Uno | Dos |
''',
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

    await tester.tap(find.byKey(const ValueKey('yuli_atomic_table_0')));
    await tester.pumpAndSettle();
    expect(find.text('EDITAR CELDAS'), findsOneWidget);
    expect(state?.selection?.start.path, [0]);

    await tester.tap(find.text('EDITAR CELDAS'));
    await tester.pumpAndSettle();
    expect(find.text('TERMINAR'), findsOneWidget);

    await tester.tap(find.byType(ParagraphBlockComponentWidget).at(2));
    await tester.pump();
    tester.testTextInput.enterText('Editable');
    await tester.pumpAndSettle();

    expect(state?.selection?.start.path.length, greaterThan(1));
    expect(YuliMarkdownDocument.encode(state!.document), contains('Editable'));
  });

  testWidgets('table header exposes row and column controls', (tester) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? state;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: StatefulBuilder(
                builder:
                    (_, setHostState) => YuliLiveTextEditor(
                      block: const TextBlock(
                        id: 1,
                        noteId: 1,
                        position: 0,
                        markdown: '''
| A | B |
| --- | --- |
| Uno | Dos |
''',
                      ),
                      accent: const Color(0xFF2D3F8C),
                      onFocusChanged:
                          (editorState, _) =>
                              setHostState(() => state = editorState),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('yuli_atomic_table_0')));
    await tester.pumpAndSettle();
    expect(find.text('FILA +'), findsOneWidget);
    expect(find.text('FILA -'), findsOneWidget);
    expect(find.text('COL +'), findsOneWidget);
    expect(find.text('COL -'), findsOneWidget);

    final table = state!.document.root.children.single;
    final initialRows = table.attributes[TableBlockKeys.rowsLen] as int;
    final initialCols = table.attributes[TableBlockKeys.colsLen] as int;

    await tester.tap(find.text('FILA +'));
    await tester.pumpAndSettle();
    expect(table.attributes[TableBlockKeys.rowsLen], initialRows + 1);

    await tester.tap(find.text('COL +'));
    await tester.pumpAndSettle();
    expect(table.attributes[TableBlockKeys.colsLen], initialCols + 1);

    await tester.tap(find.text('FILA -'));
    await tester.pumpAndSettle();
    expect(table.attributes[TableBlockKeys.rowsLen], initialRows);

    await tester.tap(find.text('COL -'));
    await tester.pumpAndSettle();
    expect(table.attributes[TableBlockKeys.colsLen], initialCols);
  });

  testWidgets('image node has a compact editor for url size and alignment', (
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
              width: 420,
              child: StatefulBuilder(
                builder:
                    (_, setHostState) => YuliLiveTextEditor(
                      block: const TextBlock(
                        id: 1,
                        noteId: 1,
                        position: 0,
                        markdown: '![Imagen](C:\\notes\\missing.png)',
                      ),
                      accent: const Color(0xFF2D3F8C),
                      debugPickImagePath: () async => 'C:\\notes\\updated.png',
                      onFocusChanged:
                          (editorState, _) =>
                              setHostState(() => state = editorState),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('yuli_atomic_image_0')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('EDITAR'), findsOneWidget);
    expect(find.text('IZQ'), findsOneWidget);
    expect(find.text('CENTRO'), findsOneWidget);
    expect(find.text('DER'), findsOneWidget);

    await tester.tap(find.text('EDITAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CAMBIAR IMAGEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PEQUEÑA'));
    await tester.pump();
    await tester.tap(find.text('DER'));
    await tester.pump();
    await tester.ensureVisible(find.text('GUARDAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final image = state!.document.root.children.single;
    expect(image.attributes[ImageBlockKeys.url], 'C:\\notes\\updated.png');
    expect(image.attributes[ImageBlockKeys.width], 180.0);
    expect(image.attributes[ImageBlockKeys.align], 'right');
  });

  testWidgets('block latex edits without exposing dollar markers', (
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
              width: 420,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '\$\$\nx^2\n\$\$',
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

    expect(find.text(r'$$'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('yuli_atomic_latex_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EDITAR'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), r'\frac{1}{2}');
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    expect(
      state?.document.root.children.single.attributes[yuliLatexBlockContent],
      r'\frac{1}{2}',
    );
    expect(
      YuliMarkdownDocument.encode(state!.document),
      contains('\$\$\n\\frac{1}{2}\n\$\$'),
    );
  });

  testWidgets('code block uses compact atomic editing flow', (tester) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? state;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '```dart\nfinal value = 1;\n```',
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

    expect(find.textContaining('```'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('yuli_atomic_code_0')));
    await tester.pumpAndSettle();
    expect(find.text('EDITAR'), findsOneWidget);

    await tester.tap(find.text('EDITAR'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'type');
    await tester.pump();
    await tester.tap(find.text('TYPESCRIPT'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).last,
      'const value = 2;\nconsole.log(value);',
    );
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final code = state!.document.root.children.single;
    expect(code.attributes['language'], 'ts');
    expect(code.delta?.toPlainText(), contains('console.log'));
    expect(YuliMarkdownDocument.encode(state!.document), contains('```ts'));
  });

  testWidgets('code block preview applies syntax highlight', (tester) async {
    final repository = _FakeNoteBlockRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: const Scaffold(
            body: SizedBox(
              width: 420,
              child: YuliLiveTextEditor(
                block: TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '```dart\nfinal value = "Hola";\n```',
                ),
                accent: Color(0xFF2D3F8C),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('```'), findsNothing);
    final highlight = tester.widget<HighlightView>(find.byType(HighlightView));
    expect(highlight.language, 'dart');
    expect(highlight.source, contains('final value'));
  });

  testWidgets('list and task markdown render visually while inactive', (
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
              width: 420,
              child: YuliLiveTextEditor(
                block: TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '- Uno\n- [ ] Pendiente',
                ),
                accent: Color(0xFF2D3F8C),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('- Uno'), findsNothing);
    expect(find.textContaining('- [ ]'), findsNothing);
    expect(find.text('•'), findsOneWidget);
    expect(find.byIcon(YuLiIcons.square), findsOneWidget);
  });

  testWidgets('last atomic node offers a following paragraph', (tester) async {
    final repository = _FakeNoteBlockRepository();
    EditorState? state;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteBlockRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: YuliLiveTextEditor(
                block: const TextBlock(
                  id: 1,
                  noteId: 1,
                  position: 0,
                  markdown: '\$\$\nx^2\n\$\$',
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

    await tester.tap(find.byKey(const ValueKey('yuli_continue_writing')));
    await tester.pumpAndSettle();

    expect(state?.document.root.children, hasLength(2));
    expect(state?.document.root.children.last.type, ParagraphBlockKeys.type);
    expect(state?.selection?.start.path, [1]);
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

bool _containsWidgetSpan(InlineSpan span) {
  if (span is WidgetSpan) return true;
  if (span is! TextSpan) return false;
  return span.children?.any(_containsWidgetSpan) ?? false;
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
