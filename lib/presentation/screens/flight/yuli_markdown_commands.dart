import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'yuli_markdown_document.dart';

const yuliMarkdownMarker = 'yuli_markdown_marker';
const yuliMarkdownBlockMarker = 'yuli_markdown_block_marker';
const yuliMarkdownDomainStart = 'yuli_markdown_domain_start';
const yuliMarkdownDomainEnd = 'yuli_markdown_domain_end';
const yuliHeadingLevel = 'yuli_heading_level';
const yuliQuoteText = 'yuli_quote_text';
const yuliHighlight = 'yuli_highlight';
const yuliLatex = 'yuli_latex';
const yuliLatexDisplay = 'yuli_latex_display';
const yuliWikiLink = 'yuli_wiki_link';

final Expando<String> _preferredAlignment = Expando<String>();

final _yuliBlockPrefixPattern = RegExp(
  r'^(#{1,6}\s+|>\s?|(?:[-+*]|\d+[.)])\s+|[-+*]\s+\[[ xX]\]\s+)',
);

List<CharacterShortcutEvent> get yuliMarkdownCharacterShortcuts => [
  _insertNewLineWithAlignment,
  _pairShortcut('*'),
  _pairShortcut('_'),
  _pairShortcut('`'),
  _pairShortcut('~'),
  _pairShortcut(r'$'),
  ...standardCharacterShortcutEvents.where(
    (event) =>
        event != formatAsteriskToBulletedList &&
        event != formatMinusToBulletedList &&
        event != formatNumberToNumberedList &&
        event != formatDoubleQuoteToQuote &&
        event != formatSignToHeading &&
        event != formatEmptyBracketsToUncheckedBox &&
        event != formatHyphenEmptyBracketsToUncheckedBox &&
        event != formatFilledBracketsToCheckedBox &&
        event != formatHyphenFilledBracketsToCheckedBox &&
        event != convertMinusesToDivider &&
        event != convertStarsToDivider &&
        event != convertUnderscoreToDivider &&
        !markdownSyntaxShortcutEvents.contains(event) &&
        event != formatGreaterEqual,
  ),
];

List<CommandShortcutEvent> get yuliMarkdownCommandShortcuts => [
  _tableCellLineBreakCommand(key: 'YuLi table cell newline', command: 'enter'),
  _tableCellLineBreakCommand(
    key: 'YuLi table cell shift newline',
    command: 'shift+enter',
  ),
  _wrapMarkdownCommand(
    key: 'YuLi markdown bold',
    command: 'ctrl+b',
    macOSCommand: 'cmd+b',
    marker: '**',
  ),
  _wrapMarkdownCommand(
    key: 'YuLi markdown italic',
    command: 'ctrl+i',
    macOSCommand: 'cmd+i',
    marker: '*',
  ),
  _wrapMarkdownCommand(
    key: 'YuLi markdown strike',
    command: 'ctrl+shift+s',
    macOSCommand: 'cmd+shift+s',
    marker: '~~',
  ),
  _wrapMarkdownCommand(
    key: 'YuLi markdown code',
    command: 'ctrl+e',
    macOSCommand: 'cmd+e',
    marker: '`',
  ),
  _wrapMarkdownCommand(
    key: 'YuLi markdown highlight',
    command: 'ctrl+shift+h',
    macOSCommand: 'cmd+shift+h',
    marker: '==',
  ),
  _lineMarkdownCommand(
    key: 'YuLi markdown H1',
    command: 'ctrl+shift+t',
    macOSCommand: 'cmd+shift+t',
    prefix: '# ',
  ),
  _lineMarkdownCommand(
    key: 'YuLi markdown H2',
    command: 'ctrl+shift+g',
    macOSCommand: 'cmd+shift+g',
    prefix: '## ',
  ),
  _lineMarkdownCommand(
    key: 'YuLi markdown H3',
    command: 'ctrl+shift+j',
    macOSCommand: 'cmd+shift+j',
    prefix: '### ',
  ),
  _lineMarkdownCommand(
    key: 'YuLi markdown body',
    command: 'ctrl+shift+b',
    macOSCommand: 'cmd+shift+b',
    prefix: '',
  ),
  _taskMarkdownCommand,
  ...standardCommandShortcutEvents.where(
    (event) =>
        event != toggleTodoListCommand &&
        !toggleMarkdownCommands.contains(event) &&
        !_yuliBlockedCommandKeys.contains(event.key) &&
        event != toggleHighlightCommand &&
        event != showLinkMenuCommand &&
        event != openInlineLinkCommand &&
        event != openLinksCommand &&
        event != indentCommand &&
        event != outdentCommand,
  ),
];

