import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_widget_contracts.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_widget_renderer.dart';
import 'package:yuli/presentation/theme/lab_icons.dart';
import 'package:yuli/presentation/widgets/yuli_design.dart';

void main() {
  testWidgets('QUIZ marks the selected correct answer', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text:
              '<!--YULI_WIDGET:QUIZ v=1\n'
              '{"question":"¿Cuánto vale pi aproximadamente?",'
              '"options":[{"id":"a","label":"1"},{"id":"c","label":"3.14159"}],'
              '"answer":"c","explanation":"Pi se aproxima como 3.14159."}'
              '-->',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
        ),
      ),
    );

    await tester.tap(find.text('3.14159'));
    await tester.pump();

    expect(find.text('Correcto'), findsOneWidget);
    expect(find.text('Pi se aproxima como 3.14159.'), findsOneWidget);
  });

  testWidgets('TASK_DRAFT renders folder as a badge, not raw mention', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text:
              '<!--YULI_WIDGET:TASK_DRAFT v=1\n'
              '{"content":"Hacer tarea de límites",'
              '"folder":{"id":7,"name":"Cálculo","color":"#2D4B8E"},'
              '"dueDate":"2026-06-20","duePrecision":"date",'
              '"reminderPreset":"before_1d"}'
              '-->',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
        ),
      ),
    );

    expect(find.text('Cálculo'), findsOneWidget);
    expect(find.textContaining('@Cálculo'), findsNothing);
    expect(find.text('CREAR'), findsOneWidget);
  });

  testWidgets('LAB_CARD_DRAFT renders as Lab draft with due time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text:
              'YULI_WIDGET:LAB_CARD_DRAFT v=1\n'
              '{"title":"Investigar APIs REST",'
              '"space":"Hello","column":"Backlog",'
              '"description":"Leer documentación",'
              '"dueDate":"2026-06-26T19:00:00",'
              '"reminderPreset":"before_1d"}'
              '\n',
          accent: yLab,
          surface: AiWidgetSurface.yuli,
        ),
      ),
    );

    expect(find.text('CREAR TARJETA'), findsOneWidget);
    expect(find.text('Investigar APIs REST'), findsOneWidget);
    expect(find.textContaining('19:00'), findsOneWidget);
    expect(find.textContaining('YULI_WIDGET'), findsNothing);
  });

  testWidgets('CONCEPT_CARD renders definition and callouts', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text:
              '<!--YULI_WIDGET:CONCEPT_CARD v=1\n'
              '{"title":"derivada",'
              '"definition":"mide el cambio instantaneo",'
              '"keyIdea":"es una pendiente local",'
              '"example":"si x es posicion, la derivada es velocidad"}'
              '-->',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
        ),
      ),
    );

    expect(find.text('Derivada'), findsOneWidget);
    expect(find.text('Idea clave'), findsOneWidget);
    expect(find.text('Ejemplo'), findsOneWidget);
    expect(find.textContaining('YULI_WIDGET'), findsNothing);
  });

  testWidgets('STEPS and COMPARISON render visual rows', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text:
              '<!--YULI_WIDGET:STEPS v=1\n'
              '{"title":"resolver limite",'
              '"items":[{"label":"sustituye","detail":"prueba directo"},'
              '{"label":"simplifica","detail":"reduce la expresion"}]}'
              '-->'
              '<!--YULI_WIDGET:COMPARISON v=1\n'
              '{"title":"directo vs algebra",'
              '"leftLabel":"directo","rightLabel":"algebra",'
              '"rows":[{"left":"rapido","right":"mas seguro"}]}'
              '-->',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
        ),
      ),
    );

    expect(find.text('Resolver limite'), findsOneWidget);
    expect(find.text('Sustituye'), findsOneWidget);
    expect(find.text('Directo vs algebra'), findsOneWidget);
    expect(find.text('Mas seguro'), findsOneWidget);
  });

  testWidgets('FLASHCARDS flips card on tap', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text:
              '<!--YULI_WIDGET:FLASHCARDS v=1\n'
              '{"title":"repaso",'
              '"cards":[{"front":"que mide la derivada","back":"cambio instantaneo"}]}'
              '-->',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
        ),
      ),
    );

    expect(find.text('Que mide la derivada'), findsOneWidget);
    expect(find.text('Cambio instantaneo'), findsNothing);

    await tester.tap(find.text('Que mide la derivada'));
    await tester.pump();

    expect(find.text('Respuesta'), findsOneWidget);
    expect(find.text('Cambio instantaneo'), findsOneWidget);
  });

  testWidgets('CHECKLIST toggles local item state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text:
              '<!--YULI_WIDGET:CHECKLIST v=1\n'
              '{"title":"plan de estudio",'
              '"items":[{"label":"repasar formulas","checked":false},'
              '{"label":"resolver ejercicios","checked":true}]}'
              '-->',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
        ),
      ),
    );

    expect(find.text('Plan de estudio'), findsOneWidget);
    expect(find.text('Repasar formulas'), findsOneWidget);
    expect(find.text('Resolver ejercicios'), findsOneWidget);

    await tester.tap(find.text('Repasar formulas'));
    await tester.pump();

    expect(find.byIcon(YuLiIcons.squareCheck), findsNWidgets(3));
  });
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}
