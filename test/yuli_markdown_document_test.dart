import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/yuli_markdown_document.dart';

void main() {
  test('round trips common markdown and alignment blocks', () {
    const markdown = '''
# Titulo

Texto con **negritas**, _cursiva_, `codigo` y \$x + y\$.

::: center
Texto centrado
:::

> Una cita

- Uno
- Dos

---
''';

    final encoded = YuliMarkdownDocument.encode(
      YuliMarkdownDocument.decode(markdown),
    );

    expect(encoded, contains('# Titulo'));
    expect(encoded, contains('**negritas**'));
    expect(encoded, contains('_cursiva_'));
    expect(encoded, contains('`codigo`'));
    expect(encoded, contains(r'$x + y$'));
    expect(encoded, contains('::: center'));
    expect(encoded, contains('Texto centrado'));
    expect(encoded, contains('> Una cita'));
    expect(encoded, contains('* Uno'));
    expect(encoded, contains('---'));
  });

  test('round trips tables, fenced code and local images', () {
    const markdown = r'''
| A | B |
| --- | --- |
| Uno | Dos |

```dart
final value = 1;
```

::: right
![Imagen](C:\notes\image.png)
:::
''';

    final document = YuliMarkdownDocument.decode(markdown);
    final encoded = YuliMarkdownDocument.encode(document);

    expect(encoded, contains('|A|B|'));
    expect(encoded, contains('```dart'));
    expect(encoded, contains('final value = 1;'));
    expect(encoded, contains(r'![](C:\notes\image.png)'));
    expect(encoded, contains('::: right'));
  });

  test(
    'round trips inline and multiline latex without splitting display math',
    () {
      const source = r'''
Texto con $1 = 1 $.

$$
\frac{1}{2}
$$
''';

      final document = YuliMarkdownDocument.decode(source);
      final encoded = YuliMarkdownDocument.encode(document);
      final display = document.root.children.firstWhere(
        (node) => node.type == yuliLatexBlockType,
      );

      expect(
        display.attributes[yuliLatexBlockContent],
        contains(r'\frac{1}{2}'),
      );
      expect(encoded, contains(r'$1 = 1 $'));
      expect(
        encoded,
        contains(
          r'$$'
          '\n'
          r'\frac{1}{2}'
          '\n'
          r'$$',
        ),
      );
    },
  );

  test('keeps long paragraphs as one wrapping document node', () {
    final text = List.filled(80, 'palabra').join(' ');
    final document = YuliMarkdownDocument.decode(text);

    expect(document.root.children, hasLength(1));
    expect(document.root.children.single.delta?.toPlainText(), text);
  });

  test('keeps visible markdown markers in editable text nodes', () {
    const source = '# Titulo\n> Cita\nTexto **fuerte** y `codigo`';

    final document = YuliMarkdownDocument.decode(source);

    expect(
      document.root.children.map((node) => node.delta?.toPlainText()).toList(),
      ['# Titulo', '> Cita', 'Texto **fuerte** y `codigo`'],
    );
    expect(YuliMarkdownDocument.encode(document), source);
  });

  test('markdown dividers and stars remain editable source text', () {
    const source = '***\n---';

    final document = YuliMarkdownDocument.decode(source);

    expect(document.root.children.first.delta?.toPlainText(), '***');
    expect(document.root.children.last.delta?.toPlainText(), '---');
    expect(YuliMarkdownDocument.encode(document), source);
  });

  test('images receive safe initial bounds without changing markdown', () {
    const source = r'![Imagen](C:\notes\image.png)';

    final document = YuliMarkdownDocument.decode(source);
    final image = document.root.children.single;

    expect(image.attributes[ImageBlockKeys.width], 320.0);
    expect(image.attributes[ImageBlockKeys.height], isNull);
    expect(
      YuliMarkdownDocument.encode(document),
      contains(r'![](C:\notes\image.png)'),
    );
  });

  test('image alignment survives markdown serialization', () {
    const source = r'''
::: left
![Imagen](C:\notes\image.png)
:::
''';

    final document = YuliMarkdownDocument.decode(source);
    final image = document.root.children.single;
    final encoded = YuliMarkdownDocument.encode(document);

    expect(image.attributes[ImageBlockKeys.align], 'left');
    expect(encoded, contains('::: left'));
  });

  test('table cells keep multiline content through markdown br markers', () {
    final table =
        TableNode.fromList<String>([
          ['Tema', 'Linea 1\nLinea 2'],
          ['Dato', 'Valor'],
        ]).node;
    final encoded = YuliMarkdownDocument.encode(
      Document(root: pageNode(children: [table])),
    );
    final decoded = YuliMarkdownDocument.decode(encoded);
    final decodedTable = decoded.root.children.single;
    final multilineCell = decodedTable.children.firstWhere(
      (cell) =>
          cell.attributes[TableCellBlockKeys.colPosition] == 0 &&
          cell.attributes[TableCellBlockKeys.rowPosition] == 1,
    );

    expect(encoded, contains('Linea 1<br>Linea 2'));
    expect(
      multilineCell.children.single.delta?.toPlainText(),
      'Linea 1\nLinea 2',
    );
  });

  test(
    'table cells keep markdown inline formatting when loaded semantically',
    () {
      const source = '''
| A | B |
| --- | --- |
| **Fuerte** | `Codigo` |
''';

      final encoded = YuliMarkdownDocument.encode(
        YuliMarkdownDocument.decode(source),
      );

      expect(encoded, contains('**Fuerte**'));
      expect(encoded, contains('`Codigo`'));
    },
  );
}
