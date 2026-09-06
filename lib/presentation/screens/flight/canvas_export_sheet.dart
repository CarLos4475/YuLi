// Option sheets for exporting a canvas (whiteboard region / notebook pages) to
// PDF or PNG. Pure UI: returns the chosen [CanvasExportOptions]; the editors
// run the actual render/share pipeline (see canvas_export.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';

enum ExportFormat { pdf, png }

/// Whiteboard region choice.
enum WhiteboardRegion { all, marquee }

class CanvasExportOptions {
  final ExportFormat format;
  final bool includeTasks;
  final bool toDrive;

  // Whiteboard-only.
  final WhiteboardRegion region;

  // Notebook-only (page set is chosen in the page drawer, not here).
  final bool onePagePerSheet; // PDF multipage vs one tall page

  const CanvasExportOptions({
    required this.format,
    required this.includeTasks,
    this.toDrive = false,
    this.region = WhiteboardRegion.all,
    this.onePagePerSheet = true,
  });
}

Future<CanvasExportOptions?> showWhiteboardExportSheet(
  BuildContext context, {
  required Color accent,
  required bool hasTasks,
}) {
  return showModalBottomSheet<CanvasExportOptions>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _WhiteboardExportSheet(accent: accent, hasTasks: hasTasks),
  );
}

Future<CanvasExportOptions?> showNotebookExportSheet(
  BuildContext context, {
  required Color accent,
  required int selectedCount,
  required bool hasTasks,
}) {
  return showModalBottomSheet<CanvasExportOptions>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder:
        (_) => _NotebookExportSheet(
          accent: accent,
          selectedCount: selectedCount,
          hasTasks: hasTasks,
        ),
  );
}

/// Blocking progress overlay shown while the export renders. Push with
/// `showDialog(barrierDismissible: false)`, pop when done.
class ExportProgressDialog extends StatelessWidget {
  final Color accent;
  const ExportProgressDialog({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineHeavy),
          boxShadow: const [
            BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
            ),
            const SizedBox(width: 16),
            Text(
              'EXPORTANDO…',
              style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.6,
                color: yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared chrome ─────────────────────────────────────────────────────────

class _SheetShell extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SheetShell({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: yCream,
          border: Border(
            top: BorderSide(color: yBorderStrong, width: yLineHeavy),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.6,
                  color: yMuted,
                ),
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: yMono(
        size: 9,
        weight: FontWeight.w700,
        tracking: 1.4,
        color: yInk,
      ),
    ),
  );
}

class _Segmented<T> extends StatelessWidget {
  final List<(T, String, IconData)> options;
  final T value;
  final Color accent;
  final ValueChanged<T> onChanged;
  const _Segmented({
    required this.options,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final o in options) ...[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(o.$1);
              },
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == o.$1 ? accent : yCream,
                  border: Border.all(color: yBorderStrong, width: yLineMid),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(o.$3, size: 15, color: value == o.$1 ? yCream : yInk),
                    const SizedBox(width: 6),
                    Text(
                      o.$2,
                      style: yMono(
                        size: 10,
                        weight: FontWeight.w700,
                        tracking: 1.0,
                        color: value == o.$1 ? yCream : yInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (o != options.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value ? accent : yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
            ),
            child:
                value
                    ? const Icon(YuLiIcons.check, size: 15, color: yCream)
                    : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: yBody(size: 14, color: yInk))),
        ],
      ),
    );
  }
}

class _ConfirmBtn extends StatelessWidget {
  final Color accent;
  final String label;
  final VoidCallback onTap;
  const _ConfirmBtn({
    required this.accent,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          border: Border.all(color: yBorderStrong, width: yLineHeavy),
          boxShadow: const [
            BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
          ],
        ),
        child: Text(
          label,
          style: yMono(
            size: 12,
            weight: FontWeight.w700,
            tracking: 1.4,
            color: yCream,
          ),
        ),
      ),
    );
  }
}

// ─── Whiteboard sheet ────────────────────────────────────────────────────────

class _WhiteboardExportSheet extends StatefulWidget {
  final Color accent;
  final bool hasTasks;
  const _WhiteboardExportSheet({required this.accent, required this.hasTasks});

  @override
  State<_WhiteboardExportSheet> createState() => _WhiteboardExportSheetState();
}

