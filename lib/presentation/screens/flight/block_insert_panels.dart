import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../providers/database_providers.dart';

enum InsertPanelType { table, code, quote, latex, image }

class InsertPanelOverlay extends StatelessWidget {
  final InsertPanelType type;
  final void Function(String markdown) onInsert;
  final VoidCallback onClose;
  final int noteId;
  final Color accent;

  const InsertPanelOverlay({
    super.key,
    required this.type,
    required this.onInsert,
    required this.onClose,
    required this.noteId,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final maxW = screenWidth > 720 ? 560.0 : screenWidth - 32.0;
    final availableHeight = media.size.height - media.padding.vertical - media.viewInsets.bottom;
    final maxH = availableHeight * (screenWidth > 720 ? 0.78 : 0.9);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.4),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: SafeArea(
            child: GestureDetector(
              onTap: () {},
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
                  child: switch (type) {
                    InsertPanelType.table => _TablePanel(accent: accent, onInsert: onInsert, onClose: onClose),
                    InsertPanelType.code => _CodePanel(accent: accent, onInsert: onInsert, onClose: onClose),
                    InsertPanelType.quote => _QuotePanel(accent: accent, onInsert: onInsert, onClose: onClose),
                    InsertPanelType.latex => _LatexPanel(accent: accent, onInsert: onInsert, onClose: onClose),
                    InsertPanelType.image => _ImagePanel(
                      accent: accent,
                      onInsert: onInsert,
                      onClose: onClose,
                      noteId: noteId,
                    ),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// ─── Panel Scaffold ──────────────────────────────────────────────────────────

class _PanelScaffold extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onInsert;
  final Color accent;
  final Widget child;

  const _PanelScaffold({
    required this.title,
    required this.onClose,
    this.onInsert,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: yCream, border: Border.all(color: yBorderStrong, width: yLineMid)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: yBorderStrong, width: yLineMid))),
            child: Row(
              children: [
                Expanded(child: Text(title, style: ySans(size: 24, weight: FontWeight.w700, color: yInk))),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: const Padding(padding: EdgeInsets.all(8), child: Icon(YuLiIcons.close, color: yInk, size: 22)),
                ),
              ],
            ),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: child)),
          if (onInsert != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onInsert,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: accent,
                  border: const Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
                ),
                child: Center(
                  child: Text(
                    'INSERTAR',
                    style: yBody(size: 14, weight: FontWeight.w700, color: yCream).copyWith(letterSpacing: 1.0),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Shared helpers ──────────────────────────────────────────────────────────

InputDecoration _panelInputDecoration({String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: yBody(size: 13, color: yMuted),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: yBorderSoft, width: yLineThin),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: yBorderSoft, width: yLineThin),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
    ),
    contentPadding: const EdgeInsets.all(12),
    isDense: true,
  );
}

// ─── Table Panel ─────────────────────────────────────────────────────────────

class _TablePanel extends StatefulWidget {
  final void Function(String) onInsert;
  final VoidCallback onClose;
  final Color accent;

  const _TablePanel({required this.accent, required this.onInsert, required this.onClose});

  @override
  State<_TablePanel> createState() => _TablePanelState();
}

class _TablePanelState extends State<_TablePanel> {
  int _cols = 2;
  TextAlign _alignment = TextAlign.left;
  late List<List<TextEditingController>> _cells;

  @override
  void initState() {
    super.initState();
    _cells = List.generate(2, (_) => List.generate(2, (_) => TextEditingController()));
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final ctrl in row) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  void _addColumn() {
    setState(() {
      _cols++;
      for (final row in _cells) {
        row.add(TextEditingController());
      }
    });
  }

  void _removeColumn() {
    if (_cols <= 1) return;
    setState(() {
      _cols--;
      for (final row in _cells) {
        row.removeLast().dispose();
      }
    });
  }

  void _addRow() {
    setState(() {
      _cells.add(List.generate(_cols, (_) => TextEditingController()));
    });
  }