CommandShortcutEvent _tableCellLineBreakCommand({
  required String key,
  required String command,
}) => CommandShortcutEvent(
  key: key,
  command: command,
  getDescription: null,
  handler: (editorState) {
    if (!_isTableCellTextSelection(editorState)) {
      return KeyEventResult.ignored;
    }
    unawaited(insertTableCellLineBreak(editorState));
    return KeyEventResult.handled;
  },
);

bool _isTableCellTextSelection(EditorState editorState) {
  final selection = editorState.selection?.normalized;
  if (selection == null || !selection.isSingle) return false;
  final node = editorState.getNodeAtPath(selection.start.path);
  return node?.delta != null && node?.parent?.type == TableCellBlockKeys.type;
}

Future<void> insertTableCellLineBreak(EditorState editorState) async {
  var selection = editorState.selection?.normalized;
  if (selection == null || !selection.isSingle) return;
  if (!selection.isCollapsed) {
    await editorState.deleteSelection(selection);
    selection = editorState.selection?.normalized;
    if (selection == null || !selection.isCollapsed) return;
  }
  final node = editorState.getNodeAtPath(selection.start.path);
  if (node?.delta == null || node?.parent?.type != TableCellBlockKeys.type) {
    return;
  }
  final cell = node!.parent!;
  final table = cell.parent;
  final nextText = node.delta!.toPlainText().replaceRange(
    selection.start.offset,
    selection.start.offset,
    '\n',
  );
  final transaction =
      editorState.transaction
        ..insertText(node, selection.start.offset, '\n')
        ..afterSelection = Selection.collapsed(
          Position(path: node.path, offset: selection.start.offset + 1),
        );
  if (table != null) {
    _applyEstimatedTableRowHeight(
      transaction: transaction,
      table: table,
      row: cell.attributes[TableCellBlockKeys.rowPosition] as int,
      editedCell: cell,
      editedText: nextText,
    );
  }
  await editorState.apply(transaction);
}

void _applyEstimatedTableRowHeight({
  required Transaction transaction,
  required Node table,
  required int row,
  required Node editedCell,
  required String editedText,
}) {
  if (table.type != TableBlockKeys.type) return;
  final rowsLen = table.attributes[TableBlockKeys.rowsLen] as int? ?? 0;
  if (rowsLen == 0) return;

  final borderWidth =
      (table.attributes[TableBlockKeys.borderWidth] as num?)?.toDouble() ??
      TableDefaults.borderWidth;
  final defaultHeight =
      (table.attributes[TableBlockKeys.rowDefaultHeight] as num?)?.toDouble() ??
      TableDefaults.rowHeight;
  var maxLines = 1;
  for (final cell in table.children) {
    if (cell.type != TableCellBlockKeys.type ||
        cell.attributes[TableCellBlockKeys.rowPosition] != row) {
      continue;
    }
    final source =
        identical(cell, editedCell)
            ? editedText
            : cell.children.isEmpty
            ? ''
            : cell.children.first.delta?.toPlainText() ?? '';
    maxLines = maxLines < _lineCount(source) ? _lineCount(source) : maxLines;
  }

  final estimatedHeight = _estimatedTableCellHeight(
    lines: maxLines,
    defaultHeight: defaultHeight,
  );
  var rowChanged = false;
  for (final cell in table.children) {
    if (cell.type != TableCellBlockKeys.type ||
        cell.attributes[TableCellBlockKeys.rowPosition] != row) {
      continue;
    }
    final current =
        (cell.attributes[TableCellBlockKeys.height] as num?)?.toDouble() ??
        defaultHeight;
    if (current < estimatedHeight) {
      transaction.updateNode(cell, {
        TableCellBlockKeys.height: estimatedHeight,
      });
      rowChanged = true;
    }
  }
  if (!rowChanged) return;

  var colsHeight = borderWidth;
  for (var currentRow = 0; currentRow < rowsLen; currentRow++) {
    Node? firstCell;
    for (final cell in table.children) {
      if (cell.type == TableCellBlockKeys.type &&
          cell.attributes[TableCellBlockKeys.rowPosition] == currentRow) {
        firstCell = cell;
        break;
      }
    }
    final height =
        currentRow == row
            ? estimatedHeight
            : (firstCell?.attributes[TableCellBlockKeys.height] as num?)
                    ?.toDouble() ??
                defaultHeight;
    colsHeight += height + borderWidth;
  }
  transaction.updateNode(table, {TableBlockKeys.colsHeight: colsHeight});
}

