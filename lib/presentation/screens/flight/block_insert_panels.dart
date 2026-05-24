import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';

enum InsertPanelType {
  table,
  code,
  quote,
  latex,
  image,
}

class InsertPanelOverlay extends StatelessWidget {
  final InsertPanelType type;
  final void Function(String markdown) onInsert;
  final VoidCallback onClose;
  final int noteId;

  const InsertPanelOverlay({
    super.key,
    required this.type,
    required this.onInsert,
    required this.onClose,
    required this.noteId,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxW = screenWidth > 720 ? 560.0 : screenWidth - 32.0;
    final maxH = MediaQuery.of(context).size.height * 0.7;

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withAlpha(100),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: GestureDetector(
          onTap: () {},
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
              child: switch (type) {
                InsertPanelType.table => _TablePanel(onInsert: onInsert, onClose: onClose),
                InsertPanelType.code => _CodePanel(onInsert: onInsert, onClose: onClose),
                InsertPanelType.quote => _QuotePanel(onInsert: onInsert, onClose: onClose),
                InsertPanelType.latex => _LatexPanel(onInsert: onInsert, onClose: onClose),
                InsertPanelType.image => _ImagePanel(onInsert: onInsert, onClose: onClose, noteId: noteId),
              },
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
  final Widget child;

  const _PanelScaffold({
    required this.title,
    required this.onClose,
    this.onInsert,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: inkColor(context), width: borderWidthHeavy),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: inkColor(context), width: borderWidth),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: displayM.copyWith(color: inkColor(context)),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close, color: inkColor(context), size: 22),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
          if (onInsert != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onInsert,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: accentFlight,
                  border: Border(
                    top: BorderSide(color: inkColor(context), width: borderWidth),
                  ),
                ),
                child: Center(
                  child: Text(
                    'INSERTAR',
                    style: labelBold.copyWith(
                      color: paperLight,
                      letterSpacing: 1.0,
                    ),
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

InputDecoration _panelInputDecoration(BuildContext context, {String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: bodyS.copyWith(color: inkGray),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: inkGray, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: inkGray.withAlpha(120), width: 1),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: accentFlight, width: 2),
    ),
    contentPadding: const EdgeInsets.all(12),
    isDense: true,
  );
}

// ─── Table Panel ─────────────────────────────────────────────────────────────

class _TablePanel extends StatefulWidget {
  final void Function(String) onInsert;
  final VoidCallback onClose;

  const _TablePanel({required this.onInsert, required this.onClose});

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
    _cells = List.generate(
      2,
      (_) => List.generate(2, (_) => TextEditingController()),
    );
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
    buf.write('\n\n');
    return buf.toString();
  }

  Widget _counterBtn(
    BuildContext context, {
    required String label,
    required int value,
    required VoidCallback onAdd,
    VoidCallback? onRemove,
  }) {
    final disabledColor = inkGray.withAlpha(80);
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
              border: Border.all(
                color: onRemove != null ? inkColor(context) : disabledColor,
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                '−',
                style: bodyM.copyWith(
                  color: onRemove != null ? inkColor(context) : disabledColor,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '$value $label',
            style: bodyS.copyWith(color: inkColor(context)),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAdd,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border.all(color: inkColor(context), width: 1),
            ),
            child: Center(
              child: Text(
                '+',
                style: bodyM.copyWith(color: inkColor(context), height: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _alignBtn(BuildContext context, IconData icon, TextAlign value) {
    final selected = _alignment == value;
    return GestureDetector(
      onTap: () => setState(() => _alignment = value),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: selected ? accentFlight : Colors.transparent,
          border: Border.all(
            color: selected ? accentFlight : inkGray.withAlpha(80),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected ? paperLight : inkColor(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderCol = inkGray.withAlpha(50);
    return _PanelScaffold(
      title: 'Tabla',
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
              _counterBtn(
                context,
                label: 'col',
                value: _cols,
                onAdd: _addColumn,
                onRemove: _cols > 1 ? _removeColumn : null,
              ),
              _counterBtn(
                context,
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
              _alignBtn(context, Icons.format_align_left, TextAlign.left),
              const SizedBox(width: 6),
              _alignBtn(context, Icons.format_align_center, TextAlign.center),
              const SizedBox(width: 6),
              _alignBtn(context, Icons.format_align_right, TextAlign.right),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(2),
              child: SizedBox(
                width: _cols * 130.0,
                child: Table(
                  border: TableBorder(
                    top: BorderSide(color: borderCol, width: 1.5),
                    bottom: BorderSide(color: borderCol, width: 1.5),
                    left: BorderSide(color: borderCol, width: 1.5),
                    right: BorderSide(color: borderCol, width: 1.5),
                    horizontalInside: BorderSide(color: borderCol, width: 0.5),
                    verticalInside: BorderSide(color: borderCol, width: 0.5),
                  ),
                  children: [
                    for (int r = 0; r < _cells.length; r++)
                      TableRow(
                        decoration: r == 0
                            ? BoxDecoration(
                                color: inkColor(context).withAlpha(12),
                              )
                            : null,
                        children: [
                          for (int c = 0; c < _cols; c++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  controller: _cells[r][c],
                                  style: r == 0
                                      ? labelBold.copyWith(
                                          color: inkColor(context),
                                          fontSize: 13)
                                      : bodyS.copyWith(
                                          color: inkColor(context)),
                                  textAlign: _alignment,
                                  decoration: InputDecoration(
                                    hintText: r == 0 ? 'Encab.' : '',
                                    hintStyle: bodyS.copyWith(
                                        color: inkGray.withAlpha(100)),
                                    border: InputBorder.none,
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 8),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
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

  const _CodePanel({required this.onInsert, required this.onClose});

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
      title: 'Código',
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
          Text('Lenguaje', style: labelBold.copyWith(color: inkGray)),
          const SizedBox(height: 8),
          TextField(
            controller: _langController,
            style: bodyM.copyWith(color: inkColor(context)),
            decoration:
                _panelInputDecoration(context, hint: 'python, dart, js...'),
          ),
          const SizedBox(height: 16),
          Text('Código', style: labelBold.copyWith(color: inkGray)),
          const SizedBox(height: 8),
          TextField(
            controller: _codeController,
            style: mono.copyWith(color: inkColor(context)),
            maxLines: 8,
            minLines: 4,
            decoration: _panelInputDecoration(context),
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

  const _QuotePanel({required this.onInsert, required this.onClose});

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
          Text('Texto de la cita', style: labelBold.copyWith(color: inkGray)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            style: bodyM.copyWith(color: inkColor(context)),
            maxLines: 6,
            minLines: 3,
            decoration: _panelInputDecoration(context),
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

  const _LatexPanel({required this.onInsert, required this.onClose});

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

  Widget _modeChip(BuildContext context, String label, bool value) {
    final selected = _isBlock == value;
    return GestureDetector(
      onTap: () => setState(() => _isBlock = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accentFlight : Colors.transparent,
          border: Border.all(
            color: selected ? accentFlight : inkGray,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: bodyS.copyWith(
            color: selected ? paperLight : inkColor(context),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PanelScaffold(
      title: 'LaTeX',
      onClose: widget.onClose,
      onInsert: () {
        if (_isBlock) {
          final formula = _controller.text;
          widget.onInsert('\n\n\$\$\n$formula\n\$\$\n\n');
        } else {
          final formula = _controller.text.trim();
          widget.onInsert(' \$$formula\$ ');
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _modeChip(context, 'En línea', false),
              const SizedBox(width: 8),
              _modeChip(context, 'Bloque', true),
            ],
          ),
          const SizedBox(height: 16),
          Text('Fórmula', style: labelBold.copyWith(color: inkGray)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            style: mono.copyWith(color: inkColor(context)),
            maxLines: _isBlock ? 6 : 1,
            minLines: _isBlock ? 3 : 1,
            decoration: _panelInputDecoration(
              context,
              hint: r'f(x) = \int_0^1 x^2\,dx',
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

  const _ImagePanel({
    required this.onInsert,
    required this.onClose,
    required this.noteId,
  });

  @override
  ConsumerState<_ImagePanel> createState() => _ImagePanelState();
}

class _ImagePanelState extends ConsumerState<_ImagePanel> {
  XFile? _pickedFile;
  bool _isLoading = false;

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
      final imagesDir =
          Directory(p.join(appDir.path, 'note_images', '${widget.noteId}'));
      await imagesDir.create(recursive: true);

      final ext = p.extension(_pickedFile!.path).toLowerCase();
      final newFilename = '${const Uuid().v4()}$ext';
      final newPath = p.join(imagesDir.path, newFilename);

      await File(_pickedFile!.path).copy(newPath);

      final fileSize = await File(newPath).length();
      await ref.read(noteRepositoryProvider).addImage(
            widget.noteId,
            newFilename,
            newPath,
            fileSize,
          );

      widget.onInsert('\n![Imagen]($newPath)\n');
      widget.onClose();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PanelScaffold(
      title: 'Imagen',
      onClose: widget.onClose,
      onInsert: _pickedFile != null && !_isLoading ? _insertImage : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pickedFile != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.file(
                File(_pickedFile!.path),
                fit: BoxFit.contain,
              ),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: inkGray, width: 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_outlined, size: 48, color: inkGray),
                    const SizedBox(height: 12),
                    Text(
                      'Seleccionar imagen',
                      style: bodyM.copyWith(color: inkGray),
                    ),
                  ],
                ),
              ),
            ),
          if (_pickedFile != null && !_isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: _pickImage,
                child: Text(
                  'Cambiar imagen',
                  style: labelBold.copyWith(color: accentFlight),
                ),
              ),
            ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: accentFlight),
              ),
            ),
        ],
      ),
    );
  }
}

