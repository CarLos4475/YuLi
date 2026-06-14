import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/stroke_tiles.dart';

void main() {
  DrawingStroke strokeAt(double x, double y) => DrawingStroke(
        colorValue: 0xFF000000,
        strokeWidth: 3,
        points: StrokePoints.fromNested([
          [x, y],
          [x + 40, y + 10],
        ]),
      );

  bool indexed(StrokeTileIndex idx, DrawingStroke s) {
    // tileSize is 512; cover a wide rect and look for the stroke by identity.
    for (final key in idx.tilesInRect(const Rect.fromLTWH(0, 0, 8192, 8192))) {
      final list = idx.strokesAt(key);
      if (list != null && list.contains(s)) return true;
    }
    return false;
  }

  test('invalidateRegion keeps strokes in the tile just past the region edge',
      () {
    // Regression: _gridAlign + _keysIn over-include one tile column/row past the
    // region when an edge lands on a tile boundary. That extra tile was cleared
    // but its strokes were not re-added → invisible chunks.
    final idx = StrokeTileIndex();
    // Far stroke at x≈1600 → tile column 3 [1536,2048]; well outside the region.
    final far = strokeAt(1600, 50);
    final near = strokeAt(100, 100);
    idx.rebuild([far, near]);
    expect(indexed(idx, far), isTrue);

    // Region right edge = 1024 (an exact multiple of tileSize/… boundary case).
    idx.invalidateRegion(const Rect.fromLTRB(0, 0, 1024, 100), [far, near]);

    expect(indexed(idx, far), isTrue,
        reason: 'stroke past the region edge must survive invalidateRegion');
    expect(indexed(idx, near), isTrue);
  });

  test('invalidateRegion drops a stroke that was actually erased', () {
    final idx = StrokeTileIndex();
    final a = strokeAt(100, 100);
    final b = strokeAt(140, 110);
    idx.rebuild([a, b]);
    // Simulate erasing `a`: re-run with only `b` present over a's region.
    idx.invalidateRegion(const Rect.fromLTRB(80, 80, 200, 200), [b]);
    expect(indexed(idx, a), isFalse);
    expect(indexed(idx, b), isTrue);
  });
}
