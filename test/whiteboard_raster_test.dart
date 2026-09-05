import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/drawing_engine.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/stroke_bounds.dart';
import 'package:yuli/presentation/screens/flight/stroke_tiles.dart';
import 'package:yuli/presentation/screens/flight/whiteboard_raster.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DrawingStroke shape({double x = 4, double y = 4}) => DrawingStroke(
    colorValue: 0xFF2468AA,
    strokeWidth: 2,
    filled: true,
    isShape: true,
    points: StrokePoints.fromNested([
      [x, y],
      [x + 24, y],
      [x + 24, y + 24],
      [x, y + 24],
      [x, y],
    ]),
  );

  Future<ui.Image> render(void Function(Canvas) paint, {int size = 64}) async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder));
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    addTearDown(image.dispose);
    return image;
  }

  Future<Uint8List> pixels(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  test(
    'overview bounds preserve ink extending beyond its centerline',
    () async {
      final strokes = [
        shape(x: 16, y: 16).copyWith(strokeWidth: 12),
        DrawingStroke(
          colorValue: 0xFF2468AA,
          strokeWidth: 4,
          isFountainPen: true,
          points: StrokePoints.fromNested([
            [16, 24, 18],
            [24, 16, 18],
            [40, 16, 18],
            [48, 24, 18],
          ]),
        ),
        DrawingStroke(
          colorValue: 0xFF2468AA,
          strokeWidth: 12,
          points: StrokePoints.fromNested([
            [32, 32],
          ]),
        ),
      ];
      for (final stroke in strokes) {
        final bounds = whiteboardInkBounds([stroke])!;
        expect(bounds.width, greaterThan(0));
        expect(bounds.height, greaterThan(0));
        final expected = await render((canvas) => drawStroke(canvas, stroke));
        final actual = await render((canvas) {
          canvas.clipRect(bounds, doAntiAlias: false);
          drawStroke(canvas, stroke);
        });
        expect(await pixels(actual), orderedEquals(await pixels(expected)));
      }
    },
  );

  test('centerline-only bounds reproduce the flat top clipping', () async {
    final stroke = shape(x: 16, y: 16).copyWith(strokeWidth: 12);
    final expected = await render((canvas) => drawStroke(canvas, stroke));
    final clipped = await render((canvas) {
      canvas.clipRect(const Rect.fromLTWH(16, 16, 24, 24));
      drawStroke(canvas, stroke);
    });
    const aboveCenterline = (12 * 64 + 28) * 4 + 3;
    expect((await pixels(expected))[aboveCenterline], greaterThan(0));
    expect((await pixels(clipped))[aboveCenterline], 0);
    expect(whiteboardInkBounds([stroke])!.top, lessThan(12));
    expect(whiteboardInkBounds([]), isNull);
  });

  test('whiteboard low zoom preserves shape fill and curved ink', () async {
    final strokes = [
      shape(),
      DrawingStroke(
        colorValue: 0xFF000000,
        strokeWidth: 3,
        points: StrokePoints.fromNested([
          [4, 40],
          [12, 32],
          [20, 48],
          [28, 32],
          [40, 48],
          [52, 40],
        ]),
      ),
    ];
    final expected = await render((canvas) {
      for (final stroke in strokes) {
        drawStroke(canvas, stroke);
      }
    });
    for (final lod in [1, 2]) {
      final actual = await render((canvas) {
        for (final stroke in strokes) {
          drawStroke(canvas, stroke, lod: lod, preserveAppearance: true);
        }
      });
      expect(await pixels(actual), orderedEquals(await pixels(expected)));
    }
    final legacy = await render(
      (canvas) => drawStroke(canvas, strokes.first, lod: 1),
    );
    expect((await pixels(legacy))[(16 * 64 + 16) * 4 + 3], 0);
    expect((await pixels(expected))[(16 * 64 + 16) * 4 + 3], greaterThan(0));
  });

  test(
    'dirty region removes old ink while keeping the cached surroundings',
    () async {
      final old = shape();
      final untouched = shape(x: 36);
      final base = await render((canvas) {
        drawStroke(canvas, old);
        drawStroke(canvas, untouched);
      });
      final expected = await render((canvas) => drawStroke(canvas, untouched));
      final actual = await render((canvas) {
        WhiteboardRasterPainter(
          baseImage: base,
          baseBounds: const Rect.fromLTWH(0, 0, 64, 64),
          visibleWorld: const Rect.fromLTWH(0, 0, 64, 64),
          replacementRegion: const Rect.fromLTWH(0, 0, 32, 64),
        ).paint(canvas, const Size(64, 64));
      });
      expect(await pixels(actual), orderedEquals(await pixels(expected)));
    },
  );

  test('focus replaces translucent overview instead of doubling it', () async {
    final ink = await render((canvas) => drawStroke(canvas, shape()));
    final actual = await render((canvas) {
      WhiteboardRasterPainter(
        baseImage: ink,
        baseBounds: const Rect.fromLTWH(0, 0, 64, 64),
        focusImage: ink,
        focusBounds: const Rect.fromLTWH(0, 0, 64, 64),
        visibleWorld: const Rect.fromLTWH(0, 0, 64, 64),
      ).paint(canvas, const Size(64, 64));
    });
    expect(await pixels(actual), orderedEquals(await pixels(ink)));
  });

  test(
    'new chunks replace overlapping old grid without exposing base',
    () async {
      final ink = await render((canvas) {
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 64, 64),
          Paint()..color = const Color(0x382468AA),
        );
      });
      final actual = await render((canvas) {
        WhiteboardRasterPainter(
          baseImage: ink,
          baseBounds: const Rect.fromLTWH(0, 0, 64, 64),
          prevTiles: [
            WhiteboardRasterTile(const Rect.fromLTWH(0, 0, 48, 64), 0, ink),
          ],
          tiles: [
            WhiteboardRasterTile(const Rect.fromLTWH(32, 0, 32, 64), 1, ink),
          ],
          visibleWorld: const Rect.fromLTWH(0, 0, 64, 64),
        ).paint(canvas, const Size(64, 64));
      });
      final rgba = await pixels(actual);
      for (final x in [8, 31, 32, 40, 47, 48, 56]) {
        expect(rgba[(32 * 64 + x) * 4 + 3], 56, reason: 'Alpha at x=$x');
      }
    },
  );

  test('handoff only paints cells still awaiting refresh', () async {
    final stroke = shape();
    final blank = await render((_) {});
    final ink = await render((canvas) => drawStroke(canvas, stroke));
    final actual = await render((canvas) {
      WhiteboardRasterPainter(
        baseImage: ink,
        baseBounds: const Rect.fromLTWH(0, 0, 64, 64),
        tiles: [
          WhiteboardRasterTile(
            const Rect.fromLTWH(0, 0, 16, 64),
            1,
            ink,
            source: const Rect.fromLTWH(0, 0, 16, 64),
          ),
          WhiteboardRasterTile(const Rect.fromLTWH(16, 0, 48, 64), 1, blank),
        ],
        handoff: [stroke],
        refreshRegions: const [Rect.fromLTWH(16, 0, 48, 64)],
        visibleWorld: const Rect.fromLTWH(0, 0, 64, 64),
      ).paint(canvas, const Size(64, 64));
    });
    expect(await pixels(actual), orderedEquals(await pixels(ink)));
  });

  test('patch includes pending ink outside the edited region', () {
    final old = shape();
    final pending = shape(x: 700, y: 700);
    final region = whiteboardPatchRegion(const Rect.fromLTWH(0, 0, 40, 40), [
      old,
      pending,
    ], 1);
    expect(region.contains(strokeBounds(pending).topLeft), isTrue);
    expect(region.right, greaterThanOrEqualTo(strokeBounds(pending).right));
    expect(region.bottom, greaterThanOrEqualTo(strokeBounds(pending).bottom));
  });

  test(
    'regional raster query deduplicates strokes and preserves edited z order',
    () {
      final index = StrokeTileIndex(tileSize: 16, preserveOrder: true);
      addTearDown(index.dispose);
      final lower = shape();
      final upper = shape(x: 8);
      index.rebuild([lower, upper]);
      final replacement = shape(x: 6);
      index.inheritOrder(lower, replacement);
      index.removeStrokes([lower]);
      index.append(replacement);
      expect(index.strokesInRect(const Rect.fromLTWH(0, 0, 64, 64)), [
        replacement,
        upper,
      ]);
      for (final key in index.tilesInRect(const Rect.fromLTWH(8, 4, 16, 16))) {
        final list = index.strokesAt(key)!;
        if (list.contains(replacement) && list.contains(upper)) {
          expect(list, [replacement, upper]);
        }
      }
    },
  );

  test('pending region survives deletion shifting the append-only count', () {
    final pending = shape(x: 700, y: 700);
    final region = whiteboardPatchRegion(
      const Rect.fromLTWH(0, 0, 40, 40),
      [pending],
      10,
      pendingRegion: strokeBounds(pending),
    );
    expect(region.contains(strokeBounds(pending).center), isTrue);
  });

  test(
    'repeated fractional overview patches preserve pixels outside the edit',
    () async {
      const bounds = Rect.fromLTWH(0.3, 0.7, 97.1, 97.7);
      const scale = 0.65;
      final stroke = shape(x: 55, y: 55);
      var image = await render((canvas) {
        canvas.scale(scale);
        canvas.translate(-bounds.left, -bounds.top);
        drawStroke(canvas, stroke);
      });
      final original = await pixels(image);
      for (var i = 0; i < 8; i++) {
        final picture = recordWhiteboardPatch(
          base: image,
          bounds: bounds,
          region: const Rect.fromLTWH(3.7, 2.1, 21.4, 22.8),
          scale: scale,
          drawRegion: (canvas, _) => drawStroke(canvas, stroke),
        );
        image = await picture.toImage(64, 64);
        picture.dispose();
        addTearDown(image.dispose);
      }
      expect(await pixels(image), orderedEquals(original));
    },
  );

  test('uncached fountain geometry matches the cached low-zoom path', () async {
    final stroke = DrawingStroke(
      colorValue: 0xFF222222,
      strokeWidth: 4,
      isFountainPen: true,
      points: StrokePoints.fromNested([
        [4, 10, 2],
        [12, 13, 5],
        [25, 8, 7],
        [40, 20, 3],
        [56, 15, 1],
      ]),
    );
    final expected = await render(
      (canvas) => drawStroke(canvas, stroke, cache: false),
    );
    final actual = await render(
      (canvas) => drawStroke(canvas, stroke, lod: 2, preserveAppearance: true),
    );
    expect(await pixels(actual), orderedEquals(await pixels(expected)));
  });

  for (final scale in [0.1, 0.3, 0.51, 0.59]) {
    test('tile boundaries retain fill coverage at scale $scale', () async {
      final stroke = DrawingStroke(
        colorValue: 0xFF2468AA,
        strokeWidth: 2,
        filled: true,
        isShape: true,
        points: StrokePoints.fromNested([
          [0, 0],
          [100, 0],
          [100, 100],
          [0, 100],
          [0, 0],
        ]),
      );
      final actual = await render((canvas) {
        canvas.translate(0.37, 0.21);
        canvas.scale(scale);
        for (var x = 0; x < 4; x++) {
          for (var y = 0; y < 4; y++) {
            final origin = Offset(x * 32.0, y * 32.0);
            canvas.save();
            canvas.translate(origin.dx, origin.dy);
            StrokeTilePainter(
              strokes: [stroke],
              tileOrigin: origin,
              version: 1,
              lod: 2,
              preserveAppearance: true,
            ).paint(canvas, const Size(32, 32));
            canvas.restore();
          }
        }
      });
      final rgba = await pixels(actual);
      final end = (90 * scale).floor();
      for (var y = 2; y < end; y++) {
        for (var x = 2; x < end; x++) {
          expect(
            rgba[(y * 64 + x) * 4 + 3],
            closeTo(56, 1),
            reason: 'Pixel $x,$y',
          );
        }
      }
    });
  }
}