int _lineCount(String text) => '\n'.allMatches(text).length + 1;

double _estimatedTableCellHeight({
  required int lines,
  required double defaultHeight,
}) {
  if (lines <= 1) return defaultHeight;
  return (18 + lines * 26).clamp(defaultHeight, 420).toDouble();
}

const _yuliBlockedCommandKeys = {
  'toggle into Heading 1',
  'toggle into Heading 2',
  'toggle into Heading 3',
  'toggle Body',
};

CommandShortcutEvent _wrapMarkdownCommand({
  required String key,
  required String command,
  required String macOSCommand,
  required String marker,
}) => CommandShortcutEvent(
  key: key,
  command: command,
  getDescription: null,
  macOSCommand: macOSCommand,
  handler: (editorState) {
    final selection = editorState.selection?.normalized;
    if (selection == null || !selection.isSingle) {
      return KeyEventResult.ignored;
    }
    unawaited(wrapMarkdownSelection(editorState, marker));
    return KeyEventResult.handled;
  },
);

CommandShortcutEvent _lineMarkdownCommand({
  required String key,
  required String command,
  required String macOSCommand,
  required String prefix,
}) => CommandShortcutEvent(
  key: key,
  command: command,
  getDescription: null,
  macOSCommand: macOSCommand,
  handler: (editorState) {
    final selection = editorState.selection?.normalized;
    if (selection == null || !selection.isSingle) {
      return KeyEventResult.ignored;
    }
    unawaited(
      applyMarkdownLinePrefix(
        editorState,
        prefix,
        removePattern: _yuliBlockPrefixPattern,
      ),
    );
    return KeyEventResult.handled;
  },
);

final CommandShortcutEvent _taskMarkdownCommand = CommandShortcutEvent(
  key: 'YuLi markdown task',
  command: 'ctrl+enter',
  getDescription: null,
  macOSCommand: 'cmd+enter',
  handler: (editorState) {
    final selection = editorState.selection?.normalized;
    if (selection == null || !selection.isSingle) {
      return KeyEventResult.ignored;
    }
    unawaited(toggleMarkdownTaskAtSelection(editorState));
    return KeyEventResult.handled;
  },
);

String preferredMarkdownAlignment(EditorState editorState) {
  final preferred = _preferredAlignment[editorState];
  if (preferred != null) return preferred;
  final selection = editorState.selection;
  final node =
      selection == null
          ? null
          : editorState.getNodeAtPath(selection.start.path);
  return node?.attributes[blockComponentAlign] as String? ?? 'left';
}

void setPreferredMarkdownAlignment(EditorState editorState, String alignment) {
  _preferredAlignment[editorState] = alignment;
}

Future<void> insertMarkdownAtSelection(
  EditorState editorState,
  Selection selection,
  String markdown,
) async {
  editorState.selection = selection;
  var target = selection.normalized;
  if (!target.isCollapsed) {
    await editorState.deleteSelection(target);
    final updated = editorState.selection?.normalized;
    if (updated == null) return;
    target = updated;
  }

  final node = editorState.getNodeAtPath(target.start.path);
  if (node?.delta == null) return;

  if (!markdown.contains('\n')) {
    final transaction =
        editorState.transaction
          ..insertText(node!, target.start.offset, markdown)
          ..afterSelection = Selection.collapsed(
            Position(
              path: node.path,
              offset: target.start.offset + markdown.length,
            ),
          );
    await editorState.apply(transaction);
    return;
  }

  final source = markdown
      .replaceFirst(RegExp(r'^\n+'), '')
      .replaceFirst(RegExp(r'\n+$'), '');
  if (source.isEmpty) return;
  final inserted =
      YuliMarkdownDocument.decode(
        source,
      ).root.children.map((node) => node.deepCopy()).toList();
  if (inserted.isEmpty) return;

  final current = node!;
  final before = current.delta!.slice(0, target.start.offset);
  final after = current.delta!.slice(
    target.start.offset,
    current.delta!.length,
  );
  final path = current.path;
  final nodes = <Node>[
    if (before.isNotEmpty)
      Node(
        type: current.type,
        attributes: {
          ...current.attributes,
          blockComponentDelta: before.toJson(),
        },
        children: const [],
      ),
    ...inserted,
    if (after.isNotEmpty)
      Node(
        type: current.type,
        attributes: {
          ...current.attributes,
          blockComponentDelta: after.toJson(),
        },
        children: const [],
      ),
  ];
  final transaction = editorState.transaction;
  transaction.insertNodes(path, nodes);
  transaction.deleteNode(current);
  final insertedEndIndex =
      path.first + (before.isNotEmpty ? 1 : 0) + inserted.length - 1;
  final last = inserted.last;
  transaction.afterSelection = Selection.collapsed(
    Position(path: [insertedEndIndex], offset: last.delta?.length ?? 0),
  );
  await editorState.apply(transaction);
}

