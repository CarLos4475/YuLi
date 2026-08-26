import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/yuli_markdown_commands.dart';

void main() {
  test('pairing inserts delimiters and leaves the cursor inside', () async {
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode()])),
    );
    state.selection = Selection.collapsed(Position(path: const [0]));

    await pairMarkdownCharacter(state, '*');

    expect(state.document.root.children.single.delta?.toPlainText(), '**');
    expect(state.selection?.start.offset, 1);
  });

  test('typing the opener again grows a bold pair', () async {
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode()])),
    );
    final node = state.document.root.children.single;
    node.updateAttributes({
      blockComponentDelta: (Delta()..insert('**')).toJson(),
    });
    state.selection = Selection.collapsed(Position(path: const [0], offset: 1));

    await pairMarkdownCharacter(state, '*');

    expect(state.document.root.children.single.delta?.toPlainText(), '****');
    expect(state.selection?.start.offset, 2);
  });

  test('dollar pairing grows from inline to display latex', () async {
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode()])),
    );
    state.selection = Selection.collapsed(Position(path: const [0]));

    await pairMarkdownCharacter(state, r'$');
    await pairMarkdownCharacter(state, r'$');

    expect(state.document.root.children.single.delta?.toPlainText(), r'$$$$');
    expect(state.selection?.start.offset, 2);
  });

  test('toolbar wrapping keeps literal markdown around a selection', () async {
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

    await wrapMarkdownSelection(state, '**');

    expect(
      state.document.root.children.single.delta?.toPlainText(),
      '**Texto**',
    );
    expect(state.selection?.start.offset, 2);
    expect(state.selection?.end.offset, 7);
  });

  test('live styling preserves markers and styles only their content', () {
    final delta = buildLiveMarkdownDelta('# **Titulo** y `codigo`');
    final operations = delta.toList().whereType<TextInsert>().toList();

    expect(delta.toPlainText(), '# **Titulo** y `codigo`');
    expect(
      operations
          .where(
            (operation) => operation.attributes?[yuliMarkdownMarker] == true,
          )
          .map((operation) => operation.text)
          .join(),
      '# ****``',
    );
    expect(
      operations.any(
        (operation) =>
            operation.text == 'Titulo' &&
            operation.attributes?[AppFlowyRichTextKeys.bold] == true &&
            operation.attributes?[yuliHeadingLevel] == 1,
      ),
      isTrue,
    );
    expect(
      operations.any(
        (operation) =>
            operation.text == 'codigo' &&
            operation.attributes?[AppFlowyRichTextKeys.code] == true,
      ),
      isTrue,
    );
  });

  test('three stars remain text and never become a divider', () {
    final delta = buildLiveMarkdownDelta('***');

    expect(delta.toPlainText(), '***');
  });

  test('native divider shortcuts are disabled', () {
    expect(
      yuliMarkdownCharacterShortcuts,
      isNot(contains(convertMinusesToDivider)),
    );
    expect(
      yuliMarkdownCharacterShortcuts,
      isNot(contains(convertStarsToDivider)),
    );
    expect(
      yuliMarkdownCharacterShortcuts,
      isNot(contains(convertUnderscoreToDivider)),
    );
  });

  test('native formatting command shortcuts are disabled', () {
    expect(
      yuliMarkdownCommandShortcuts,
      isNot(contains(toggleTodoListCommand)),
    );
    for (final command in toggleMarkdownCommands) {
      expect(yuliMarkdownCommandShortcuts, isNot(contains(command)));
    }
    expect(
      yuliMarkdownCommandShortcuts.map((command) => command.key),
      isNot(contains('toggle into Heading 1')),
    );
    expect(
      yuliMarkdownCommandShortcuts.map((command) => command.key),
      isNot(contains('toggle into Heading 2')),
    );
    expect(
      yuliMarkdownCommandShortcuts.map((command) => command.key),
      isNot(contains('toggle into Heading 3')),
    );
    expect(
      yuliMarkdownCommandShortcuts.map((command) => command.key),
      isNot(contains('toggle Body')),
    );
    expect(
      yuliMarkdownCommandShortcuts,
      isNot(contains(toggleHighlightCommand)),
    );
    expect(yuliMarkdownCommandShortcuts, isNot(contains(showLinkMenuCommand)));
    expect(
      yuliMarkdownCommandShortcuts,
      isNot(contains(openInlineLinkCommand)),
    );
    expect(yuliMarkdownCommandShortcuts, isNot(contains(openLinksCommand)));
    expect(yuliMarkdownCommandShortcuts, isNot(contains(indentCommand)));
    expect(yuliMarkdownCommandShortcuts, isNot(contains(outdentCommand)));
    expect(yuliMarkdownCommandShortcuts, contains(undoCommand));
    expect(yuliMarkdownCommandShortcuts, contains(redoCommand));
  });

  test('YuLi command shortcuts insert markdown syntax', () async {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [paragraphNode(delta: Delta()..insert('Hola'))],
        ),
      ),
    );
    state.selection = Selection.single(
      path: const [0],
      startOffset: 0,
      endOffset: 4,
    );

    yuliMarkdownCommandShortcuts
        .firstWhere((command) => command.key == 'YuLi markdown bold')
        .execute(state);
    await Future<void>.delayed(Duration.zero);

    expect(
      state.document.root.children.single.delta?.toPlainText(),
      '**Hola**',
    );
  });

  test('YuLi heading command shortcuts insert line prefixes', () async {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [paragraphNode(delta: Delta()..insert('Titulo'))],
        ),
      ),
    );
    state.selection = Selection.collapsed(Position(path: const [0], offset: 6));

    yuliMarkdownCommandShortcuts
        .firstWhere((command) => command.key == 'YuLi markdown H2')
        .execute(state);
    await Future<void>.delayed(Duration.zero);

    expect(
      state.document.root.children.single.delta?.toPlainText(),
      '## Titulo',
    );

    yuliMarkdownCommandShortcuts
        .firstWhere((command) => command.key == 'YuLi markdown body')
        .execute(state);
    await Future<void>.delayed(Duration.zero);

    expect(state.document.root.children.single.delta?.toPlainText(), 'Titulo');
  });

  test('YuLi task command toggles markdown checkboxes', () async {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [paragraphNode(delta: Delta()..insert('Pendiente'))],
        ),
      ),
    );
    state.selection = Selection.collapsed(Position(path: const [0], offset: 0));
    final command = yuliMarkdownCommandShortcuts.firstWhere(
      (command) => command.key == 'YuLi markdown task',
    );

    command.execute(state);
    await Future<void>.delayed(Duration.zero);
    expect(
      state.document.root.children.single.delta?.toPlainText(),
      '- [ ] Pendiente',
    );

    command.execute(state);
    await Future<void>.delayed(Duration.zero);
    expect(
      state.document.root.children.single.delta?.toPlainText(),
      '- [x] Pendiente',
    );
  });

  test('table cell enter inserts a multiline break inside the cell', () async {
    final table =
        TableNode.fromList<String>([
          ['A'],
        ]).node;
    final state = EditorState(document: Document(root: pageNode(children: [])));
    state.document.root.insert(table);
    final textNode = table.children.single.children.single;
    state.selection = Selection.collapsed(
      Position(path: textNode.path, offset: 1),
    );

    yuliMarkdownCommandShortcuts
        .firstWhere((command) => command.key == 'YuLi table cell newline')
        .execute(state);
    await Future<void>.delayed(Duration.zero);

    expect(textNode.delta?.toPlainText(), 'A\n');
    expect(state.selection?.start.offset, 2);
    expect(
      table.children.every(
        (cell) => cell.attributes[TableCellBlockKeys.height] == 70.0,
      ),
      isTrue,
    );
    expect(table.attributes[TableBlockKeys.colsHeight], 74.0);
  });

  test('inline formatting stays active with trailing spaces', () {
    final cases = <(String, String, String)>[
      ('**Hola **', 'Hola ', AppFlowyRichTextKeys.bold),
      ('***Hola ***', 'Hola ', AppFlowyRichTextKeys.bold),
      ('*Hola *', 'Hola ', AppFlowyRichTextKeys.italic),
      ('_Hola _', 'Hola ', AppFlowyRichTextKeys.italic),
      ('~~Hola ~~', 'Hola ', AppFlowyRichTextKeys.strikethrough),
      ('==Hola ==', 'Hola ', yuliHighlight),
      ('`Hola `', 'Hola ', AppFlowyRichTextKeys.code),
    ];

    for (final (source, content, attribute) in cases) {
      final operations =
          buildLiveMarkdownDelta(source).toList().whereType<TextInsert>();
      expect(
        operations.any(
          (operation) =>
              operation.text == content &&
              operation.attributes?[attribute] == true,
        ),
        isTrue,
        reason: source,
      );
    }
  });

  test('inline latex keeps source markers and supports trailing spaces', () {
    final operations =
        buildLiveMarkdownDelta(
          r'Antes $1 = 1 $ despues',
        ).toList().whereType<TextInsert>().toList();

    expect(
      operations
          .where(
            (operation) => operation.attributes?[yuliMarkdownMarker] == true,
          )
          .map((operation) => operation.text)
          .join(),
      r'$$',
    );
    expect(
      operations.any(
        (operation) =>
            operation.text == '1 = 1 ' &&
            operation.attributes?[yuliLatex] == true,
      ),
      isTrue,
    );
  });

  test('multiple inline latex domains remain independent', () {
    final operations =
        buildLiveMarkdownDelta(
          r'Hola $1+2$ y $1*3$',
        ).toList().whereType<TextInsert>().toList();
    final formulas =
        operations
            .where((operation) => operation.attributes?[yuliLatex] == true)
            .map((operation) => operation.text)
            .toList();

    expect(formulas, ['1+2', '1*3']);
  });

  test('display latex remains one live domain across lines', () {
    final operations =
        buildLiveMarkdownDelta('''\$\$
x^2 + y^2
\$\$''').toList().whereType<TextInsert>().toList();

    expect(
      operations.any(
        (operation) =>
            operation.text.contains('x^2 + y^2') &&
            operation.attributes?[yuliLatex] == true &&
            operation.attributes?[yuliLatexDisplay] == true,
      ),
      isTrue,
    );
  });

  test('empty and escaped dollar domains do not render as latex', () {
    for (final source in [r'$ $', r'\$1 = 1$']) {
      final operations =
          buildLiveMarkdownDelta(source).toList().whereType<TextInsert>();
      expect(
        operations.any((operation) => operation.attributes?[yuliLatex] == true),
        isFalse,
        reason: source,
      );
    }
  });

  test('markers containing only spaces do not format', () {
    final sources = ['** **', '* *', '_ _', '~~ ~~', '== ==', '` `'];

    for (final source in sources) {
      final operations =
          buildLiveMarkdownDelta(source).toList().whereType<TextInsert>();
      expect(
        operations.any(
          (operation) =>
              operation.attributes?[AppFlowyRichTextKeys.bold] == true ||
              operation.attributes?[AppFlowyRichTextKeys.italic] == true ||
              operation.attributes?[AppFlowyRichTextKeys.strikethrough] ==
                  true ||
              operation.attributes?[AppFlowyRichTextKeys.code] == true ||
              operation.attributes?[yuliHighlight] == true,
        ),
        isFalse,
        reason: source,
      );
    }
  });

  test('block markers appear only while their line is active', () {
    final marker =
        buildLiveMarkdownDelta(
          '# Titulo',
        ).toList().whereType<TextInsert>().first;

    expect(
      isMarkdownMarkerActive(
        attributes: marker.attributes!,
        selectionIsInNode: true,
        selectionStart: 7,
        selectionEnd: 7,
      ),
      isTrue,
    );
    expect(
      isMarkdownMarkerActive(
        attributes: marker.attributes!,
        selectionIsInNode: false,
        selectionStart: 0,
        selectionEnd: 0,
      ),
      isFalse,
    );
  });

  test('inline markers appear only inside their markdown domain', () {
    final marker = buildLiveMarkdownDelta(
      'Antes **fuerte** despues',
    ).toList().whereType<TextInsert>().firstWhere(
      (operation) => operation.attributes?[yuliMarkdownDomainStart] != null,
    );

    expect(
      isMarkdownMarkerActive(
        attributes: marker.attributes!,
        selectionIsInNode: true,
        selectionStart: 9,
        selectionEnd: 9,
      ),
      isTrue,
    );
    expect(
      isMarkdownMarkerActive(
        attributes: marker.attributes!,
        selectionIsInNode: true,
        selectionStart: 2,
        selectionEnd: 2,
      ),
      isFalse,
    );
  });

  test('caret snaps across hidden inline marker interiors', () {
    const source = 'Antes **fuerte** despues';
    final openingStart = source.indexOf('**');
    final openingInterior = openingStart + 1;
    final contentStart = source.indexOf('fuerte');
    final contentEnd = contentStart + 'fuerte'.length;
    final closingStart = source.lastIndexOf('**');
    final closingInterior = closingStart + 1;
    final closingEnd = closingStart + 2;

    expect(
      snapHiddenMarkdownMarkerCaretOffset(
        text: source,
        offset: openingInterior,
        previousOffset: openingInterior - 1,
      ),
      contentStart,
    );
    expect(
      snapHiddenMarkdownMarkerCaretOffset(
        text: source,
        offset: openingInterior,
        previousOffset: contentStart,
      ),
      openingStart,
    );
    expect(
      snapHiddenMarkdownMarkerCaretOffset(
        text: source,
        offset: closingInterior,
        previousOffset: contentEnd,
      ),
      closingEnd,
    );
    expect(
      snapHiddenMarkdownMarkerCaretOffset(
        text: source,
        offset: closingInterior,
        previousOffset: closingEnd,
      ),
      contentEnd,
    );
  });

  test('heading and quote markers include their following space', () {
    final heading =
        buildLiveMarkdownDelta('# Titulo').toList().whereType<TextInsert>();
    final quote =
        buildLiveMarkdownDelta('> Cita').toList().whereType<TextInsert>();

    expect(
      heading
          .where(
            (operation) => operation.attributes?[yuliMarkdownMarker] == true,
          )
          .map((operation) => operation.text)
          .join(),
      '# ',
    );
    expect(
      quote
          .where(
            (operation) => operation.attributes?[yuliMarkdownMarker] == true,
          )
          .map((operation) => operation.text)
          .join(),
      '> ',
    );
  });

  test('list and task markers remain visible source text', () {
    for (final source in ['- Tarea', '1. Paso', '- [ ] Pendiente']) {
      final markers =
          buildLiveMarkdownDelta(source)
              .toList()
              .whereType<TextInsert>()
              .where(
                (operation) =>
                    operation.attributes?[yuliMarkdownMarker] == true,
              )
              .map((operation) => operation.text)
              .join();

      expect(markers, isEmpty, reason: source);
    }
  });

  test('panel insertion restores its captured selection', () async {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [paragraphNode(delta: Delta()..insert('Antes despues'))],
        ),
      ),
    );
    final captured = Selection.collapsed(Position(path: const [0], offset: 6));
    state.selection = null;

    await insertMarkdownAtSelection(state, captured, 'TABLA ');

    expect(
      state.document.root.children.single.delta?.toPlainText(),
      'Antes TABLA despues',
    );
  });

  test(
    'panel insertion uses YuLi nodes instead of AppFlowy paste nodes',
    () async {
      final state = EditorState(
        document: Document(root: pageNode(children: [paragraphNode()])),
      );
      final selection = Selection.collapsed(Position(path: const [0]));

      await insertMarkdownAtSelection(state, selection, '\n> Cita\n');

      expect(state.document.root.children, hasLength(1));
      expect(state.document.root.children.single.type, ParagraphBlockKeys.type);
      expect(
        state.document.root.children.single.delta?.toPlainText(),
        '> Cita',
      );
    },
  );

  test(
    'multiline insertion splits the active paragraph at the cursor',
    () async {
      final state = EditorState(
        document: Document(
          root: pageNode(
            children: [paragraphNode(delta: Delta()..insert('Antes despues'))],
          ),
        ),
      );
      final selection = Selection.collapsed(
        Position(path: const [0], offset: 6),
      );

      await insertMarkdownAtSelection(state, selection, '\n> Cita\n');

      expect(
        state.document.root.children
            .map((node) => node.delta?.toPlainText())
            .toList(),
        ['Antes ', '> Cita', 'despues'],
      );
      expect(state.selection?.start.path, [1]);
    },
  );

  test('divider insertion remains literal markdown', () async {
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode()])),
    );
    final selection = Selection.collapsed(Position(path: const [0]));

    await insertMarkdownAtSelection(state, selection, '\n\n---\n\n');

    expect(state.document.root.children.single.type, ParagraphBlockKeys.type);
    expect(state.document.root.children.single.delta?.toPlainText(), '---');
  });

  test('new paragraphs inherit the selected alignment', () async {
    final state = EditorState(
      document: Document(
        root: pageNode(
          children: [paragraphNode(delta: Delta()..insert('Centro'))],
        ),
      ),
    );
    state.selection = Selection.collapsed(Position(path: const [0], offset: 6));
    setPreferredMarkdownAlignment(state, 'center');

    await yuliMarkdownCharacterShortcuts.first.execute(state);

    expect(state.document.root.children, hasLength(2));
    expect(
      state.document.root.children.last.attributes[blockComponentAlign],
      'center',
    );
    expect(preferredMarkdownAlignment(state), 'center');
  });

  test('enter after an atomic node creates a following paragraph', () async {
    final state = EditorState(
      document: Document(
        root: pageNode(children: [imageNode(url: 'image.png')]),
      ),
    );
    state.selection = Selection.single(
      path: const [0],
      startOffset: 0,
      endOffset: 1,
    );

    await yuliMarkdownCharacterShortcuts.first.execute(state);

    expect(state.document.root.children, hasLength(2));
    expect(state.document.root.children.last.type, ParagraphBlockKeys.type);
    expect(state.selection?.start.path, [1]);
  });

  test('alignment remains selected until the user changes it', () async {
    final state = EditorState(
      document: Document(root: pageNode(children: [paragraphNode()])),
    );
    state.selection = Selection.collapsed(Position(path: const [0]));
    setPreferredMarkdownAlignment(state, 'right');

    await yuliMarkdownCharacterShortcuts.first.execute(state);
    setPreferredMarkdownAlignment(state, 'left');
    await yuliMarkdownCharacterShortcuts.first.execute(state);

    expect(
      state.document.root.children[1].attributes[blockComponentAlign],
      'right',
    );
    expect(
      state.document.root.children[2].attributes[blockComponentAlign],
      isNull,
    );
    expect(preferredMarkdownAlignment(state), 'left');
  });
}
