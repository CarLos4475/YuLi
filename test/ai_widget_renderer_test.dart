import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
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

  testWidgets('STEPS sends explanation prompt when tapping a step', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      _wrap(
        AiWidgetRenderer(
          text:
              '<!--YULI_WIDGET:STEPS v=1\n'
              '{"title":"resolver ecuacion",'
              '"items":[{"label":"despeja x","detail":"divide entre 2"}]}'
              '-->',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
          onSendMessage: sent.add,
        ),
      ),
    );

    await tester.tap(find.text('Despeja x'), warnIfMissed: false);
    await tester.pump();

    expect(sent.single, contains('Explícame con más detalle el paso 1'));
    expect(sent.single, contains('Despeja x'));
  });

  testWidgets('SOLVED_EXAMPLE renders latex and sends step prompt', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      _wrap(
        AiWidgetRenderer(
          text: r'''<!--YULI_WIDGET:SOLVED_EXAMPLE v=1
{"title":"resolver $2x=0$","setup":"buscamos el valor de $x$","steps":[{"label":"despeja","detail":"divide ambos lados entre $2$","formula":"$$x=0$$"},{"label":"verifica","detail":"sustituye $x=0$"}],"result":"resultado final: $$x=0$$","intuition":"si duplicas cero, queda cero"}
-->''',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
          onSendMessage: sent.add,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('EJEMPLO'), findsOneWidget);
    expect(find.byType(Math), findsWidgets);
    expect(find.textContaining('YULI_WIDGET'), findsNothing);

    await tester.tap(find.text('Despeja'), warnIfMissed: false);
    await tester.pump();

    expect(sent.last, contains('Explícame con más detalle el paso 1'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('FORMULA_CARD renders latex formula and variables', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text: r'''<!--YULI_WIDGET:FORMULA_CARD v=1
{"title":"formula cuadratica","formula":"$$x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}$$","variables":[{"symbol":"$a$","meaning":"coeficiente de $x^2$"}],"whenToUse":"cuando tienes $ax^2+bx+c=0$","example":"si $a=1$, se simplifica"}
-->''',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('FORMULA'), findsOneWidget);
    expect(find.byType(Math), findsWidgets);
    expect(find.textContaining('YULI_WIDGET'), findsNothing);
    expect(find.textContaining('<center>'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('PRACTICE_SET sends solve prompt from exercise action', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      _wrap(
        AiWidgetRenderer(
          text: r'''<!--YULI_WIDGET:PRACTICE_SET v=1
{"title":"practica ecuaciones","items":[{"level":"facil","prompt":"Resuelve $2x=0$.","hint":"divide entre 2"}]}
-->''',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
          onSendMessage: sent.add,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolver'), warnIfMissed: false);
    await tester.pump();

    expect(sent.single, contains('Resuelve este ejercicio paso a paso'));
    expect(sent.single, contains('2x=0'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('HINT_LADDER reveals hints and sends detail prompt', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      _wrap(
        AiWidgetRenderer(
          text: r'''<!--YULI_WIDGET:HINT_LADDER v=1
{"title":"pistas para resolver","hints":[{"label":"pista 1","text":"deja $x$ sola"},{"label":"pista 2","text":"divide entre $2$"}]}
-->''',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
          onSendMessage: sent.add,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Pista 2'), findsNothing);
    await tester.tap(find.text('REVELAR PISTA'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Pista 2'), findsOneWidget);

    await tester.tap(find.text('Pista 1'), warnIfMissed: false);
    await tester.pump();
    expect(sent.single, contains('Explícame con más detalle el paso 1'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('expanded study widgets render without raw contracts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AiWidgetRenderer(
          text:
              '<!--YULI_WIDGET:MISTAKE_CHECK v=1\n'
              '{"title":"errores comunes","items":[{"mistake":"sumar mal","why":"signos","fix":"revisa cada paso"}]}'
              '-->'
              '<!--YULI_WIDGET:MINI_PROOF v=1\n'
              '{"title":"prueba breve","claim":"si a=b","steps":[{"label":"usa igualdad","detail":"sustituye"}],"conclusion":"queda probado"}'
              '-->'
              '<!--YULI_WIDGET:VOCAB_CARD v=1\n'
              '{"term":"pendiente","definition":"inclinacion","example":"sube 3"}'
              '-->'
              '<!--YULI_WIDGET:TIMELINE v=1\n'
              '{"title":"cronologia","entries":[{"date":"1637","label":"inicio","detail":"primera idea"}]}'
              '-->'
              '<!--YULI_WIDGET:FLOWCHART v=1\n'
              '{"title":"flujo de estudio","nodes":[{"label":"lee","detail":"detecta datos"},{"label":"resuelve","detail":"aplica metodo"}]}'
              '-->'
              '<!--YULI_WIDGET:CAUSE_EFFECT v=1\n'
              '{"title":"causa y efecto","cause":"aumenta x","mechanism":"cambia y","effect":"sube la recta"}'
              '-->'
              '<!--YULI_WIDGET:GRAPH_SKETCH v=1\n'
              '{"title":"grafica lineal","xLabel":"x","yLabel":"y","description":"recta creciente","features":[{"label":"pendiente","value":"3"}]}'
              '-->'
              '<!--YULI_WIDGET:MNEMONIC v=1\n'
              '{"title":"mnemotecnia","mnemonic":"SOH CAH TOA","meaning":"razones trigonometricas","items":[{"cue":"SOH","text":"seno"}]}'
              '-->'
              '<!--YULI_WIDGET:EXAM_RUBRIC v=1\n'
              '{"title":"guia examen","focus":"reglas basicas","criteria":[{"label":"derivar","weight":"50%","detail":"potencia"}],"traps":[{"text":"olvidar signos"}]}'
              '-->',
          accent: yFlight,
          surface: AiWidgetSurface.flight,
        ),
      ),
    );

    expect(find.text('Errores comunes'), findsOneWidget);
    expect(find.text('Prueba breve'), findsOneWidget);
    expect(find.text('Pendiente'), findsWidgets);
    expect(find.text('Cronologia'), findsOneWidget);
    expect(find.text('1637'), findsOneWidget);
    expect(find.text('Flujo de estudio'), findsOneWidget);
    expect(find.text('Causa y efecto'), findsOneWidget);
    expect(find.text('Grafica lineal'), findsOneWidget);
    expect(find.text('Mnemotecnia'), findsOneWidget);
    expect(find.text('Guia examen'), findsOneWidget);
    expect(find.textContaining('YULI_WIDGET'), findsNothing);
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

    await tester.tap(find.text('Que mide la derivada'), warnIfMissed: false);
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

    await tester.tap(find.text('Repasar formulas'), warnIfMissed: false);
    await tester.pump();

    expect(find.byIcon(YuLiIcons.squareCheck), findsNWidgets(3));
  });
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(child: SizedBox(width: 500, child: child)),
        ),
      ),
    ),
  );
}