final CharacterShortcutEvent _insertNewLineWithAlignment =
    CharacterShortcutEvent(
      key: 'YuLi insert newline with alignment',
      character: '\n',
      handler: (editorState) async {
        var selection = editorState.selection?.normalized;
        if (selection == null) return false;
        final node = editorState.getNodeAtPath(selection.start.path);
        if (node == null) return false;
        if (node.path.length == 1 &&
            selection.start.path.equals(selection.end.path) &&
            (node.type == ImageBlockKeys.type ||
                node.type == TableBlockKeys.type ||
                node.type == yuliLatexBlockType)) {
          final path = [node.path.first + 1];
          final transaction =
              editorState.transaction
                ..insertNode(path, paragraphNode())
                ..afterSelection = Selection.collapsed(Position(path: path));
          await editorState.apply(transaction);
          return true;
        }
        if (node.type != ParagraphBlockKeys.type) return false;

        if (!selection.isCollapsed) {
          await editorState.deleteSelection(selection);
          selection = editorState.selection?.normalized;
          if (selection == null || !selection.isCollapsed) return true;
        }

        final alignment = preferredMarkdownAlignment(editorState);
        await editorState.insertNewLine(
          position: selection.start,
          nodeBuilder:
              (newNode) => newNode.copyWith(
                attributes: {
                  ...newNode.attributes,
                  if (alignment != 'left') blockComponentAlign: alignment,
                },
              ),
        );
        return true;
      },
    );

bool isMarkdownMarkerActive({
  required Map<String, dynamic> attributes,
  required bool selectionIsInNode,
  required int selectionStart,
  required int selectionEnd,
}) {
  if (!selectionIsInNode) return false;
  if (attributes[yuliMarkdownBlockMarker] == true) return true;
  final domainStart = attributes[yuliMarkdownDomainStart] as int?;
  final domainEnd = attributes[yuliMarkdownDomainEnd] as int?;
  return domainStart != null &&
      domainEnd != null &&
      selectionStart <= domainEnd &&
      selectionEnd >= domainStart;
}

int? snapHiddenMarkdownMarkerCaretOffset({
  required String text,
  required int offset,
  int? previousOffset,
}) {
  if (offset <= 0 || offset >= text.length) return null;

  var cursor = 0;
  for (final operation in buildLiveMarkdownDelta(text).toList()) {
    if (operation is! TextInsert) continue;
    final start = cursor;
    final end = cursor + operation.text.length;
    cursor = end;
    if (offset <= start || offset >= end) continue;

    final attributes = operation.attributes ?? const <String, dynamic>{};
    if (attributes[yuliMarkdownMarker] != true ||
        attributes[yuliMarkdownBlockMarker] == true) {
      continue;
    }

    final domainStart = attributes[yuliMarkdownDomainStart] as int?;
    final domainEnd = attributes[yuliMarkdownDomainEnd] as int?;
    if (domainStart == null || domainEnd == null) continue;

    final movingRight = previousOffset == null || offset > previousOffset;
    if (end <= domainStart) return movingRight ? domainStart : start;
    if (start >= domainEnd) return movingRight ? end : domainEnd;
    return movingRight ? end : start;
  }
  return null;
}

CharacterShortcutEvent _pairShortcut(String character) =>
    CharacterShortcutEvent(
      key: 'YuLi pair $character',
      character: character,
      handler: (editorState) => pairMarkdownCharacter(editorState, character),
    );

