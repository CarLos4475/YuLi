import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:flutter_math_fork/flutter_math.dart';
import '../../theme/app_tokens.dart';
import '../../utils/pdf_export.dart';
import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../widgets/coach_mark.dart';
import '../../widgets/fight_panel.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/repositories/note_repository.dart';
import 'block_insert_menu.dart';
import 'block_insert_panels.dart';
import 'drawing_cell.dart';
import 'note_cell_model.dart';
import 'format_toolbar.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note note;
  final Folder folder;

  const NoteEditorScreen({super.key, required this.note, required this.folder});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late List<NoteCell> _cells;
  late final NoteRepository _noteRepository;
  final Map<String, TextEditingController> _textCtrls = {};
  final Map<String, FocusNode> _focusNodes = {};
  String? _activeCellId;
  bool _isPreview = false;
  Timer? _autosaveTimer;
  bool _isDirty = false;
  InsertPanelType? _activePanel;
  bool _isDrawing = false;
  final Set<String> _scrollLockedCells = {};

  @override
  void initState() {
    super.initState();
    _noteRepository = ref.read(noteRepositoryProvider);
    _titleController = TextEditingController(text: widget.note.title ?? '');
    _titleController.addListener(_onContentChanged);
    _cells = parseCells(widget.note.rawMarkdown);
    for (final cell in _cells) {
      if (cell.type == CellType.markdown) _createCellCtrls(cell);
    }
    final firstMd =
        _cells.where((c) => c.type == CellType.markdown).firstOrNull;
    if (firstMd != null) _activeCellId = firstMd.id;
    _isPreview = widget.note.rawMarkdown.isNotEmpty;
  }

  void _createCellCtrls(NoteCell cell) {
    final ctrl = TextEditingController(text: cell.content);
    ctrl.addListener(_onContentChanged);
    _textCtrls[cell.id] = ctrl;
    final fn = FocusNode();
    fn.addListener(() {
      if (fn.hasFocus && _activeCellId != cell.id) {
        setState(() => _activeCellId = cell.id);
      }
    });
    fn.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.backspace &&
          ctrl.text.isEmpty &&
          _cells.length > 1) {
        _deleteCell(cell.id);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _focusNodes[cell.id] = fn;
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _save();
    _titleController.dispose();
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _onContentChanged() {
    if (!_isDirty) setState(() => _isDirty = true);
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 2), _save);
  }

  Future<void> _save() async {
    if (!_isDirty) return;
    for (final cell in _cells) {
      if (cell.type == CellType.markdown) {
        cell.content = _textCtrls[cell.id]?.text ?? '';
      }
    }
    final title = _titleController.text.trim();
    final content = serializeCells(_cells);
    await _noteRepository.update(
      widget.note.copyWith(
        title: title.isEmpty ? null : title,
        clearTitle: title.isEmpty,
        rawMarkdown: content,
        sizeBytes: content.length,
        updatedAt: DateTime.now(),
      ),
    );
    await _noteRepository.saveVersion(widget.note.id, content);
    if (mounted) setState(() => _isDirty = false);
  }

  void _insertBlock(String syntax) {
    if (_activeCellId == null) return;
    final controller = _textCtrls[_activeCellId!];
    if (controller == null) return;
    final cursor = controller.selection.baseOffset;
    final text = controller.text;
    final newText = cursor >= 0
        ? text.substring(0, cursor) + syntax + text.substring(cursor)
        : text + syntax;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (cursor >= 0 ? cursor : text.length) + syntax.length,
      ),
    );
    _focusNodes[_activeCellId!]?.requestFocus();
  }

  void _addMarkdownCell() {
    final cell = NoteCell(type: CellType.markdown);
    _createCellCtrls(cell);
    setState(() {
      _cells.add(cell);
      _activeCellId = cell.id;
      _isDirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[cell.id]?.requestFocus();
    });
  }

  void _addDrawingCell() {
    setState(() {
      _cells.add(NoteCell(type: CellType.drawing, drawingData: DrawingData()));
      _isDirty = true;
    });
  }

  void _deleteCell(String id) {
    if (_cells.length <= 1) return;
    setState(() {
      _cells.removeWhere((c) => c.id == id);
      _textCtrls[id]?.dispose();
      _textCtrls.remove(id);
      _focusNodes[id]?.dispose();
      _focusNodes.remove(id);
      if (_activeCellId == id) {
        _activeCellId = _cells
            .where((c) => c.type == CellType.markdown)
            .firstOrNull
            ?.id;
      }
      _isDirty = true;
    });
  }

  void _showSendToLab(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SendNoteToKanbanSheet(
        note: widget.note,
        onLinked: (cardId) {
          if (_activeCellId != null) {
            final ctrl = _textCtrls[_activeCellId!];
            if (ctrl != null) {
              ctrl.text = '${ctrl.text}\n\n<!-- kanban:$cardId -->';
            }
          }
          _save();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nota vinculada a Kanban y ancla insertada'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: paperColor(context),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _NoteHeader(
                  folder: widget.folder,
                  titleController: _titleController,
                  isDirty: _isDirty,
                  isPreview: _isPreview,
                  onTogglePreview: () =>
                      setState(() => _isPreview = !_isPreview),
                  onLinkToLab: () => _showSendToLab(context),
                  onSave: _save,
                  onExportPdf: () => exportNoteToPdf(
                    context: context,
                    title: widget.note.displayTitle,
                    content: widget.note.rawMarkdown,
                  ),
                  onBack: () async {
                    await _save();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                Expanded(
                  child: Stack(
                    children: [
                      _DotGrid(isDark: isDark),
                      if (_isPreview)
                        _buildPreview(context, isDark)
                      else
                        _buildCellList(context),
                    ],
                  ),
                ),
                _BottomBar(
                  onInsertBlock:
                      _activeCellId != null ? _insertBlock : null,
                  onOpenPanel: (type) =>
                      setState(() => _activePanel = type),
                  onToggleFightPanel: () => _showFightPanel(context),
                  contentController: _activeCellId != null
                      ? _textCtrls[_activeCellId!]
                      : null,
                  onAddMarkdownCell: _addMarkdownCell,
                  onAddDrawingCell: _addDrawingCell,
                ),
              ],
            ),
            if (_activePanel != null)
              Positioned.fill(
                child: InsertPanelOverlay(
                  type: _activePanel!,
                  noteId: widget.note.id,
                  onInsert: (markdown) {
                    _insertBlock(markdown);
                    setState(() => _activePanel = null);
                  },
                  onClose: () => setState(() => _activePanel = null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCellList(BuildContext context) {
    return ListView.separated(
      physics: (_isDrawing || _scrollLockedCells.isNotEmpty) ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _cells.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (_, i) => _buildCell(context, _cells[i]),
    );
  }

  Widget _buildCell(BuildContext context, NoteCell cell) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
      child: Row(
        children: [
          Icon(
            cell.type == CellType.markdown
                ? Icons.text_fields
                : Icons.brush_outlined,
            size: 12,
            color: inkGray.withAlpha(80),
          ),
          const Spacer(),
          if (_cells.length > 1)
            GestureDetector(
              onTap: () => _deleteCell(cell.id),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 12, color: inkGray.withAlpha(80)),
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cell.type == CellType.markdown)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: accentFlight, width: borderWidth),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _textCtrls[cell.id],
                    focusNode: _focusNodes[cell.id],
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: bodyL.copyWith(color: inkColor(context)),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          DrawingCell(
            header: header,
            data: cell.drawingData ?? DrawingData(),
            onChanged: (data) {
              cell.drawingData = data;
              _onContentChanged();
            },
            onDelete: () => _deleteCell(cell.id),
            onDrawStart: () => setState(() => _isDrawing = true),
            onDrawEnd: () => setState(() => _isDrawing = false),
            onScrollLockChanged: (locked) {
              setState(() {
                if (locked) {
                  _scrollLockedCells.add(cell.id);
                } else {
                  _scrollLockedCells.remove(cell.id);
                }
              });
            },
          ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cell in _cells)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: cell.type == CellType.markdown
                  ? _MarkdownPreview(content: cell.content, isDark: isDark)
                  : cell.drawingData != null
                      ? SizedBox(
                          height: cell.drawingData!.height,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: DrawingPreviewPainter(
                                strokes: cell.drawingData!.strokes),
                            size: Size.infinite,
                          ),
                        )
                      : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  void _showFightPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.2,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => FightPanel(
          folderId: widget.folder.id,
          scrollController: scrollController,
          onTapTask: (task) {
            _insertBlock('\n- [ ] ${task.content}\n');
            ref.read(taskRepositoryProvider).markDone(task.id);
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Tarea insertada como checklist y completada'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Supporting widgets ──────────────────────────────────────────────────────

class _DotGrid extends StatelessWidget {
  final bool isDark;
  const _DotGrid({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _DotGridPainter(isDark: isDark)),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final bool isDark;
  const _DotGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(25)
      ..strokeCap = StrokeCap.round;
    const spacing = 24.0;
    const dotSize = 1.5;
    for (var y = spacing; y < size.height; y += spacing) {
      for (var x = spacing; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.isDark != isDark;
}

class _NoteHeader extends StatelessWidget {
  final Folder folder;
  final TextEditingController titleController;
  final bool isDirty;
  final bool isPreview;
  final VoidCallback onTogglePreview;
  final VoidCallback onLinkToLab;
  final VoidCallback onSave;
  final VoidCallback onExportPdf;
  final VoidCallback onBack;

  const _NoteHeader({
    required this.folder,
    required this.titleController,
    required this.isDirty,
    required this.isPreview,
    required this.onTogglePreview,
    required this.onLinkToLab,
    required this.onSave,
    required this.onExportPdf,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          bottom: BorderSide(color: inkColor(context), width: borderWidth),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child:
                  Icon(Icons.arrow_back, color: inkColor(context), size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: titleController,
              style: displayL.copyWith(color: folder.color),
              decoration: InputDecoration(
                hintText: 'Sin título',
                hintStyle: displayL.copyWith(color: inkGray),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSave,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isDirty ? accentFlight : Colors.transparent,
                border: Border.all(
                  color: isDirty ? accentFlight : inkGray.withAlpha(80),
                  width: 1,
                ),
              ),
              child: Icon(Icons.check, size: 16,
                  color: isDirty ? paperLight : inkGray.withAlpha(80)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTogglePreview,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isPreview ? accentLab : Colors.transparent,
                border: Border.all(
                  color: isPreview ? accentLab : inkGray.withAlpha(80),
                  width: 1,
                ),
              ),
              child: Icon(
                isPreview ? Icons.edit_outlined : Icons.visibility_outlined,
                size: 16,
                color: isPreview ? paperLight : inkGray.withAlpha(80),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onLinkToLab,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accentFlight,
                border: Border.all(color: accentFlight, width: 1),
              ),
              child: Icon(Icons.link, size: 16, color: paperLight),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExportPdf,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accentJournal,
                border: Border.all(color: inkBlack, width: borderWidth),
                boxShadow: const [
                  BoxShadow(
                    color: inkBlack,
                    offset: shadowOffset,
                    blurRadius: shadowBlurRadius,
                  ),
                ],
              ),
              child: const Icon(
                Icons.picture_as_pdf,
                size: 16,
                color: paperLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownPreview extends ConsumerWidget {
  final String content;
  final bool isDark;

  const _MarkdownPreview({required this.content, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(activeFoldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];

    SpanNode? customTextGenerator(
        m.Node node, MarkdownConfig config, WidgetVisitor visitor) {
      if (node is m.Text) {
        final text = node.text;
        final regex = RegExp(r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)');
        final matches = regex.allMatches(text).toList();

        if (matches.isNotEmpty) {
          final matchedSpans = <MapEntry<Match, Folder>>[];
          for (final match in matches) {
            final folderName = match.group(1)!;
            final cleanFolder = removeAccents(folderName.toLowerCase());
            final matchingFolders = folders.where(
              (f) => removeAccents(f.name.toLowerCase()) == cleanFolder,
            );
            if (matchingFolders.isNotEmpty) {
              matchedSpans.add(MapEntry(match, matchingFolders.first));
            }
          }
          if (matchedSpans.isNotEmpty) {
            final root = ConcreteElementNode();
            int lastIndex = 0;
            final defaultStyle =
                config.p.textStyle ?? TextStyle(color: inkColor(context));
            for (final item in matchedSpans) {
              final match = item.key;
              final folder = item.value;
              if (match.start > lastIndex) {
                root.accept(TextNode(
                    text: text.substring(lastIndex, match.start),
                    style: defaultStyle));
              }
              root.accept(TextNode(
                  text: match.group(0)!.substring(1),
                  style: defaultStyle.copyWith(
                      color: folder.color, fontWeight: FontWeight.bold)));
              lastIndex = match.end;
            }
            if (lastIndex < text.length) {
              root.accept(TextNode(
                  text: text.substring(lastIndex), style: defaultStyle));
            }
            return root;
          }
        }
      }
      return null;
    }

    final generator = MarkdownGenerator(
      textGenerator: customTextGenerator,
      inlineSyntaxList: [LatexSyntax()],
      blockSyntaxList: [const LatexBlockSyntax(), const AlignmentBlockSyntax()],
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'latex',
          generator: (e, config, visitor) =>
              LatexNode(e.attributes, e.textContent, config),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'align',
          generator: (e, config, visitor) =>
              AlignmentNode(e.attributes['align'] ?? 'left', e.textContent, config),
        ),
      ],
    );

    return MarkdownWidget(
      data: content,
      shrinkWrap: true,
      markdownGenerator: generator,
      config: MarkdownConfig(configs: [
        PConfig(textStyle: bodyL.copyWith(color: inkColor(context))),
        H1Config(style: displayL.copyWith(color: inkColor(context))),
        H2Config(style: displayM.copyWith(color: inkColor(context))),
        H3Config(
            style: displayM.copyWith(
                color: inkColor(context), fontSize: 20)),
        CodeConfig(
            style: mono.copyWith(
                color: inkColor(context),
                backgroundColor: cardBackground(context))),
        BlockquoteConfig(textColor: inkGray, sideColor: accentFlight),
        ImgConfig(
          builder: (url, attributes) {
            final maxW = MediaQuery.of(context).size.width * 0.75;
            Widget img;
            if (url.startsWith('/')) {
              img = Image.file(File(url),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(
                      '[Imagen no encontrada]',
                      style: bodyS.copyWith(color: inkGray)));
            } else {
              img = Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text('[Imagen: $url]',
                      style: bodyS.copyWith(color: inkGray)));
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: 300, maxWidth: maxW),
                child: img,
              ),
            );
          },
        ),
      ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final void Function(String)? onInsertBlock;
  final void Function(InsertPanelType) onOpenPanel;
  final VoidCallback onToggleFightPanel;
  final TextEditingController? contentController;
  final VoidCallback onAddMarkdownCell;
  final VoidCallback onAddDrawingCell;

  const _BottomBar({
    this.onInsertBlock,
    required this.onOpenPanel,
    required this.onToggleFightPanel,
    this.contentController,
    required this.onAddMarkdownCell,
    required this.onAddDrawingCell,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context), width: borderWidth),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleFightPanel,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Tareas pendientes',
                  style: bodyS.copyWith(color: inkGray)),
            ),
          ),
          Container(height: 1, color: inkGray.withAlpha(60)),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _cellBtn(context, '+ Texto', Icons.text_fields,
                    onAddMarkdownCell),
                const SizedBox(width: 6),
                _cellBtn(context, '+ Dibujo', Icons.brush_outlined,
                    onAddDrawingCell),
                if (onInsertBlock != null) ...[
                  const SizedBox(width: 10),
                  CoachMark(
                    flagKey: 'block_insert',
                    message:
                        'Inserta imágenes, LaTeX, código, tablas y más.',
                    position: CoachMarkPosition.above,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => BlockInsertMenu(
                          onDirectInsert: onInsertBlock!,
                          onOpenPanel: onOpenPanel,
                        ),
                      ),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: inkColor(context),
                              width: borderWidth),
                        ),
                        child: Center(
                          child: Text('+',
                              style: displayM.copyWith(
                                  color: inkColor(context),
                                  height: 1,
                                  fontSize: 18)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FormatToolbar(controller: contentController),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cellBtn(
      BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: inkColor(context), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: inkColor(context)),
            const SizedBox(width: 4),
            Text(label, style: bodyS.copyWith(color: inkColor(context))),
          ],
        ),
      ),
    );
  }
}

// ─── LaTeX support ───────────────────────────────────────────────────────────

class LatexNode extends SpanNode {
  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;

  LatexNode(this.attributes, this.textContent, this.config);

  @override
  InlineSpan build() {
    final content = attributes['content'] ?? '';
    final isInline = attributes['isInline'] == 'true';
    final style = parentStyle ?? config.p.textStyle ?? const TextStyle();
    if (content.isEmpty) {
      return TextSpan(style: style, text: textContent);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Math.tex(
        content,
        mathStyle: isInline ? MathStyle.text : MathStyle.display,
        textStyle: style,
        onErrorFallback: (err) =>
            Text(textContent, style: style.copyWith(color: Colors.red)),
      ),
    );
  }
}

class LatexBlockSyntax extends m.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^\$\$\s*$');
  const LatexBlockSyntax() : super();

  @override
  m.Node? parse(m.BlockParser parser) {
    final contentLines = <String>[];
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      if (pattern.hasMatch(line)) {
        parser.advance();
        break;
      }
      contentLines.add(line);
      parser.advance();
    }
    final content = contentLines.join('\n');
    final element = m.Element('latex', [m.Text(content)]);
    element.attributes['content'] = content;
    element.attributes['isInline'] = 'false';
    return element;
  }
}

class LatexSyntax extends m.InlineSyntax {
  LatexSyntax()
      : super(
            r'(\$\$(?!\s)([\s\S]+?)(?<!\s)\$\$)|(\$(?!\s)([^$\n]+?)(?<!\s)\$)');

  @override
  bool onMatch(m.InlineParser parser, Match match) {
    final matchValue = match.group(0)!;
    String content = '';
    bool isInline = true;
    if (matchValue.startsWith(r'$$') && matchValue.endsWith(r'$$')) {
      isInline = false;
      content = matchValue.substring(2, matchValue.length - 2).trim();
    } else if (matchValue.startsWith(r'$') && matchValue.endsWith(r'$')) {
      isInline = true;
      content = matchValue.substring(1, matchValue.length - 1).trim();
    }
    final element = m.Element.text('latex', matchValue);
    element.attributes['content'] = content;
    element.attributes['isInline'] = '$isInline';
    parser.addNode(element);
    return true;
  }
}

class AlignmentNode extends SpanNode {
  final String align;
  final String textContent;
  final MarkdownConfig config;

  AlignmentNode(this.align, this.textContent, this.config);

  @override
  InlineSpan build() {
    final textAlignment = switch (align) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    final style = parentStyle ?? config.p.textStyle;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          textContent,
          textAlign: textAlignment,
          style: style,
        ),
      ),
    );
  }
}

class AlignmentBlockSyntax extends m.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^:::\s*(left|center|right)\s*$');
  const AlignmentBlockSyntax() : super();

  @override
  m.Node? parse(m.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    if (match == null) return null;
    final align = match.group(1)!;
    final contentLines = <String>[];
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      if (RegExp(r'^:::\s*$').hasMatch(line)) {
        parser.advance();
        break;
      }
      contentLines.add(line);
      parser.advance();
    }
    final content = contentLines.join('\n');
    final element = m.Element('align', [m.Text(content)]);
    element.attributes['align'] = align;
    return element;
  }
}

