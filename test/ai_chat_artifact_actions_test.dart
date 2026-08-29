import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/note_block_widgets.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_widget_contracts.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_widget_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('code blocks expose copy and pin actions', (tester) async {
    String? copied;
    String? pinned;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NoteMarkdownPreview(
              data: '```dart\nvoid main() {}\n```',
              onCopyBlock: (value) => copied = value,
              onPinBlock: (value) => pinned = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copiar bloque'));
    expect(copied, 'void main() {}');

    await tester.tap(find.byTooltip('Pinear en lienzo'));
    expect(pinned, '```dart\nvoid main() {}\n```');

    await _disposePreview(tester);
  });

  testWidgets('display math exposes clean LaTeX and pinnable markdown', (tester) async {
    String? copied;
    String? pinned;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NoteMarkdownPreview(
              data: '\$\$\nx^2 + y^2 = z^2\n\$\$',
              onCopyBlock: (value) => copied = value,
              onPinBlock: (value) => pinned = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copiar bloque'));
    expect(copied, 'x^2 + y^2 = z^2');

    await tester.tap(find.byTooltip('Pinear en lienzo'));
    expect(pinned, '\$\$\nx^2 + y^2 = z^2\n\$\$');

    await _disposePreview(tester);
  });

  testWidgets('tables expose copy and pin actions for each table', (tester) async {
    String? copied;
    String? pinned;
    const firstTable = '| Nombre | Valor |\n|---|---|\n| Alfa | 1 |';
    const secondTable = '| Día | Tarea |\n|---|---|\n| Lunes | Leer |';

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NoteMarkdownPreview(
              data: '$firstTable\n\n$secondTable',
              onCopyBlock: (value) => copied = value,
              onPinBlock: (value) => pinned = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Copiar bloque'), findsNWidgets(2));
    expect(find.byTooltip('Pinear en lienzo'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Copiar bloque').first);
    expect(copied, firstTable);

    await tester.tap(find.byTooltip('Pinear en lienzo').last);
    expect(pinned, secondTable);

    await _disposePreview(tester);
  });

  testWidgets('formula cards expose the same artifact actions', (tester) async {
    String? copied;
    String? pinned;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AiWidgetRenderer(
              text: '''<!--YULI_WIDGET:FORMULA_CARD v=1
{"title":"Pitágoras","formula":"\$\$a^2+b^2=c^2\$\$","variables":[]}
-->''',
              accent: const Color(0xFF2D3F8C),
              surface: AiWidgetSurface.flight,
              onCopyBlock: (value) => copied = value,
              onPinBlock: (value) => pinned = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copiar bloque'));
    expect(copied, 'a^2+b^2=c^2');

    await tester.tap(find.byTooltip('Pinear en lienzo'));
    expect(pinned, '\$\$\na^2+b^2=c^2\n\$\$');

    await _disposePreview(tester);
  });
}

Future<void> _disposePreview(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 600));
}
