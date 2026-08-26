import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:markdown/markdown.dart' as md;

const yuliCodeBlockType = 'code';
const yuliLatexBlockType = 'latex_block';
const yuliLatexBlockContent = 'latex';
const _yuliTableBreakToken = '\uE000';
final _yuliTableBreakPattern = RegExp(r'<br\s*/?>', caseSensitive: false);

class YuliMarkdownDocument {
  const YuliMarkdownDocument._();

  static Document decode(String markdown) {
    final root = pageNode(children: []);
    final document = Document(root: root);
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final plain = StringBuffer();

    void appendPlain() {
      if (plain.isEmpty) return;
      final decoded = markdownToDocument(
        _prepareTableLineBreaks(plain.toString()),
        markdownParsers: const [_CodeMarkdownParser()],
      );
      final nodes = _visibleSourceNodes(decoded.root.children);
      _normalizeNodes(nodes);
      if (nodes.isNotEmpty) {
        for (final node in nodes) {
          root.insert(node);
        }
      }
      plain.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed == r'$$') {
        var end = i + 1;
        while (end < lines.length && lines[end].trim() != r'$$') {
          end++;
        }
        if (end < lines.length) {
          appendPlain();
          root.insert(
            Node(
              type: yuliLatexBlockType,
              attributes: {
                yuliLatexBlockContent: lines.sublist(i + 1, end).join('\n'),
              },
            ),
          );
          i = end;
          continue;
        }
      }
      if (!trimmed.startsWith(':::')) {
        if (trimmed == '***' || trimmed == '___' || trimmed == '---') {
          appendPlain();
          root.insert(paragraphNode(delta: Delta()..insert(lines[i])));
          continue;
        }
        plain.writeln(lines[i]);
        continue;
      }
      final align = trimmed.substring(3).trim();
      if (align != 'left' && align != 'center' && align != 'right') {
        plain.writeln(lines[i]);
        continue;
      }
      var end = i + 1;
      while (end < lines.length && lines[end].trim() != ':::') {
        end++;
      }
      if (end >= lines.length) {
        plain.writeln(lines[i]);
        continue;
      }
      appendPlain();
      final inner = lines.sublist(i + 1, end).join('\n');
      final decoded = decode(inner);
      final nodes =
          decoded.root.children.map((node) => node.deepCopy()).toList();
      _normalizeNodes(nodes);
      for (final node in nodes) {
        node.updateAttributes({
          blockComponentAlign: align,
          if (node.type == ImageBlockKeys.type) ImageBlockKeys.align: align,
        });
      }
      if (nodes.isNotEmpty) {
        for (final node in nodes) {
          root.insert(node);
        }
      }
      i = end;
    }
    appendPlain();
    if (root.children.isEmpty) {
      root.insert(paragraphNode());
    }
    return document;
  }

  static String encode(Document document) {
    final buffer = StringBuffer();
    String? openAlign;

    void closeAlign() {
      if (openAlign == null) return;
      buffer.writeln(':::');
      openAlign = null;
    }

    for (final node in document.root.children) {
      final align =
          node.type == ImageBlockKeys.type
              ? node.attributes[ImageBlockKeys.align] as String?
              : node.attributes[blockComponentAlign] as String?;
      if (align != openAlign) {
        closeAlign();
        if (align != null) {
          openAlign = align;
          buffer.writeln('::: $align');
        }
      }
      final isolated = Document(root: pageNode(children: [node.deepCopy()]));
      final encoded =
          node.type == yuliLatexBlockType
              ? '\$\$\n${node.attributes[yuliLatexBlockContent] ?? ''}\n\$\$'
              : node.type == TableBlockKeys.type
              ? _encodeTable(node)
              : node.delta != null && node.type != yuliCodeBlockType
              ? node.delta!.toPlainText()
              : documentToMarkdown(isolated).trimRight();
      if (encoded.isNotEmpty) {
        buffer.writeln(encoded);
      } else if (node.type == ParagraphBlockKeys.type) {
        buffer.writeln();
      }
    }
    closeAlign();
    return buffer.toString().trimRight();
  }

  static void _normalizeNodes(Iterable<Node> nodes) {
    for (final node in nodes) {
      if (node.type == ImageBlockKeys.type) {
        final url = node.attributes[ImageBlockKeys.url] as String?;
        final width = node.attributes[ImageBlockKeys.width] as num?;
        final align =
            node.attributes[blockComponentAlign] as String? ??
            node.attributes[ImageBlockKeys.align] as String? ??
            'center';
        if (url != null) {
          node.updateAttributes({
            ImageBlockKeys.url: Uri.decodeFull(url),
            ImageBlockKeys.align: align,
            ImageBlockKeys.width:
                width == null ? 320.0 : width.toDouble().clamp(160.0, 520.0),
            ImageBlockKeys.height: null,
          });
        }
      }
      if (node.type == TableBlockKeys.type) {
        _restoreTableLineBreaks(node);
      }
      _normalizeNodes(node.children);
    }
  }

  static List<Node> _visibleSourceNodes(Iterable<Node> nodes) {
    final result = <Node>[];
    for (final node in nodes) {
      if (node.delta == null || node.type == yuliCodeBlockType) {
        result.add(node);
        continue;
      }
      final isolated = Document(root: pageNode(children: [node.deepCopy()]));
      final source = documentToMarkdown(isolated).trimRight();
      final lines = source.split('\n');
      for (final line in lines) {
        result.add(paragraphNode(delta: Delta()..insert(line)));
      }
    }
    return result;
  }
}

