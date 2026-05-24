import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as m;

class InspectBlockSyntax extends m.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^\$\$');

  @override
  m.Node? parse(m.BlockParser parser) {
    final currentLine = parser.current;
    print('currentLine runtimeType: ${currentLine.runtimeType}');
    
    // We can use dart:mirrors or simply print its properties we can find via code.
    // Let's see if currentLine has a 'content' or 'text' property by trying to compile/print.
    // We will print:
    try {
      print('currentLine.content: ${(currentLine as dynamic).content}');
    } catch (e) {
      print('content property failed: $e');
    }
    
    try {
      print('currentLine.text: ${(currentLine as dynamic).text}');
    } catch (e) {
      print('text property failed: $e');
    }

    try {
      print('currentLine.value: ${(currentLine as dynamic).value}');
    } catch (e) {
      print('value property failed: $e');
    }

    parser.advance();
    return null;
  }
}

void main() {
  test('Inspect BlockParser lines', () {
    final document = m.Document(blockSyntaxes: [InspectBlockSyntax()]);
    document.parseLines(['\$\$', 'formula', '\$\$']);
  });
}