  void _removeRow() {
    if (_cells.length <= 2) return;
    setState(() {
      for (final ctrl in _cells.removeLast()) {
        ctrl.dispose();
      }
    });
  }

  String _generateMarkdown() {
    final buf = StringBuffer('\n');
    buf.write('|');
    for (int c = 0; c < _cols; c++) {
      final t = _cells[0][c].text.trim();
      buf.write(' ${t.isEmpty ? '   ' : t} |');
    }
    buf.write('\n|');
    for (int c = 0; c < _cols; c++) {
      switch (_alignment) {
        case TextAlign.center:
          buf.write(' :---: |');
        case TextAlign.right:
          buf.write(' ---: |');
        default:
          buf.write(' --- |');
      }
    }
    for (int r = 1; r < _cells.length; r++) {
      buf.write('\n|');
      for (int c = 0; c < _cols; c++) {
        final t = _cells[r][c].text.trim();
        buf.write(' ${t.isEmpty ? '   ' : t} |');
      }
    }
    buf.write('\n');
    final table = buf.toString().trim();
    if (_alignment == TextAlign.center) return '\n::: center\n$table\n:::\n';
    if (_alignment == TextAlign.right) return '\n::: right\n$table\n:::\n';
    return '\n$table\n';
  }

  Widget _counterBtn({required String label, required int value, required VoidCallback onAdd, VoidCallback? onRemove}) {
    final disabledColor = yMuted.withValues(alpha: 0.4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRemove,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border.all(color: onRemove != null ? yBorderStrong : disabledColor, width: yLineThin),
            ),
            child: Center(
              child: Text('−', style: yBody(size: 16, color: onRemove != null ? yInk : disabledColor, height: 1)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('$value $label', style: yBody(size: 13, color: yInk)),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAdd,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(border: Border.all(color: yBorderStrong, width: yLineThin)),
            child: Center(child: Text('+', style: yBody(size: 16, color: yInk, height: 1))),
          ),
        ),
      ],
    );
  }

  Widget _alignBtn(IconData icon, TextAlign value) {
    final selected = _alignment == value;
    return GestureDetector(
      onTap: () => setState(() => _alignment = value),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: selected ? widget.accent : Colors.transparent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Icon(icon, size: 18, color: selected ? yCream : yInk),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderCol = yMuted.withValues(alpha: 0.3);
    return _PanelScaffold(
      title: 'Tabla',
      accent: widget.accent,
      onClose: widget.onClose,
      onInsert: () => widget.onInsert(_generateMarkdown()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _counterBtn(label: 'col', value: _cols, onAdd: _addColumn, onRemove: _cols > 1 ? _removeColumn : null),
              _counterBtn(
                label: 'filas',
                value: _cells.length - 1,
                onAdd: _addRow,
                onRemove: _cells.length > 2 ? _removeRow : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _alignBtn(YuLiIcons.textAlignStart, TextAlign.left),
              const SizedBox(width: 6),
              _alignBtn(YuLiIcons.textAlignCenter, TextAlign.center),
              const SizedBox(width: 6),
              _alignBtn(YuLiIcons.textAlignEnd, TextAlign.right),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _cols * 130.0,
              child: Table(
                border: TableBorder.all(color: borderCol, width: yLineThin),
                children: [
                  for (int r = 0; r < _cells.length; r++)
                    TableRow(
                      decoration: r == 0 ? BoxDecoration(color: yInk.withValues(alpha: 0.05)) : null,
                      children: [
                        for (int c = 0; c < _cols; c++)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: TextField(
                              controller: _cells[r][c],
                              maxLines: null,
                              style:
                                  r == 0
                                      ? yBody(size: 13, weight: FontWeight.w700, color: yInk)
                                      : yBody(size: 13, color: yInk),
                              textAlign: _alignment,
                              decoration: InputDecoration(
                                hintText: r == 0 ? 'Encab.' : '',
                                hintStyle: yBody(size: 13, color: yMuted.withValues(alpha: 0.5)),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.all(6),
                                isDense: true,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Code Panel ──────────────────────────────────────────────────────────────

class _CodePanel extends StatefulWidget {
  final void Function(String) onInsert;
  final VoidCallback onClose;
  final Color accent;

  const _CodePanel({required this.accent, required this.onInsert, required this.onClose});

  @override
  State<_CodePanel> createState() => _CodePanelState();
}

class _CodePanelState extends State<_CodePanel> {
  final _langController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _langController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PanelScaffold(
      title: 'Codigo',
      accent: widget.accent,
      onClose: widget.onClose,
      onInsert: () {
        final lang = _langController.text.trim();
        final code = _codeController.text;
        widget.onInsert('\n```$lang\n$code\n```\n');
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lenguaje', style: yBody(size: 14, weight: FontWeight.w700, color: yInk)),
          const SizedBox(height: 8),
          TextField(
            controller: _langController,
            style: yBody(size: 16, color: yInk),
            decoration: _panelInputDecoration(hint: 'python, dart, js...'),
          ),
          const SizedBox(height: 16),
          Text('Código', style: yBody(size: 14, weight: FontWeight.w700, color: yInk)),
          const SizedBox(height: 8),
          TextField(
            controller: _codeController,
            style: yMono(size: 14, color: yInk, tracking: 0),
            maxLines: 8,
            minLines: 4,
            decoration: _panelInputDecoration(),
          ),
        ],
      ),
    );
  }
}

// ─── Quote Panel ─────────────────────────────────────────────────────────────

class _QuotePanel extends StatefulWidget {
  final void Function(String) onInsert;
  final VoidCallback onClose;
  final Color accent;

  const _QuotePanel({required this.accent, required this.onInsert, required this.onClose});

  @override
  State<_QuotePanel> createState() => _QuotePanelState();
}

class _QuotePanelState extends State<_QuotePanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PanelScaffold(
      title: 'Cita',
      accent: widget.accent,
      onClose: widget.onClose,
      onInsert: () {
        final lines = _controller.text.split('\n');
        final quoted = lines.map((l) => '> $l').join('\n');
        widget.onInsert('\n$quoted\n');
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Texto de la cita', style: yBody(size: 14, weight: FontWeight.w700, color: yInk)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            style: yBody(size: 16, color: yInk),
            maxLines: 6,
            minLines: 3,
            decoration: _panelInputDecoration(),
          ),
        ],
      ),
    );
  }
}

// ─── LaTeX Panel ─────────────────────────────────────────────────────────────

class _LatexPanel extends StatefulWidget {
  final void Function(String) onInsert;
  final VoidCallback onClose;
  final Color accent;

  const _LatexPanel({required this.accent, required this.onInsert, required this.onClose});

  @override
  State<_LatexPanel> createState() => _LatexPanelState();
}

class _LatexPanelState extends State<_LatexPanel> {
  final _controller = TextEditingController();
  bool _isBlock = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _modeChip(String label, bool value) {
    final selected = _isBlock == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _isBlock = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? widget.accent : Colors.transparent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(label, style: yBody(size: 13, color: selected ? yCream : yInk)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formula = _controller.text.trim();
    return _PanelScaffold(
      title: 'Latex',
      accent: widget.accent,
      onClose: widget.onClose,
      onInsert:
          formula.isEmpty
              ? null
              : () {
                if (_isBlock) {
                  widget.onInsert('\n\n\$\$\n${_controller.text}\n\$\$\n\n');
                } else {
                  widget.onInsert(' \$$formula\$ ');
                }
              },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [_modeChip('En línea', false), const SizedBox(width: 8), _modeChip('Bloque', true)]),
          const SizedBox(height: 16),
          Text('Fórmula', style: yBody(size: 14, weight: FontWeight.w700, color: yInk)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            style: yMono(size: 14, color: yInk, tracking: 0),
            maxLines: _isBlock ? 6 : 1,
            minLines: _isBlock ? 3 : 1,
            decoration: _panelInputDecoration(hint: r'f(x) = \int_0^1 x^2\,dx'),
          ),
          const SizedBox(height: 16),
          Text('Vista previa', style: yBody(size: 14, weight: FontWeight.w700, color: yInk)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: yCream2, border: Border.all(color: yBorderSoft, width: yLineThin)),
            alignment: _isBlock ? Alignment.center : Alignment.centerLeft,
            child:
                formula.isEmpty
                    ? Text('Escribe una fórmula para previsualizarla', style: yBody(size: 13, color: yMuted))
                    : Math.tex(
                      formula.replaceAll('\\\\', '\\'),
                      mathStyle: _isBlock ? MathStyle.display : MathStyle.text,
                      textStyle: yBody(size: 16, color: yInk),
                      onErrorFallback: (_) => Text(formula, style: yMono(size: 13, color: yMuted, tracking: 0)),
                    ),
          ),
        ],
      ),
    );
  }
}

// ─── Image Panel ─────────────────────────────────────────────────────────────

class _ImagePanel extends ConsumerStatefulWidget {
  final void Function(String) onInsert;
  final VoidCallback onClose;
  final int noteId;
  final Color accent;

  const _ImagePanel({required this.accent, required this.onInsert, required this.onClose, required this.noteId});

  @override
  ConsumerState<_ImagePanel> createState() => _ImagePanelState();
}

class _ImagePanelState extends ConsumerState<_ImagePanel> {
  XFile? _pickedFile;
  bool _isLoading = false;
  String? _imageAlign;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked != null && mounted) {
      setState(() => _pickedFile = picked);
    }
  }

  Future<void> _insertImage() async {
    if (_pickedFile == null) return;
    setState(() => _isLoading = true);

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(appDir.path, 'note_images', '${widget.noteId}'));
      await imagesDir.create(recursive: true);

      final ext = p.extension(_pickedFile!.path).toLowerCase();
      final newFilename = '${const Uuid().v4()}$ext';
      final newPath = p.join(imagesDir.path, newFilename);

      await File(_pickedFile!.path).copy(newPath);

      final fileSize = await File(newPath).length();
      await ref.read(noteRepositoryProvider).addImage(widget.noteId, newFilename, newPath, fileSize);

      final imgMarkdown = '![Imagen]($newPath)';
      final md = _imageAlign != null ? '\n::: $_imageAlign\n$imgMarkdown\n:::\n' : '\n$imgMarkdown\n';
      widget.onInsert(md);
      widget.onClose();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PanelScaffold(
      title: 'Imagen',
      accent: widget.accent,
      onClose: widget.onClose,
      onInsert: _pickedFile != null && !_isLoading ? _insertImage : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pickedFile != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.file(File(_pickedFile!.path), fit: BoxFit.contain),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(border: Border.all(color: yBorderStrong, width: yLineThin)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(YuLiIcons.image, size: 48, color: yMuted),
                    const SizedBox(height: 12),
                    Text('Seleccionar imagen', style: yBody(size: 16, color: yMuted)),
                  ],
                ),
              ),
            ),
          if (_pickedFile != null && !_isLoading) ...[
            const SizedBox(height: 10),
            Text('Alineacion', style: yBody(size: 13, weight: FontWeight.w700, color: yInk)),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildAlignBtn('Izquierda', 'left'),
                const SizedBox(width: 6),
                _buildAlignBtn('Centro', 'center'),
                const SizedBox(width: 6),
                _buildAlignBtn('Derecha', 'right'),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: yBorderStrong, width: yLineThin)),
                child: Text('Cambiar imagen', style: yBody(size: 13, weight: FontWeight.w700, color: yInk)),
              ),
            ),
          ],
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('...', style: ySans(size: 18, weight: FontWeight.w700, color: yInk)),
            ),
        ],
      ),
    );
  }

  Widget _buildAlignBtn(String label, String align) {
    final selected = _imageAlign == align;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _imageAlign = selected ? null : align),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
        decoration: BoxDecoration(
          color: selected ? widget.accent : Colors.transparent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(label, style: yBody(size: 11, weight: FontWeight.w700, color: selected ? yCream : yInk)),
      ),
    );
  }
}
