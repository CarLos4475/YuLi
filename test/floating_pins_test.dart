import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/pinned_snapshots.dart';
import 'package:yuli/presentation/theme/lab_icons.dart';

Future<ui.Image> _testImage({int width = 200, int height = 100}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF123456),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('controller clamps, resizes, collapses, orders, and closes pins', (
    tester,
  ) async {
    final controller = FloatingPinController();
    final bounds = Rect.fromLTWH(8, 8, 392, 292);
    final first = controller.addSnapshot(
      image: await _testImage(),
      rect: const Rect.fromLTWH(0, 0, 200, 200),
      usableBounds: bounds,
    );
    final second = controller.addSnapshot(
      image: await _testImage(width: 100, height: 100),
      rect: const Rect.fromLTWH(40, 40, 120, 120),
      usableBounds: bounds,
    );

    expect(controller.value.first.id, first.id);
    expect(controller.value.last.id, second.id);
    expect(first.rect.left, 8);
    expect(first.rect.top, 8);
    expect(first.rect.height, floatingPinHeaderHeight + 100);

    controller.commitRect(
      first.id,
      const Rect.fromLTWH(40, 50, 260, 100),
      bounds,
    );
    final resized = controller.value.firstWhere((pin) => pin.id == first.id);
    expect(resized.rect.width, 260);
    expect(resized.rect.height, floatingPinHeaderHeight + 130);

    controller.toggleCollapsed(first.id);
    expect(
      controller.value.firstWhere((pin) => pin.id == first.id).collapsed,
      isTrue,
    );

    controller.bringToFront(first.id);
    expect(controller.value.last.id, first.id);

    controller.close(first.id);
    expect(controller.value.map((pin) => pin.id), isNot(contains(first.id)));
    controller.close(second.id);
  });

  testWidgets('layer appears without rebuilding host and commits drag on release', (
    tester,
  ) async {
    final controller = FloatingPinController();
    final bounds = Rect.fromLTWH(8, 8, 392, 292);
    var hostBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 420,
          height: 320,
          child: KeyedSubtree(
            key: const ValueKey('pin-layer-host'),
            child: Builder(
              builder: (_) {
                hostBuilds++;
                return FloatingPinsLayer(
                  controller: controller,
                  usableBounds: bounds,
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(hostBuilds, 1);
    final layerBoundaries = find.descendant(
      of: find.byKey(const ValueKey('pin-layer-host')),
      matching: find.byType(RepaintBoundary),
    );
    expect(layerBoundaries, findsNothing);

    final pin = controller.addSnapshot(
      image: await _testImage(),
      rect: const Rect.fromLTWH(30, 30, 160, 160),
      usableBounds: bounds,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(hostBuilds, 1);
    expect(find.byKey(ValueKey(pin.id)), findsOneWidget);
    expect(layerBoundaries, findsOneWidget);

    final initialRect = controller.value.single.rect;
    await tester.drag(
      find.byKey(ValueKey('pin-header-${pin.id}')),
      const Offset(50, 40),
    );
    await tester.pump();

    expect(controller.value.single.rect.left, initialRect.left + 50);
    expect(controller.value.single.rect.top, initialRect.top + 40);

    await tester.tap(find.byIcon(YuLiIcons.close));
    await tester.pump();
    expect(controller.value.single.id, pin.id);
    expect(find.byKey(ValueKey(pin.id)), findsOneWidget);

    await tester.pumpAndSettle();
    expect(controller.value, isEmpty);
    expect(find.byKey(ValueKey(pin.id)), findsNothing);
  });
}
