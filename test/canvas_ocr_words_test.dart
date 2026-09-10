import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/domain/models/canvas_ocr.dart';
import 'package:yuli/presentation/screens/flight/canvas_ocr_search.dart';
import 'package:yuli/presentation/screens/flight/canvas_ocr_segmentation.dart';

void main() {
  CanvasInkGroup ink(List<List<Offset>> strokes) =>
      CanvasInkGroup('ink', const Rect.fromLTWH(100, 200, 100, 20), strokes);

  test(
    'Word boxes follow separated ink, including overlapping accent strokes',
    () {
      final words = alignCanvasWords(
        ink([
          [const Offset(0, 0), const Offset(30, 20)],
          [const Offset(9, 0), const Offset(14, 3)],
          [const Offset(55, 0), const Offset(100, 20)],
        ]),
        'Hola, adios',
      );
      expect(words.length, 2);
      expect(words.first.start, 0);
      expect(words.first.end, 4);
      expect(words.first.bounds, const Rect.fromLTWH(100, 200, 30, 20));
      expect(words.last.start, 6);
      expect(words.last.end, 11);
      expect(words.last.bounds, const Rect.fromLTWH(155, 200, 45, 20));
    },
  );

  test('Ambiguous gaps never become estimated character-width underlines', () {
    expect(
      alignCanvasWords(
        ink([
          [const Offset(0, 0), const Offset(100, 20)],
        ]),
        'Dos palabras',
      ),
      isEmpty,
    );
    expect(
      alignCanvasWords(
        ink([
          [const Offset(0, 0), const Offset(10, 20)],
          [const Offset(30, 0), const Offset(40, 20)],
        ]),
        'Palabra',
      ),
      isEmpty,
    );
    expect(
      alignCanvasWords(
        ink([
          [const Offset(0, 0), const Offset(100, 20)],
        ]),
        'Dos\nlíneas',
      ),
      isEmpty,
    );
  });

  const segment = CanvasOcrSegment(
    hash: 'words',
    bounds: Rect.fromLTWH(0, 0, 120, 20),
    text: 'Hola hola',
    alignmentVersion: 1,
    spellingChecked: true,
    words: [
      CanvasOcrWord(0, 4, Rect.fromLTWH(0, 0, 40, 20)),
      CanvasOcrWord(5, 9, Rect.fromLTWH(70, 0, 50, 20)),
    ],
  );

  test(
    'Only an exact word range can be underlined; phrases stay search-only',
    () {
      expect(
        segment.wordBoundsFor(const OcrSpellingSuggestion(0, 4, [])),
        segment.words.first.bounds,
      );
      expect(
        segment.wordBoundsFor(const OcrSpellingSuggestion(0, 9, [])),
        isNull,
      );
      expect(
        segment.wordBoundsFor(const OcrSpellingSuggestion(1, 3, [])),
        isNull,
      );
      expect(segment.boundsForRange(0, 9), segment.bounds);
    },
  );

  test(
    'Find counts each occurrence in reading order and excludes stale pages',
    () {
      final matches = findCanvasOcrMatches([
        const CanvasOcrPage(1, 1, false, [segment]),
        const CanvasOcrPage(2, 1, true, [segment]),
        const CanvasOcrPage(3, 1, true, [segment]),
      ], 'hóla');
      expect(matches.map((m) => m.blockId), [2, 2, 3, 3]);
      expect(matches.map((m) => m.identity).toSet().length, 4);
      expect(matches[0].bounds, segment.words.first.bounds);
      expect(matches[1].bounds, segment.words.last.bounds);
      expect(
        findCanvasOcrMatches([
          const CanvasOcrPage(1, 1, true, [segment]),
        ], ''),
        isEmpty,
      );
    },
  );

  test(
    'Legacy JSON is unchecked, while word geometry and successful review round-trip',
    () {
      final json = segment.toJson();
      final restored = CanvasOcrSegment.fromJson(json);
      expect(restored.words.last.bounds, segment.words.last.bounds);
      expect(restored.spellingChecked, isTrue);
      json.remove('spellingChecked');
      json.remove('alignmentVersion');
      json.remove('words');
      final legacy = CanvasOcrSegment.fromJson(json);
      expect(legacy.spellingChecked, isFalse);
      expect(legacy.alignmentVersion, 0);
      expect(legacy.words, isEmpty);
      expect(legacy.reviewed(null).spellingChecked, isFalse);
      expect(legacy.reviewed([]).spellingChecked, isTrue);
    },
  );
}
