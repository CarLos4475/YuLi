import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/screens/flight/ai_chat_session.dart';
import 'package:yuli/presentation/screens/flight/ai_chat_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('switching chat layout keeps the unsent draft', (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    tester.view.devicePixelRatio = 1;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final session = AiChatSession(901);
    final controller = AiChatDockController()..open();
    var canvasTaps = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              Scaffold(
                body: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => canvasTaps++,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                child: AiChatDock(
                  controller: controller,
                  session: session,
                  accent: const Color(0xFF2D3F8C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final input = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Escribe a YuLi…',
    );
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Borrador sin enviar');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cambiar a ventana flotante'));
    await tester.pump();
    expect(controller.displayMode, AiChatDisplayMode.floating);
    expect(find.text('MOVER CHAT'), findsOneWidget);
    expect(
      tester.widget<TextField>(input).controller?.text,
      'Borrador sin enviar',
    );

    await tester.tapAt(const Offset(30, 200));
    expect(canvasTaps, 1);

    final beforeDrag = tester.getTopLeft(find.text('MOVER CHAT'));
    await tester.drag(find.text('MOVER CHAT'), const Offset(-90, 35));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('MOVER CHAT')).dx,
      lessThan(beforeDrag.dx),
    );

    final beforeResize = tester.getTopLeft(find.text('REDIMENSIONAR'));
    await tester.drag(find.text('REDIMENSIONAR'), const Offset(-70, -50));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('REDIMENSIONAR')).dy,
      lessThan(beforeResize.dy),
    );

    tester.view.physicalSize = const Size(360, 740);
    await tester.pump();
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.text('REDIMENSIONAR')).dy,
      lessThanOrEqualTo(440),
    );
    tester.view.resetViewInsets();
    await tester.pump();

    await tester.tap(find.byTooltip('Cambiar a panel lateral'));
    await tester.pump();
    expect(controller.displayMode, AiChatDisplayMode.lateral);
    expect(find.text('MOVER CHAT'), findsNothing);
    expect(
      tester.widget<TextField>(input).controller?.text,
      'Borrador sin enviar',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(milliseconds: 10));
    controller.dispose();
    session.dispose();
  });
}
