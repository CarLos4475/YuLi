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
