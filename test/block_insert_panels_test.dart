import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/block_insert_panels.dart';

void main() {
  testWidgets('latex panel previews and inserts inline math', (tester) async {
    String? inserted;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: InsertPanelOverlay(
              type: InsertPanelType.latex,
              noteId: 1,
              accent: const Color(0xFF2D3F8C),
              onClose: () {},
              onInsert: (markdown) => inserted = markdown,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Vista previa'), findsOneWidget);
    expect(find.byType(Math), findsNothing);

    await tester.enterText(find.byType(TextField), r'1 + \frac{1}{2}');
    await tester.pump();

    expect(find.byType(Math), findsOneWidget);
    await tester.tap(find.text('INSERTAR'));
    await tester.pump();

    expect(inserted, r' $1 + \frac{1}{2}$ ');
  });

  testWidgets('latex block panel accepts multiline input', (tester) async {
    String? inserted;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: InsertPanelOverlay(
              type: InsertPanelType.latex,
              noteId: 1,
              accent: const Color(0xFF2D3F8C),
              onClose: () {},
              onInsert: (markdown) => inserted = markdown,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Bloque'));
    await tester.pump();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.keyboardType, TextInputType.multiline);
    expect(input.textInputAction, TextInputAction.newline);

    await tester.enterText(find.byType(TextField), 'a = b\nc = d');
    await tester.pump();
    await tester.tap(find.text('INSERTAR'));
    await tester.pump();

    expect(inserted, '\n\n\$\$\na = b\nc = d\n\$\$\n\n');
  });

  testWidgets('code panel selects language through search', (tester) async {
    String? inserted;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: InsertPanelOverlay(
              type: InsertPanelType.code,
              noteId: 1,
              accent: const Color(0xFF2D3F8C),
              onClose: () {},
              onInsert: (markdown) => inserted = markdown,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'type');
    await tester.pump();
    await tester.tap(find.text('TYPESCRIPT'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'const value = 1;');
    await tester.pump();
    await tester.tap(find.text('INSERTAR'));
    await tester.pump();

    expect(inserted, '\n```ts\nconst value = 1;\n```\n');
  });
}
