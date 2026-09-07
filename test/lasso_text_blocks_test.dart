import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/lasso_controller.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';

void main() {
  test(
    'duplicate text block gives it a new id and preserves wiki markdown',
    () {
      final controller =
          LassoController()
            ..selectedTextBlockIndices = {0}
            ..boundingBox = const Rect.fromLTWH(10, 20, 100, 50);
      final blocks = [
        CanvasTextBlock(x: 10, y: 20, w: 100, h: 50, markdown: '[[Clase]]'),
      ];
      final id = blocks.single.id;

      controller.duplicateSelected([], [], [], blocks);

      expect(blocks, hasLength(2));
      expect(blocks.last.id, isNot(id));
      expect(blocks.last.markdown, '[[Clase]]');
      expect(blocks.last.x, 25);
      expect(blocks.last.y, 35);
      expect(controller.selectedTextBlockIndices, {1});
    },
  );

  test('copy and paste text block preserve its content with a new id', () {
    final controller =
        LassoController()
          ..selectedTextBlockIndices = {0}
          ..boundingBox = const Rect.fromLTWH(10, 20, 100, 50);
    final source = CanvasTextBlock(
      x: 10,
      y: 20,
      w: 100,
      h: 50,
      markdown: '[[Clase]]',
    );
    final original = [source];

    controller.copySelected([], [], original);
    final pasted = <CanvasTextBlock>[];
    controller.pasteAt(const Offset(200, 300), [], [], 0, pasted);

    expect(pasted, hasLength(1));
    expect(pasted.single.id, isNot(source.id));
    expect(pasted.single.markdown, '[[Clase]]');
    expect(pasted.single.x, 150);
    expect(pasted.single.y, 275);
  });

  test('cut moves text blocks but leaves task blocks in place', () {
    final controller =
        LassoController()
          ..selectedBlockIndices = {0}
          ..selectedTextBlockIndices = {0}
          ..boundingBox = const Rect.fromLTWH(10, 20, 100, 50);
    final tasks = [CanvasTaskBlock(x: 10, y: 20, w: 100, h: 50)];
    final text = [
      CanvasTextBlock(x: 10, y: 20, w: 100, h: 50, markdown: 'Texto'),
    ];

    controller.cutSelected([], [], tasks, text);

    expect(tasks, hasLength(1));
    expect(text, isEmpty);
    expect(controller.hasClipboard, isTrue);
  });
}