// ─── Kanban linking ──────────────────────────────────────────────────────────

class _SendNoteToKanbanSheet extends ConsumerWidget {
  final Note note;
  final ValueChanged<int> onLinked;

  const _SendNoteToKanbanSheet({
    required this.note,
    required this.onLinked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final spaces = spacesAsync.valueOrNull ?? [];

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context), width: borderWidthHeavy),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text('Vincular a Lab Space',
                  style: labelBold.copyWith(color: inkGray)),
            ),
            if (spaces.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text(
                    'No hay Lab Spaces activos. Crea uno primero.',
                    style: bodyS.copyWith(color: inkGray)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: spaces
                      .map((space) => _SpaceNoteLinkRow(
                          note: note, space: space, onLinked: onLinked))
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SpaceNoteLinkRow extends ConsumerWidget {
  final Note note;
  final LabSpace space;
  final ValueChanged<int> onLinked;

  const _SpaceNoteLinkRow({
    required this.note,
    required this.space,
    required this.onLinked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columnsAsync = ref.watch(kanbanColumnsProvider(space.id));
    final columns = columnsAsync.valueOrNull ?? [];

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Text(space.name,
          style: bodyM.copyWith(
              color: space.accentColor, fontWeight: FontWeight.w700)),
      children: columns
          .map((col) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final card =
                      await ref.read(kanbanCardRepositoryProvider).create(
                            labSpaceId: space.id,
                            columnId: col.id,
                            title: note.displayTitle,
                            sourceNoteId: note.id,
                          );
                  onLinked(card.id);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 10, 24, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(col.name,
                        style: bodyM.copyWith(color: inkColor(context))),
                  ),
                ),
              ))
          .toList(),
    );
  }
}
