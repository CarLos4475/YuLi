import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'yuli_editor_viewport.dart';

Node yuliTableCell(Node table, int row, int col) => table.children.firstWhere(
  (n) =>
      n.attributes[TableCellBlockKeys.rowPosition] == row &&
      n.attributes[TableCellBlockKeys.colPosition] == col,
);

Node yuliReorderTableAxis(
  Node table,
  TableDirection direction,
  int from,
  int to,
) {
  final result = table.deepCopy();
  final key =
      direction == TableDirection.row
          ? TableCellBlockKeys.rowPosition
          : TableCellBlockKeys.colPosition;
  final length =
      table.attributes[direction == TableDirection.row
              ? TableBlockKeys.rowsLen
              : TableBlockKeys.colsLen]
          as int;
  if (from < 0 || to < 0 || from >= length || to >= length) return result;
  final order = List.generate(length, (i) => i);
  order.insert(to, order.removeAt(from));
  for (final cell in result.children) {
    cell.updateAttributes({key: order.indexOf(cell.attributes[key] as int)});
  }
  return result;
}

List<List<String>> yuliParseTableClipboard(String input) {
  if (input.length > 100000) {
    throw const FormatException('La tabla es demasiado grande.');
  }
  final rows = <List<String>>[];
  var cells = <String>[];
  var text = StringBuffer();
  var quoted = false;
  final source = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (c == '"' && (quoted || text.isEmpty)) {
      if (quoted && i + 1 < source.length && source[i + 1] == '"') {
        text.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (c == '\t' || c == '\n')) {
      cells.add(text.toString());
      text = StringBuffer();
      if (c == '\n') {
        rows.add(cells);
        cells = [];
      }
    } else {
      text.write(c);
    }
  }
  if (quoted) throw const FormatException('La tabla copiada está incompleta.');
  if (text.isNotEmpty || cells.isNotEmpty || rows.isEmpty) {
    cells.add(text.toString());
    rows.add(cells);
  }
  final width = rows.fold<int>(
    0,
    (width, row) => row.length > width ? row.length : width,
  );
  if (rows.length > 100 || width > 40 || rows.length * width > 2000) {
    throw const FormatException(
      'Pega hasta 100 filas, 40 columnas y 2000 celdas.',
    );
  }
  return rows;
}

Node yuliPasteTableCells(
  Node table,
  int startRow,
  int startCol,
  List<List<String>> values,
) {
  final oldRows = table.attributes[TableBlockKeys.rowsLen] as int;
  final oldCols = table.attributes[TableBlockKeys.colsLen] as int;
  final rows = (startRow + values.length).clamp(oldRows, 100);
  final width = values.fold<int>(
    0,
    (n, row) => row.length > n ? row.length : n,
  );
  final cols = (startCol + width).clamp(oldCols, 40);
  if (startRow + values.length > rows ||
      startCol + width > cols ||
      rows * cols > 2000) {
    throw const FormatException('La tabla resultante es demasiado grande.');
  }
  final result =
      TableNode.fromList(
        List.generate(cols, (_) => List.filled(rows, '')),
      ).node;
  result.updateAttributes({
    ...table.attributes,
    TableBlockKeys.rowsLen: rows,
    TableBlockKeys.colsLen: cols,
  });
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      final cell = yuliTableCell(result, row, col);
      final old =
          row < oldRows && col < oldCols
              ? yuliTableCell(table, row, col)
              : null;
      if (old != null) {
        cell.updateAttributes({...old.attributes});
        for (final child in cell.children.toList()) {
          child.unlink();
        }
        for (final child in old.children) {
          cell.insert(child.deepCopy());
        }
      }
      final r = row - startRow;
      final c = col - startCol;
      if (r >= 0 && r < values.length && c >= 0 && c < values[r].length) {
        for (final child in cell.children.toList()) {
          child.unlink();
        }
        cell.insert(paragraphNode(delta: Delta()..insert(values[r][c])));
      }
    }
  }
  return result;
}

class YuliTableTools extends StatelessWidget {
  final Color accent;
  final VoidCallback paste;
  final VoidCallback exit;
  final VoidCallback selectTable;
  final VoidCallback deleteTable;
  final void Function(TableDirection direction, String action) onAction;
  final VoidCallback onMenuOpen;
  final VoidCallback onMenuClose;

  const YuliTableTools({
    super.key,
    required this.accent,
    required this.paste,
    required this.exit,
    required this.selectTable,
    required this.deleteTable,
    required this.onAction,
    required this.onMenuOpen,
    required this.onMenuClose,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: yCream,
      border: Border.all(color: yBorderStrong, width: yLineThin),
      boxShadow: const [
        BoxShadow(color: yInk, offset: Offset(3, 3), blurRadius: 0),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button('Seleccionar tabla', YuLiIcons.table, selectTable),
        _divider(),
        _button(
          'Añadir fila debajo',
          YuLiIcons.flipVertical,
          () => onAction(TableDirection.row, 'after'),
        ),
        _button(
          'Añadir columna a la derecha',
          YuLiIcons.flipHorizontal,
          () => onAction(TableDirection.col, 'after'),
        ),
        _divider(),
        _menu('Más opciones', YuLiIcons.moreHorizontal, const {
          'table:paste': 'Pegar celdas',
          'row:before': 'Insertar fila arriba',
          'col:before': 'Insertar columna a la izquierda',
          'row:duplicate': 'Duplicar fila',
          'col:duplicate': 'Duplicar columna',
          'col:narrow': 'Reducir ancho de columna',
          'col:widen': 'Aumentar ancho de columna',
          'row:back': 'Mover fila arriba',
          'row:forward': 'Mover fila abajo',
          'col:back': 'Mover columna a la izquierda',
          'col:forward': 'Mover columna a la derecha',
        }),
        _menu('Eliminar', YuLiIcons.trash, const {
          'row:delete': 'Eliminar fila',
          'col:delete': 'Eliminar columna',
          'table:delete': 'Eliminar tabla',
        }, destructive: true),
        _divider(),
        _button('Continuar debajo', YuLiIcons.arrowRight, exit),
      ],
    ),
  );

  Widget _divider() => Container(
    width: yLineThin,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    color: yBorderSoft,
  );

  Widget _button(String label, IconData icon, VoidCallback callback) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: callback,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 18, color: accent),
        ),
      ),
    ),
  );

  Widget _menu(
    String label,
    IconData icon,
    Map<String, String> entries, {
    bool destructive = false,
  }) => Builder(
    builder:
        (context) => _button(label, icon, () async {
          onMenuOpen();
          try {
            final value = await showYuliEditorMenu<String>(
              context: context,
              color: yCream,
              shape: Border.all(color: yBorderStrong, width: yLineThin),
              items: [
                for (final entry in entries.entries)
                  PopupMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      style: yBody(
                        size: 13,
                        color: destructive ? accent : yInk,
                      ),
                    ),
                  ),
              ],
            );
            if (!context.mounted || value == null) return;
            if (value == 'table:paste') {
              paste();
              return;
            }
            if (value == 'table:delete') {
              deleteTable();
              return;
            }
            final parts = value.split(':');
            onAction(
              parts.first == 'row' ? TableDirection.row : TableDirection.col,
              parts.last,
            );
          } finally {
            onMenuClose();
          }
        }),
  );
}