Future<bool> pairMarkdownCharacter(
  EditorState editorState,
  String character,
) async {
  final selection = editorState.selection?.normalized;
  if (selection == null || !selection.isSingle) return false;
  final node = editorState.getNodeAtPath(selection.start.path);
  final delta = node?.delta;
  if (node == null || delta == null) return false;

  if (!selection.isCollapsed) {
    final start = selection.start.offset;
    final end = selection.end.offset;
    final transaction =
        editorState.transaction
          ..insertText(node, end, character)
          ..insertText(node, start, character)
          ..afterSelection = Selection.single(
            path: node.path,
            startOffset: start + 1,
            endOffset: end + 1,
          );
    await editorState.apply(transaction);
    return true;
  }

  final offset = selection.start.offset;
  final text = delta.toPlainText();
  final previous = offset > 0 ? text[offset - 1] : null;
  final next = offset < text.length ? text[offset] : null;

  if (previous == character && next == character) {
    final transaction =
        editorState.transaction
          ..insertText(node, offset, '$character$character')
          ..afterSelection = Selection.collapsed(
            Position(path: node.path, offset: offset + 1),
          );
    await editorState.apply(transaction);
    return true;
  }

  if (next == character) {
    await editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: node.path, offset: offset + 1)),
      reason: SelectionUpdateReason.uiEvent,
    );
    return true;
  }

  final transaction =
      editorState.transaction
        ..insertText(node, offset, '$character$character')
        ..afterSelection = Selection.collapsed(
          Position(path: node.path, offset: offset + 1),
        );
  await editorState.apply(transaction);
  return true;
}

Future<void> wrapMarkdownSelection(
  EditorState editorState,
  String marker,
) async {
  final selection = editorState.selection?.normalized;
  if (selection == null || !selection.isSingle) return;
  final node = editorState.getNodeAtPath(selection.start.path);
  if (node?.delta == null) return;

  final start = selection.start.offset;
  final end = selection.end.offset;
  final transaction =
      editorState.transaction
        ..insertText(node!, end, marker)
        ..insertText(node, start, marker)
        ..afterSelection =
            selection.isCollapsed
                ? Selection.collapsed(
                  Position(path: node.path, offset: start + marker.length),
                )
                : Selection.single(
                  path: node.path,
                  startOffset: start + marker.length,
                  endOffset: end + marker.length,
                );
  await editorState.apply(transaction);
}

Future<void> applyMarkdownLinePrefix(
  EditorState editorState,
  String prefix, {
  RegExp? removePattern,
  bool replaceLine = false,
}) async {
  final selection = editorState.selection?.normalized;
  if (selection == null || !selection.isSingle) return;
  final node = editorState.getNodeAtPath(selection.start.path);
  final delta = node?.delta;
  if (node == null || delta == null) return;
  final source = delta.toPlainText();
  final next =
      replaceLine
          ? prefix
          : '$prefix${removePattern == null ? source : source.replaceFirst(removePattern, '')}';
  final transaction =
      editorState.transaction
        ..updateNode(node, {
          blockComponentDelta: (Delta()..insert(next)).toJson(),
        })
        ..afterSelection = Selection.collapsed(
          Position(
            path: node.path,
            offset:
                selection.isCollapsed
                    ? (selection.start.offset + next.length - source.length)
                        .clamp(prefix.length, next.length)
                    : next.length,
          ),
        );
  await editorState.apply(transaction);
}

Future<void> toggleMarkdownTaskAtSelection(EditorState editorState) async {
  final selection = editorState.selection?.normalized;
  if (selection == null || !selection.isSingle) return;
  final node = editorState.getNodeAtPath(selection.start.path);
  final delta = node?.delta;
  if (node == null || delta == null) return;

  final source = delta.toPlainText();
  final task = RegExp(r'^(\s*)[-+*]\s+\[([ xX])\]\s+').firstMatch(source);
  if (task == null) {
    await applyMarkdownLinePrefix(
      editorState,
      '- [ ] ',
      removePattern: _yuliBlockPrefixPattern,
    );
    return;
  }

  final checked = task.group(2)!.toLowerCase() == 'x';
  final nextMarker = '${task.group(1)!}- [${checked ? ' ' : 'x'}] ';
  final next = source.replaceRange(task.start, task.end, nextMarker);
  final transaction =
      editorState.transaction
        ..updateNode(node, {
          blockComponentDelta: (Delta()..insert(next)).toJson(),
        })
        ..afterSelection = selection;
  await editorState.apply(transaction);
}

