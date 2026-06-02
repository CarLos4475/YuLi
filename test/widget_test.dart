// Smoke test: la pantalla de arranque (splash) se renderiza con el título.
// Se prueba el splash en aislado en vez de bootear YuLiApp completa: el arranque
// real usa un Future.delayed(800ms) no cancelable + streams de BD en el shell que
// hacen frágil/colgante un test de integración. El splash cubre el render inicial.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/presentation/widgets/yuli_splash_screen.dart';

void main() {
  testWidgets('El splash de arranque muestra el título YuLi', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: YuliSplashScreen()));

    expect(find.text('YuLi'), findsOneWidget);
    expect(find.byType(YuliSplashScreen), findsOneWidget);

    // Desmonta para cancelar el AnimationController del cubo del splash.
    await tester.pumpWidget(const SizedBox());
  });
}
