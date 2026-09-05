import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/notebook_raster_state.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/stroke_tiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('low zoom notebook tiles retain fill and clip to the page', () async {
    final stroke = DrawingStroke(
      colorValue: 0xFF2468AA,
      strokeWidth: 2,
      filled: true,
      isShape: true,
      points: StrokePoints.fromNested([
        [0, 0],
        [620, 0],
        [620, 850],
        [0, 850],
        [0, 0],
      ]),
    );
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)..scale(0.5);
    for (var x = 0; x < 3; x++) {
      for (var y = 0; y < 4; y++) {
        final origin = Offset(x * 256.0, y * 256.0);
        canvas.save();
        canvas.translate(origin.dx, origin.dy);
        StrokeTilePainter(
          strokes: [stroke],
          tileOrigin: origin,
          version: 1,
          lod: 2,
          preserveAppearance: true,
          clipBounds: const Rect.fromLTWH(0, 0, 595, 842),
        ).paint(canvas, const Size(256, 256));
        canvas.restore();
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(320, 440);
    picture.dispose();
    addTearDown(image.dispose);
    final pixels =
        (await image.toByteData(
          format: ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
    for (var y = 10; y < 410; y++) {
      for (var x = 10; x < 290; x++) {
        expect(
          pixels[(y * 320 + x) * 4 + 3],
          closeTo(56, 1),
          reason: 'Page pixel $x,$y',
        );
      }
    }
    expect(pixels[(100 * 320 + 305) * 4 + 3], 0);
    expect(pixels[(430 * 320 + 100) * 4 + 3], 0);
  });

  test('an edit includes recent ink outside the edited region', () {
    final state = NotebookRasterState();
    const ink = Rect.fromLTWH(10, 10, 20, 20);
    const erase = Rect.fromLTWH(400, 700, 30, 30);
    state.append(ink);
    expect(state.edit(erase), ink.expandToInclude(erase));
  });

  test('ink appended while an edit is baking stays in its replacement', () {
    final state = NotebookRasterState();
    const erase = Rect.fromLTWH(10, 10, 30, 30);
    const ink = Rect.fromLTWH(400, 700, 20, 20);
    state.edit(erase);
    state.append(ink);
    state.queue(erase);
    expect(state.edit(state.queuedPatch!), erase.expandToInclude(ink));
  });

  test('overlapping asynchronous edits retain both regions for retry', () {
    final state = NotebookRasterState();
    const first = Rect.fromLTWH(10, 10, 20, 20);
    const second = Rect.fromLTWH(400, 700, 20, 20);
    state.queue(first);
    state.queue(second);
    expect(state.queuedPatch, first.expandToInclude(second));
  });

  test(
    'accepting a bake clears pending regions without resetting generation',
    () {
      final state = NotebookRasterState()..generation = 3;
      const region = Rect.fromLTWH(10, 10, 20, 20);
      state.append(region);
      state.edit(region);
      state.queue(region);
      state.accept();
      expect(state.pendingInk, isNull);
      expect(state.editedRegion, isNull);
      expect(state.queuedPatch, isNull);
      expect(state.generation, 3);
    },
  );

  test('editing another page does not inherit the first page pending ink', () {
    final first = NotebookRasterState();
    final second = NotebookRasterState();
    first.append(const Rect.fromLTWH(10, 10, 20, 20));
    const region = Rect.fromLTWH(400, 700, 20, 20);
    expect(second.edit(region), region);
    expect(first.pendingInk, isNotNull);
  });
}