class _WhiteboardExportSheetState extends State<_WhiteboardExportSheet> {
  bool _toDrive = false;
  WhiteboardRegion _region = WhiteboardRegion.all;
  ExportFormat _format = ExportFormat.pdf;
  bool _includeTasks = true;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'EXPORTAR PIZARRA',
      children: [
        const _SectionLabel('QUÉ EXPORTAR'),
        _Segmented<WhiteboardRegion>(
          accent: widget.accent,
          value: _region,
          options: const [
            (WhiteboardRegion.all, 'TODO', YuLiIcons.checkCheck),
            (WhiteboardRegion.marquee, 'ÁREA', YuLiIcons.crop),
          ],
          onChanged: (v) => setState(() => _region = v),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('FORMATO'),
        _Segmented<ExportFormat>(
          accent: widget.accent,
          value: _format,
          options: const [
            (ExportFormat.pdf, 'PDF', YuLiIcons.fileText),
            (ExportFormat.png, 'PNG', YuLiIcons.image),
          ],
          onChanged: (v) => setState(() => _format = v),
        ),
        if (widget.hasTasks) ...[
          const SizedBox(height: 16),
          _ToggleRow(
            label: 'Incluir bloques de tareas',
            value: _includeTasks,
            accent: widget.accent,
            onChanged: (v) => setState(() => _includeTasks = v),
          ),
        ],
        const SizedBox(height: 16),
        _ToggleRow(
          label: 'Guardar en Google Drive (Conectar en Ajustes)',
          value: _toDrive,
          accent: widget.accent,
          onChanged: (v) => setState(() => _toDrive = v),
        ),
        const SizedBox(height: 18),
        _ConfirmBtn(
          accent: widget.accent,
          label:
              _region == WhiteboardRegion.marquee
                  ? 'SELECCIONAR ÁREA  →'
                  : 'EXPORTAR',
          onTap:
              () => Navigator.pop(
                context,
                CanvasExportOptions(
                  format: _format,
                  includeTasks: _includeTasks,
                  region: _region,
                  toDrive: _toDrive,
                ),
              ),
        ),
      ],
    );
  }
}

// ─── Notebook sheet ──────────────────────────────────────────────────────────

class _NotebookExportSheet extends StatefulWidget {
  final Color accent;
  final int selectedCount;
  final bool hasTasks;
  const _NotebookExportSheet({
    required this.accent,
    required this.selectedCount,
    required this.hasTasks,
  });

  @override
  State<_NotebookExportSheet> createState() => _NotebookExportSheetState();
}

class _NotebookExportSheetState extends State<_NotebookExportSheet> {
  bool _toDrive = false;
  ExportFormat _format = ExportFormat.pdf;
  bool _includeTasks = true;
  bool _onePagePerSheet = true;

  @override
  Widget build(BuildContext context) {
    final n = widget.selectedCount;
    return _SheetShell(
      title: 'EXPORTAR · $n ${n == 1 ? 'PÁGINA' : 'PÁGINAS'}',
      children: [
        const _SectionLabel('FORMATO'),
        _Segmented<ExportFormat>(
          accent: widget.accent,
          value: _format,
          options: const [
            (ExportFormat.pdf, 'PDF', YuLiIcons.fileText),
            (ExportFormat.png, 'PNG', YuLiIcons.image),
          ],
          onChanged: (v) => setState(() => _format = v),
        ),
        if (_format == ExportFormat.pdf && n > 1) ...[
          const SizedBox(height: 14),
          _ToggleRow(
            label: 'Una página PDF por hoja',
            value: _onePagePerSheet,
            accent: widget.accent,
            onChanged: (v) => setState(() => _onePagePerSheet = v),
          ),
        ],
        if (widget.hasTasks) ...[
          const SizedBox(height: 14),
          _ToggleRow(
            label: 'Incluir bloques de tareas',
            value: _includeTasks,
            accent: widget.accent,
            onChanged: (v) => setState(() => _includeTasks = v),
          ),
        ],
        const SizedBox(height: 16),
        _ToggleRow(
          label: 'Guardar en Google Drive (Conectar en Ajustes)',
          value: _toDrive,
          accent: widget.accent,
          onChanged: (v) => setState(() => _toDrive = v),
        ),
        const SizedBox(height: 18),
        _ConfirmBtn(
          accent: widget.accent,
          label: 'EXPORTAR',
          onTap:
              () => Navigator.pop(
                context,
                CanvasExportOptions(
                  format: _format,
                  includeTasks: _includeTasks,
                  onePagePerSheet: _onePagePerSheet,
                  toDrive: _toDrive,
                ),
              ),
        ),
      ],
    );
  }
}
