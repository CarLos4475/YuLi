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
}
