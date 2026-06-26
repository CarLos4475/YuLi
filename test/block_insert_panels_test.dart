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
}
