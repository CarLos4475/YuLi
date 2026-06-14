import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/stroke_points.dart';

void main() {
  group('StrokePoints', () {
    test('empty defaults to 2 comps', () {
      final p = StrokePoints();
      expect(p.isEmpty, true);
      expect(p.length, 0);
      expect(p.comps, 2);
    });

    test('add grows and reads back by index', () {
      final p = StrokePoints(comps: 2);
      for (var i = 0; i < 100; i++) {
        p.add(i.toDouble(), (i * 2).toDouble());
      }
      expect(p.length, 100);
      expect(p.x(0), 0);
      expect(p.y(0), 0);
      expect(p.x(50), 50);
      expect(p.y(50), 100);
      expect(p.firstX, 0);
      expect(p.lastX, 99);
      expect(p.lastY, 198);
    });

    test('comps=3 keeps the third component, z() defaults to 0 for comps=2', () {
      final p3 = StrokePoints(comps: 3);
      p3.add(1, 2, 0.7);
      expect(p3.z(0), closeTo(0.7, 1e-6));
      final p2 = StrokePoints(comps: 2);
      p2.add(1, 2, 0.7); // extra ignored
      expect(p2.comps, 2);
      expect(p2.z(0), 0);
    });

    test('removeWhere compacts in place', () {
      final p = StrokePoints(comps: 2);
      for (var i = 0; i < 10; i++) {
        p.add(i.toDouble(), 0);
      }
      p.removeWhere((i) => p.x(i) % 2 == 0); // drop evens
      expect(p.length, 5);
      expect([for (var i = 0; i < p.length; i++) p.x(i)], [1, 3, 5, 7, 9]);
    });

    test('fromFloat32 wraps without copying', () {
      final data = Float32List.fromList([0, 0, 1, 1, 2, 2]);
      final p = StrokePoints.fromFloat32(data, 2);
      expect(p.length, 3);
      expect(p.x(2), 2);
      expect(identical(p.packed(), data), true); // exact size → same array
    });

    test('fromNested / toNested round-trip preserving comps', () {
      final nested = [
        [1.0, 2.0, 0.5],
        [3.0, 4.0, 0.9],
      ];
      final p = StrokePoints.fromNested(nested);
      expect(p.comps, 3);
      final out = p.toNested();
      expect(out.length, 2);
      for (var i = 0; i < 2; i++) {
        for (var c = 0; c < 3; c++) {
          expect(out[i][c], closeTo(nested[i][c], 1e-6)); // float32 precision
        }
      }
    });

    test('clone is independent', () {
      final p = StrokePoints(comps: 2)..add(1, 1);
      final c = p.clone();
      p.add(2, 2);
      expect(c.length, 1);
      expect(p.length, 2);
    });

    test('mapXY transforms x,y and preserves extra comps', () {
      final p = StrokePoints(comps: 3)
        ..add(1, 2, 0.5)
        ..add(3, 4, 0.9);
      final m = p.mapXY((x, y) => Offset(x + 10, y * 2));
      expect(m.x(0), 11);
      expect(m.y(0), 4);
      expect(m.z(0), closeTo(0.5, 1e-6));
      expect(m.x(1), 13);
      expect(m.y(1), 8);
      expect(m.z(1), closeTo(0.9, 1e-6));
    });

    test('toOffsets', () {
      final p = StrokePoints(comps: 2)
        ..add(1, 2)
        ..add(3, 4);
      expect(p.toOffsets(), [const Offset(1, 2), const Offset(3, 4)]);
    });
  });
}