Delta buildLiveMarkdownDelta(String text) {
  if (text.isEmpty) return Delta();
  final attributes = List.generate(text.length, (_) => <String, dynamic>{});

  final heading = RegExp(r'^(#{1,6})\s').firstMatch(text);
  if (heading != null) {
    final level = heading.group(1)!.length;
    _markBlock(attributes, heading.start, heading.end);
    for (var i = heading.end; i < text.length; i++) {
      attributes[i][yuliHeadingLevel] = level;
    }
  }

  final quote = RegExp(r'^>\s?').firstMatch(text);
  if (quote != null) {
    _markBlock(attributes, quote.start, quote.end);
    for (var i = quote.end; i < text.length; i++) {
      attributes[i][yuliQuoteText] = true;
    }
  }

  if (text.trim() == '---') {
    _markBlock(attributes, 0, text.length);
  }

  _applyDelimited(text, attributes, RegExp(r'\[\[([^\]\n]{1,120})\]\]'), 2, {
    yuliWikiLink: true,
  });

  _applyDelimited(
    text,
    attributes,
    RegExp(r'^\$\$([\s\S]*\S[\s\S]*?)\$\$$'),
    2,
    {yuliLatex: true, yuliLatexDisplay: true},
  );
  _applyDelimited(
    text,
    attributes,
    RegExp(r'(?<![\\$])\$(?![$\s])([^$\n]*[^$\s\n][^$\n]*)\$(?!\$)'),
    1,
    {yuliLatex: true},
  );
  _applyDelimited(
    text,
    attributes,
    RegExp(r'(?<!\*)\*\*\*(?!\s)(.*?\S.*?)\*\*\*'),
    3,
    {AppFlowyRichTextKeys.bold: true, AppFlowyRichTextKeys.italic: true},
  );
  _applyDelimited(
    text,
    attributes,
    RegExp(r'(?<!\*)\*\*(?!\s)(.*?\S.*?)\*\*'),
    2,
    {AppFlowyRichTextKeys.bold: true},
  );
  _applyDelimited(text, attributes, RegExp(r'(?<!~)~~(?!\s)(.*?\S.*?)~~'), 2, {
    AppFlowyRichTextKeys.strikethrough: true,
  });
  _applyDelimited(text, attributes, RegExp(r'(?<!=)==(?!\s)(.*?\S.*?)=='), 2, {
    yuliHighlight: true,
  });
  _applyDelimited(text, attributes, RegExp(r'(?<!`)`([^`\n]*\S[^`\n]*)`'), 1, {
    AppFlowyRichTextKeys.code: true,
  });
  _applyDelimited(
    text,
    attributes,
    RegExp(r'(?<![*])\*(?![*\s])(.*?\S.*?)\*(?![*])'),
    1,
    {AppFlowyRichTextKeys.italic: true},
  );
  _applyDelimited(
    text,
    attributes,
    RegExp(r'(?<![_])_(?![_\s])(.*?\S.*?)_(?![_])'),
    1,
    {AppFlowyRichTextKeys.italic: true},
  );

  final delta = Delta();
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || !_same(attributes[start], attributes[i])) {
      delta.insert(
        text.substring(start, i),
        attributes: attributes[start].isEmpty ? null : attributes[start],
      );
      start = i;
    }
  }
  return delta;
}

void _applyDelimited(
  String text,
  List<Map<String, dynamic>> attributes,
  RegExp pattern,
  int markerLength,
  Map<String, dynamic> contentAttributes,
) {
  for (final match in pattern.allMatches(text)) {
    _markInline(
      attributes,
      match.start,
      match.start + markerLength,
      match.start + markerLength,
      match.end - markerLength,
    );
    _markInline(
      attributes,
      match.end - markerLength,
      match.end,
      match.start + markerLength,
      match.end - markerLength,
    );
    for (
      var i = match.start + markerLength;
      i < match.end - markerLength;
      i++
    ) {
      attributes[i].addAll({
        ...contentAttributes,
        yuliMarkdownDomainStart: match.start + markerLength,
        yuliMarkdownDomainEnd: match.end - markerLength,
      });
    }
  }
}

void _markBlock(List<Map<String, dynamic>> attributes, int start, int end) {
  for (var i = start; i < end && i < attributes.length; i++) {
    attributes[i][yuliMarkdownMarker] = true;
    attributes[i][yuliMarkdownBlockMarker] = true;
  }
}

void _markInline(
  List<Map<String, dynamic>> attributes,
  int start,
  int end,
  int domainStart,
  int domainEnd,
) {
  for (var i = start; i < end && i < attributes.length; i++) {
    attributes[i][yuliMarkdownMarker] = true;
    attributes[i][yuliMarkdownDomainStart] = domainStart;
    attributes[i][yuliMarkdownDomainEnd] = domainEnd;
  }
}

bool _same(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}