String _prepareTableLineBreaks(String source) {
  return source
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map(
        (line) =>
            line.trimLeft().startsWith('|')
                ? line.replaceAll(_yuliTableBreakPattern, _yuliTableBreakToken)
                : line,
      )
      .join('\n');
}

void _restoreTableLineBreaks(Node table) {
  for (final cell in table.children) {
    if (cell.type != TableCellBlockKeys.type) continue;
    for (final child in cell.children) {
      final delta = child.delta;
      if (delta == null) continue;
      final text = delta.toPlainText();
      if (!text.contains(_yuliTableBreakToken)) continue;
      child.updateAttributes({
        blockComponentDelta:
            (Delta()..insert(text.replaceAll(_yuliTableBreakToken, '\n')))
                .toJson(),
      });
    }
  }
}

String _encodeTable(Node table) {
  final rows = (table.attributes[TableBlockKeys.rowsLen] as num).toInt();
  final cols = (table.attributes[TableBlockKeys.colsLen] as num).toInt();
  final lines = <String>[];
  for (var row = 0; row < rows; row++) {
    final cells = <String>[];
    for (var col = 0; col < cols; col++) {
      final cell = _tableCellAt(table, col, row);
      cells.add(cell == null ? ' ' : _encodeTableCell(cell));
    }
    lines.add('|${cells.join('|')}|');
    if (row == 0) {
      lines.add('|${List.filled(cols, '---').join('|')}|');
    }
  }
  return lines.join('\n');
}

Node? _tableCellAt(Node table, int col, int row) {
  for (final child in table.children) {
    if (child.type == TableCellBlockKeys.type &&
        child.attributes[TableCellBlockKeys.colPosition] == col &&
        child.attributes[TableCellBlockKeys.rowPosition] == row) {
      return child;
    }
  }
  return null;
}

String _encodeTableCell(Node cell) {
  final source =
      cell.children
          .map((child) {
            if (child.delta != null && child.type != yuliCodeBlockType) {
              final text = child.delta!.toPlainText();
              if (_tableCellLooksLikeMarkdownSource(text)) return text;
            }
            return documentToMarkdown(
              Document(root: pageNode(children: [child.deepCopy()])),
            ).trimRight();
          })
          .join('\n')
          .trimRight();
  final normalized =
      source.isEmpty
          ? ' '
          : source
              .replaceAll('\r\n', '\n')
              .split('\n')
              .map((line) => line.replaceAll('|', r'\|'))
              .join('<br>');
  return normalized;
}

bool _tableCellLooksLikeMarkdownSource(String text) {
  return RegExp(
    r'(^|\n)\s*(#{1,6}\s|>\s?|[-+*]\s+\[[ xX]\]\s+|[-+*]\s+|\d+[.)]\s+)|(\*\*|__|~~|==|`|\$|\*[^*\n]+\*|_[^_\n]+_)',
  ).hasMatch(text);
}

class _CodeMarkdownParser extends CustomMarkdownParser {
  const _CodeMarkdownParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'pre') return const [];
    final children = element.children;
    final child = children == null || children.isEmpty ? null : children.first;
    if (child is! md.Element || child.tag != 'code') return const [];
    final className = child.attributes['class'] ?? '';
    final language =
        className.startsWith('language-') ? className.substring(9) : '';
    return [
      Node(
        type: yuliCodeBlockType,
        attributes: {
          blockComponentDelta:
              (Delta()..insert(
                    child.textContent.replaceFirst(RegExp(r'\n$'), ''),
                  ))
                  .toJson(),
          'language': language,
        },
      ),
    ];
  }
}
