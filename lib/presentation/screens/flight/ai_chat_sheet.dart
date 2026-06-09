import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/note_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../widgets/ai_working_dialog.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../../domain/services/ai_assistant.dart';
import '../../../domain/models/note.dart' show NoteKind;
import '../../../domain/models/note_block.dart';
import '../../../domain/models/task.dart';
import '../../../domain/models/canvas_context_source.dart';
import '../../../data/services/context_cache.dart';
import '../../../data/services/web_reader.dart' show WebReaderException;
import 'ai_chat_session.dart';
import 'context_assembler.dart' as ctx;
import 'ocr_send_to_note.dart' show sendTextToNote;
// Reuse the notes' markdown renderer (markdown_widget + flutter_math_fork) so
// the assistant's markdown/LaTeX renders exactly like a note.
import 'note_block_widgets.dart' show NoteMarkdownPreview, fixMarkdownTables;

/// Open the AI chat for a note view. The conversation is the per-note
/// [AiChatSession] (persists while you're in the view; the sheet is a window).
/// [newContext] (from OCR / a note) sets the anchor, or — if one already
/// exists — asks **Añadir o Reemplazar**. Cold (no context, no anchor) → asks
/// "¿De qué es esto?".
Future<void> showAiChat(
  BuildContext context,
  WidgetRef ref, {
  required int noteId,
  String? newContext,
  String? prefillMessage,
  required Color accent,

  /// When non-null, AI replies show an "Enviar a lienzo" action that drops the
  /// reply (raw markdown) onto the host canvas as a [CanvasTextBlock]. Only the
  /// whiteboard/notebook editors pass this; a plain note leaves it null.
  void Function(String markdown)? onSendToCanvas,

  /// When non-null, the "Título" action suggests titles and applies the chosen
  /// one here (the note editor wires its title field). Null → no title action.
  void Function(String title)? onApplyTitle,
}) async {
  final hasKey = await ref.read(aiKeyStoreProvider).hasKey();
  if (!context.mounted) return;
  if (!hasKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configura tu API key de DeepSeek en Ajustes'),
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }

  final session = ref.read(aiSessionProvider(noteId));
  final ctx = newContext?.trim();
  if (ctx != null && ctx.isNotEmpty) {
    if (!session.hasAnchor) {
      session.setAnchor(ctx);
    } else if (ctx != session.anchor) {
      // Different incoming context → ask. (Unchanged → just reopen, no prompt.)
      final choice = await _chooseContextAction(context, accent);
      if (!context.mounted) return;
      if (choice == _CtxAction.add) {
        session.appendAnchor(ctx);
      } else if (choice == _CtxAction.replace) {
        session.setAnchor(ctx);
      }
      // cancel → keep current anchor, still open the chat.
    }
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => _AiChatSheet(
          session: session,
          accent: accent,
          prefillMessage: prefillMessage,
          onSendToCanvas: onSendToCanvas,
          onApplyTitle: onApplyTitle,
        ),
  );
}

/// Chat about a LAB space (phase 2). Reuses the chat sheet in "board mode": the
/// context is the serialized Kanban board ([buildContext]), refreshed via ↻; no
/// note/canvas UI. Session is namespaced ('lab') so it doesn't collide with
/// note sessions sharing the same int id.
Future<void> showLabChat(
  BuildContext context,
  WidgetRef ref, {
  required int spaceId,
  required String boardLabel,
  required Color accent,
  required Future<String> Function() buildContext,
}) async {
  final hasKey = await ref.read(aiKeyStoreProvider).hasKey();
  if (!context.mounted) return;
  if (!hasKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configura tu API key de DeepSeek en Ajustes'),
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }
  final session = ref.read(aiLabSessionProvider(spaceId));
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => _AiChatSheet(
          session: session,
          accent: accent,
          isBoard: true,
          boardLabel: boardLabel,
          onResyncContext:
              () async => session.setSyncedAnchor(await buildContext()),
        ),
  );
}

enum _CtxAction { add, replace }

Future<_CtxAction?> _chooseContextAction(BuildContext context, Color accent) {
  return showModalBottomSheet<_CtxAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder:
        (_) => Container(
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(
              top: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'YA HAY CONTEXTO',
                  style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '¿Qué hago con el contexto nuevo?',
                  style: yBody(size: 13, color: yMuted),
                ),
                const SizedBox(height: 14),
                _bigChoice(
                  'AÑADIR AL CONTEXTO',
                  accent,
                  true,
                  () => Navigator.pop(context, _CtxAction.add),
                ),
                const SizedBox(height: 8),
                _bigChoice(
                  'REEMPLAZAR CONTEXTO',
                  accent,
                  false,
                  () => Navigator.pop(context, _CtxAction.replace),
                ),
              ],
            ),
          ),
        ),
  );
}

Widget _bigChoice(String label, Color accent, bool filled, VoidCallback onTap) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? accent : yCream,
        border: Border.all(
          color: filled ? yBorderStrong : accent,
          width: yLineMid,
        ),
      ),
      child: Text(
        label,
        style: yMono(
          size: 12,
          weight: FontWeight.w700,
          tracking: 1.2,
          color: filled ? yCream : yInk,
        ),
      ),
    ),
  );
}

class _AiChatSheet extends ConsumerStatefulWidget {
  final AiChatSession session;
  final Color accent;
  final String? prefillMessage;
  final void Function(String markdown)? onSendToCanvas;
  final void Function(String title)? onApplyTitle;

  /// Board mode (LAB): the context is a serialized Kanban board (not a note).
  /// Hides note-specific UI (sources/canvas/save-to-note/extract-tasks) and uses
  /// [onResyncContext] to refresh the anchor from the live board.
  final bool isBoard;
  final String? boardLabel;
  final Future<void> Function()? onResyncContext;

  const _AiChatSheet({
    required this.session,
    required this.accent,
    this.prefillMessage,
    this.onSendToCanvas,
    this.onApplyTitle,
    this.isBoard = false,
    this.boardLabel,
    this.onResyncContext,
  });

  @override
  ConsumerState<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<_AiChatSheet>
    with TickerProviderStateMixin {
  final _input = TextEditingController();
  final _anchorInput = TextEditingController();
  final _scroll = ScrollController();
  int? _remaining;
  late final AnimationController _aiSpinCtrl;

  AiChatSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSession);
    _loadRemaining();
    // Drives the erratic rotation of the diamond inside the AI mark.
    _aiSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    // If there are existing messages, jump to the latest one on first open.
    if (_s.messages.isNotEmpty) _scrollToBottom();
    final prefill = widget.prefillMessage?.trim();
    if (prefill != null && prefill.isNotEmpty) _input.text = prefill;
    // If this canvas is linked to a source note, resync the context on open.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) =>
          widget.isBoard
              ? widget.onResyncContext?.call()
              : _resyncFromSources(),
    );
  }

  // ─── Canvas context sources (notes + urls) — assembly & sync ──────────────

  DateTime? _syncedAt;

  /// Rebuild the anchor from ALL context sources. For **block notes** the
  /// note's own content is the primary source (implicit, no DB row) followed by
  /// any additional sources (other notes + urls). For **canvases**, reads all DB
  /// sources (notes + urls), no implicit self-source.
  Future<void> _resyncFromSources() async {
    final repo = ref.read(noteRepositoryProvider);
    final note = await repo.getById(_s.noteId);
    if (note == null) return;
    final isBlock = note.kind == NoteKind.block;

    final pieces = <String>[];

    // Block note: own content is always the first (implicit) source.
    if (isBlock) {
      final blocks = await ref.read(noteBlocksProvider(_s.noteId).future);
      final label =
          (note.title?.trim().isEmpty ?? true) ? 'Nota' : note.title!.trim();
      final raw = _extractNoteContext(blocks);
      if (raw.trim().isNotEmpty) {
        final piece = await _compactPiece('note:${note.id}', raw);
        pieces.add('## $label\n\n$piece');
      }
    }

    // Additional sources from DB: URLs for block notes; notes + URLs for canvases.
    final sources = await repo.getContextSources(_s.noteId);
    for (final s in sources) {
      if (!s.enabled) continue; // user-toggled off
      if (s.isNote && s.ref == _s.noteId.toString()) continue; // skip self-ref
      String raw;
      String label;
      String key;
      if (s.isNote) {
        final nid = s.noteId;
        if (nid == null) {
          await repo.removeContextSource(s.id);
          continue;
        }
        final srcNote = await repo.getById(nid);
        if (srcNote == null) {
          await repo.removeContextSource(s.id);
          continue;
        }
        final blocks = await ref.read(noteBlocksProvider(nid).future);
        label =
            (srcNote.title?.trim().isEmpty ?? true)
                ? 'Nota'
                : srcNote.title!.trim();
        raw = _extractNoteContext(blocks);
        key = 'note:$nid';
      } else {
        label = (s.label?.trim().isEmpty ?? true) ? s.ref : s.label!.trim();
        raw = (await readUrlContent(s.ref)) ?? '';
        key = 'url:${contextStableHash(s.ref)}';
      }
      if (raw.trim().isEmpty) continue;
      final piece = await _compactPiece(key, raw);
      pieces.add('## $label\n\n$piece');
    }

    if (pieces.isEmpty) return; // empty block note → no anchor yet

    _s.setSyncedAnchor(pieces.join('\n\n---\n\n'));
    if (mounted) setState(() => _syncedAt = DateTime.now());
  }

  /// Compact a single source if it's long, caching the result by content hash
  /// (one compaction per source version, reused thereafter). Short → as-is.
  Future<String> _compactPiece(String key, String raw) =>
      ctx.compactPiece(ref, key, raw);

  /// Open the "Fuentes" manager (add/remove notes + urls; refetch a url).
  Future<void> _showSourcesSheet() async {
    final note = ref.read(noteByIdProvider(_s.noteId)).valueOrNull;
    if (note == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _SourcesSheet(
            canvasNoteId: _s.noteId,
            folderId: note.folderId,
            accent: widget.accent,
            onChanged: _resyncFromSources,
          ),
    );
  }

  @override
  void dispose() {
    _aiSpinCtrl.dispose();
    _s.removeListener(_onSession);
    _input.dispose();
    _anchorInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSession() {
    _scrollToBottom();
    if (!_s.streaming) _loadRemaining();
  }

  Future<void> _loadRemaining() async {
    final r = await ref.read(aiUsageLimiterProvider).remaining();
    if (mounted) setState(() => _remaining = r);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send(String text, {bool quickAction = false}) {
    if (text.trim().isEmpty || _s.streaming || !_s.hasAnchor) return;
    if (!quickAction) _input.clear();
    _s.send(
      ref.read(aiAssistantProvider),
      ref.read(aiUsageLimiterProvider),
      text,
      quickAction: quickAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: FractionallySizedBox(
        heightFactor: 0.95,
        child: Container(
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(
              top: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
          ),
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _s,
              builder: (_, _) {
                // Board (LAB) mode: always the chat; context is the serialized
                // board, no note/canvas providers involved.
                if (widget.isBoard) return _buildChat();
                final hostKind =
                    ref.watch(noteByIdProvider(_s.noteId)).valueOrNull?.kind;
                final isBlock = hostKind == NoteKind.block;
                // Block notes: show the chat only when there's actual content
                // (hasAnchor set by _resyncFromSources). Empty → gate.
                final linked =
                    (ref
                        .watch(canvasContextSourcesProvider(_s.noteId))
                        .valueOrNull
                        ?.isNotEmpty) ??
                    false;
                final showChat =
                    isBlock ? _s.hasAnchor : (_s.hasAnchor || linked);
                return showChat ? _buildChat() : _buildAnchorGate(isBlock);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnchorGate([bool isBlock = false]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isBlock) ...[
                Text(
                  'ESTA NOTA ESTÁ VACÍA',
                  style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Importa otra nota o agrega un enlace para darle contexto a la IA.',
                  style: yMono(size: 10, tracking: 0.4, color: yMuted),
                ),
              ] else ...[
                Text(
                  '¿DE QUÉ ES ESTO?',
                  style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Dale un punto de partida (ej. "Proceso de Markov"). Queda como '
                  'contexto de la conversación; puedes editarlo luego.',
                  style: yMono(size: 10, tracking: 0.4, color: yMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _anchorInput,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  style: yBody(size: 15, color: yInk),
                  onSubmitted: (v) => _s.setAnchor(v),
                  decoration: _fieldDeco('¿Sobre qué quieres hablar?'),
                ),
                const SizedBox(height: 12),
                _primaryButton(
                  'EMPEZAR',
                  () => _s.setAnchor(_anchorInput.text),
                ),
                const SizedBox(height: 10),
              ],
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showNotePicker,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: yCream,
                    border: Border.all(color: yBorderStrong, width: yLineMid),
                  ),
                  child: Text(
                    'IMPORTAR NOTA',
                    style: yMono(
                      size: 12,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _showSourcesSheet,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: yCream,
                    border: Border.all(color: widget.accent, width: yLineMid),
                  ),
                  child: Text(
                    'FUENTES DE CONTEXTO',
                    style: yMono(
                      size: 12,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Open a bottom sheet listing the other notes in the same folder so the
  /// user can pick one to import as the chat anchor.
  void _showNotePicker() async {
    final noteAsync = ref.read(noteByIdProvider(_s.noteId));
    final note = noteAsync.valueOrNull;
    if (note == null) return;
    final folderId = note.folderId;
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final notesAsync = ref.watch(notesByFolderProvider(folderId));
        final notes = notesAsync.valueOrNull ?? [];
        // Exclude the current note itself (pizarra / cuaderno / nota).
        final others = notes.where((n) => n.id != _s.noteId).toList();

        return Container(
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(
              top: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'IMPORTAR NOTA',
                  style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk,
                  ),
                ),
                const SizedBox(height: 10),
                if (others.isEmpty)
                  Text(
                    'No hay otras notas en esta carpeta.',
                    style: yBody(size: 13, color: yMuted),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: others.length,
                      itemBuilder: (_, i) {
                        final n = others[i];
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            final blocksAsync = await ref.read(
                              noteBlocksProvider(n.id).future,
                            );
                            final ctxText = _extractNoteContext(blocksAsync);
                            if (ctxText.isNotEmpty) {
                              _s.setAnchor(ctxText);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: yBorderStrong,
                                  width: yLineThin,
                                ),
                              ),
                            ),
                            child: Text(
                              (n.title?.isEmpty ?? true)
                                  ? 'Sin título'
                                  : n.title!,
                              style: ySans(
                                size: 14,
                                weight: FontWeight.w700,
                                color: yInk,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Extract a plain-text context from a note's blocks (same rules as the
  /// note editor: text + bullets + math; skip tasks & drawings).
  String _extractNoteContext(List<NoteBlock> blocks) =>
      ctx.extractNoteContext(blocks);

  Widget _buildChat() {
    return Column(
      children: [
        _header(),
        _contextBar(),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
            children: [
              // Canned greeting (UI-only, no request) when the thread is empty.
              if (_s.messages.isEmpty) _greeting(),
              for (int i = 0; i < _s.messages.length; i++)
                _bubble(_s.messages[i], i),
            ],
          ),
        ),
        _quickActions(),
        _inputBar(),
      ],
    );
  }

  /// Branches: block notes get the implicit "NOTA COMO CONTEXTO" bar; canvases
  /// show the SINCRONIZADA / CONTEXTO bar as before.
  Widget _contextBar() {
    if (widget.isBoard) return _boardContextBar();
    final hostKind = ref.watch(noteByIdProvider(_s.noteId)).valueOrNull?.kind;
    if (hostKind == NoteKind.block) return _noteContextBar();
    final sources =
        ref.watch(canvasContextSourcesProvider(_s.noteId)).valueOrNull ??
        const [];
    if (sources.isNotEmpty) return _linkedContextBar(sources.length);
    return _normalContextBar();
  }

  /// TABLERO ▸ [proyecto] · hace Xmin   ↻ (re-serializa el board)
  Widget _boardContextBar() {
    final ago = _syncedAt == null ? '' : ' · ${_agoLabel(_syncedAt!)}';
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
      child: Row(
        children: [
          Container(width: 8, height: 8, color: widget.accent),
          const SizedBox(width: 8),
          Text(
            'TABLERO ▸',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.2,
              color: yInk,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.boardLabel ?? ''}$ago',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: yBody(size: 13, weight: FontWeight.w700, color: yInk),
            ),
          ),
          const SizedBox(width: 8),
          _ghostIcon(YuLiIcons.refresh, 'Re-sincronizar tablero', () async {
            await widget.onResyncContext?.call();
            if (mounted) setState(() => _syncedAt = DateTime.now());
          }),
        ],
      ),
    );
  }

  /// NOTA COMO CONTEXTO · [N enlaces]   [🔗]
  Widget _noteContextBar() {
    final urls =
        (ref.watch(canvasContextSourcesProvider(_s.noteId)).valueOrNull ??
                const [])
            .where((s) => s.isUrl)
            .length;
    final urlLabel = urls == 0 ? '' : ' · $urls enlaces';
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
      child: Row(
        children: [
          Container(width: 8, height: 8, color: widget.accent),
          const SizedBox(width: 8),
          Text(
            'NOTA COMO CONTEXTO$urlLabel',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.2,
              color: yInk,
            ),
          ),
          const Spacer(),
          _ghostIcon(YuLiIcons.link, 'Fuentes de contexto', _showSourcesSheet),
        ],
      ),
    );
  }

  /// CONTEXTO ▸ [texto del ancla]  ✎  ✕  🔗
  Widget _normalContextBar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
      child: Row(
        children: [
          Text(
            'CONTEXTO ▸',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _editContext,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: yCream,
                  border: Border.all(color: yBorderStrong, width: yLineMid),
                ),
                child: Text(
                  _s.anchor ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: yBody(size: 13, weight: FontWeight.w600, color: yInk),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ghostIcon(YuLiIcons.link, 'Fuentes de contexto', _showSourcesSheet),
          const SizedBox(width: 6),
          _ghostIcon(YuLiIcons.pen, 'Editar contexto', _editContext),
          const SizedBox(width: 6),
          _ghostIcon(YuLiIcons.close, 'Quitar contexto', () => _s.setAnchor('')),
        ],
      ),
    );
  }

  /// SINCRONIZADA ▸ N fuentes · hace Xmin   ↻(notas)   ⚙(gestionar)
  Widget _linkedContextBar(int count) {
    final ago = _syncedAt == null ? '' : ' · ${_agoLabel(_syncedAt!)}';
    final label = count == 1 ? '1 fuente' : '$count fuentes';
    return Container(
      decoration: BoxDecoration(
        color: yCream2,
        border: const Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
      child: Row(
        children: [
          Container(width: 8, height: 8, color: widget.accent),
          const SizedBox(width: 8),
          Text(
            'SINCRONIZADA ▸',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.2,
              color: yInk,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showSourcesSheet,
              child: Text(
                '$label$ago',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: yBody(size: 13, weight: FontWeight.w700, color: yInk),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Re-reads local notes only; urls are refreshed per-source from the
          // Fuentes sheet (no surprise network).
          _ghostIcon(YuLiIcons.refresh, 'Re-sincronizar notas', _resyncFromSources),
          const SizedBox(width: 6),
          _ghostIcon(YuLiIcons.slidersHorizontal, 'Gestionar fuentes', _showSourcesSheet),
        ],
      ),
    );
  }

  String _agoLabel(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'recién';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  Widget _ghostIcon(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
          ),
          child: Icon(icon, size: 14, color: yInk),
        ),
      ),
    );
  }

  /// UI-only greeting bubble shown when the conversation is empty.
  Widget _greeting() => _aiMsgFrame(
    const Text(
      'Hola. Tengo tu contexto cargado, ¿qué hacemos con él?',
      style: TextStyle(fontSize: 15, height: 1.5, color: yInk),
    ),
  );

  static const _kDailyCap = 150;

  /// Command bar: ink background, mark + wordmark + FLASH|PRO segmented control
  /// + usage meter + close. Accent = the note's accent (everything is accent).
  Widget _header() {
    final used =
        _remaining == null
            ? null
            : (_kDailyCap - _remaining!).clamp(0, _kDailyCap);
    return Container(
      decoration: const BoxDecoration(
        color: yInk,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          // Mark: accent square with a cream diamond.
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.accent,
              border: Border.all(color: yCream, width: yLineMid),
            ),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 12, height: 12, color: yCream),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YuLi · IA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ySans(
                    size: 18,
                    weight: FontWeight.w700,
                    color: yCream,
                  ),
                ),
                Text(
                  widget.isBoard
                      ? 'ASISTENTE DE PROYECTO'
                      : 'ASISTENTE DE NOTAS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: yMono(
                    size: 8,
                    tracking: 1.6,
                    color: yCream.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // FLASH | PRO segmented control.
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: yCream, width: yLineMid),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _seg(
                  'FLASH',
                  _s.model == AiModel.flash,
                  () => _s.setModel(AiModel.flash),
                ),
                Container(width: yLineThin, height: 24, color: yCream),
                _seg(
                  'PRO',
                  _s.model == AiModel.pro,
                  () => _s.setModel(AiModel.pro),
                ),
              ],
            ),
          ),
          if (used != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 58,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$used/$_kDailyCap',
                    textAlign: TextAlign.right,
                    style: yMono(size: 9, tracking: 0.6, color: yCream),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      border: Border.all(color: yCream, width: 1),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (used / _kDailyCap).clamp(0.0, 1.0),
                      child: Container(color: widget.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: yCream, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.close, size: 16, color: yCream),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        color: active ? widget.accent : Colors.transparent,
        child: Text(
          label,
          style: yMono(
            size: 10,
            weight: FontWeight.w700,
            tracking: 1.0,
            color: yCream,
          ),
        ),
      ),
    );
  }

  Widget _aiAvatar() {
    return AnimatedBuilder(
      animation: _aiSpinCtrl,
      builder: (_, _) {
        final poses = [
          [-0.72, 0.34, -0.10],
          [-0.26, -0.92, 0.12],
          [0.72, 0.34, 0.10],
          [0.26, 0.92, -0.12],
        ];
        final step = _aiSpinCtrl.value * poses.length;
        final i = step.floor() % poses.length;
        final next = (i + 1) % poses.length;
        final local = step - step.floor();
        final jump =
            local < 0.16
                ? 0.0
                : Curves.easeInOutCubic.transform(
                  ((local - 0.16) / 0.84).clamp(0, 1),
                );
        final yaw = poses[i][0] + (poses[next][0] - poses[i][0]) * jump;
        final pitch = poses[i][1] + (poses[next][1] - poses[i][1]) * jump;
        final roll = poses[i][2] + (poses[next][2] - poses[i][2]) * jump;
        return _AiCubeMark(
          accent: widget.accent,
          yaw: yaw,
          pitch: pitch,
          roll: roll,
        );
      },
    );
  }

  /// Assistant message frame: mark + "YULI · IA" label + cream bubble (hard
  /// shadow) holding [content], with optional [actions] under a divider.
  Widget _aiMsgFrame(Widget content, {List<Widget>? actions}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiAvatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Text(
                    'YULI · IA',
                    style: yMono(
                      size: 9,
                      weight: FontWeight.w700,
                      tracking: 1.6,
                      color: yMuted,
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                  decoration: BoxDecoration(
                    color: yCream,
                    border: Border.all(color: yBorderStrong, width: yLineMid),
                    boxShadow: const [
                      BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      content,
                      if (actions != null && actions.isNotEmpty) ...[
                        const SizedBox(height: 11),
                        Container(
                          height: yLineThin,
                          color: yInk.withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 11),
                        Wrap(spacing: 6, runSpacing: 6, children: actions),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _msgActionBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(
          label.toUpperCase(),
          style: yMono(
            size: 9,
            weight: FontWeight.w700,
            tracking: 0.8,
            color: yInk,
          ),
        ),
      ),
    );
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado'),
        duration: Duration(milliseconds: 700),
      ),
    );
  }

  /// Drop this reply (raw markdown) onto the host canvas as a text block, then
  /// close the sheet so the new block is visible. Same engine as note cells →
  /// it renders identically.
  void _sendToCanvas(String text) {
    final send = widget.onSendToCanvas;
    if (send == null) return;
    send(text.trim());
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
  }

  String _cleanTaskLine(String s) =>
      s.replaceAll('**', '').replaceAll('`', '').trim();

  /// Pull candidate task lines from an assistant reply. Prefers bulleted /
  /// numbered / checkbox lines; if there are none, falls back to all lines.
  List<String> _parseTaskLines(String text) {
    final bulletRe = RegExp(r'^\s*([-*•·]|\d+[.)]|\[[ xX]?\])\s+(.*)$');
    final bulleted = <String>[];
    final all = <String>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final m = bulletRe.firstMatch(line);
      if (m != null) {
        final c = _cleanTaskLine(m.group(2)!);
        if (c.isNotEmpty) bulleted.add(c);
      }
      final a = _cleanTaskLine(line);
      if (a.isNotEmpty) all.add(a);
    }
    final src = bulleted.isNotEmpty ? bulleted : all;
    return src.map((s) => s.length > 280 ? s.substring(0, 280) : s).toList();
  }

  /// Extract tasks from [text] → review checklist → create them in FIGHT,
  /// linked to the host note.
  Future<void> _extractTasks(String text) async {
    final candidates = _parseTaskLines(text);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No encontré tareas en esa respuesta'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final note = ref.read(noteByIdProvider(_s.noteId)).valueOrNull;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _TaskReviewSheet(
            candidates: candidates,
            noteId: _s.noteId,
            folderId: note?.folderId,
            accent: widget.accent,
          ),
    );
  }

  Widget _bubble(AiChatMsg m, int i) {
    if (m.role == AiRole.system) return _systemNotice(m, i);
    if (m.role == AiRole.user) return _userBubble(m.text);

    // Assistant.
    final streaming = _s.streaming && i == _s.messages.length - 1;
    final Widget content =
        (m.text.isEmpty && streaming)
            ? Text('…', style: yBody(size: 14, color: yInk))
            : streaming
            ? SelectableText(m.text, style: yBody(size: 14, color: yInk))
            : NoteMarkdownPreview(data: fixMarkdownTables(m.text), accent: widget.accent);
    final actions =
        (!streaming && m.text.isNotEmpty)
            ? <Widget>[
              _msgActionBtn('Copiar', () => _copy(m.text)),
              // Note-specific actions are hidden in board (LAB) mode.
              if (!widget.isBoard)
                _msgActionBtn('Guardar en nota', () {
                  final note =
                      ref.read(noteByIdProvider(_s.noteId)).valueOrNull;
                  sendTextToNote(
                    context,
                    ref,
                    m.text,
                    defaultFolderId: note?.folderId,
                    accent: widget.accent,
                  );
                }),
              if (widget.onSendToCanvas != null)
                _msgActionBtn('Enviar a lienzo', () => _sendToCanvas(m.text)),
              _msgActionBtn(
                'Rehacer',
                () => _s.regenerate(
                  i,
                  ref.read(aiAssistantProvider),
                  ref.read(aiUsageLimiterProvider),
                ),
              ),
              if (!widget.isBoard)
                _msgActionBtn('Extraer tareas', () => _extractTasks(m.text)),
            ]
            : null;
    return _aiMsgFrame(content, actions: actions);
  }

  Widget _userBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 6),
            child: Text(
              'TÚ',
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.6,
                color: yMuted,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
              decoration: BoxDecoration(
                color: widget.accent,
                border: Border.all(color: yBorderStrong, width: yLineMid),
                boxShadow: const [
                  BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
                ],
              ),
              child: SelectableText(
                text,
                style: yBody(size: 15, weight: FontWeight.w500, color: yCream),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemNotice(AiChatMsg m, int i) {
    final canUndo = _s.canUndoCompact && i == _s.compactNoticeIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              m.text,
              textAlign: TextAlign.center,
              style: yMono(
                size: 10,
                tracking: 0.5,
                color: yMuted,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
            if (canUndo) ...[
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _s.undoCompact(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(YuLiIcons.undo, size: 11, color: yMuted),
                    const SizedBox(width: 3),
                    Text(
                      'DESHACER',
                      style: yMono(size: 8, tracking: 0.8, color: yMuted),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One-shot: ask for 3 short titles, show a pick+edit popup, apply the chosen
  /// one via [widget.onApplyTitle]. Doesn't touch the chat thread.
  Future<void> _suggestTitle() async {
    final apply = widget.onApplyTitle;
    if (apply == null) return;
    if (!_s.hasAnchor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay contexto para titular.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final limiter = ref.read(aiUsageLimiterProvider);
    if (!await limiter.canSend()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Límite diario de IA alcanzado.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) =>
              aiWorkingDialog(accent: widget.accent, label: 'Generando título'),
    );
    await limiter.record();
    final buf = StringBuffer();
    String? err;
    try {
      await for (final tok in ref.read(aiAssistantProvider).streamReply([
        const AiMessage(
          AiRole.system,
          'Sugiere títulos cortos. Responde SOLO con 3 títulos, uno por '
          'línea, máximo 6 palabras cada uno, sin numerar, sin comillas, '
          'sin explicación.',
        ),
        AiMessage(
          AiRole.user,
          '<context_documents>\n${_s.anchor}\n</context_documents>',
        ),
        const AiMessage(AiRole.user, 'Dame 3 títulos para este contenido.'),
      ], model: AiModel.flash)) {
        buf.write(tok);
      }
    } catch (e) {
      err = '$e';
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop(); // close spinner
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 3)),
      );
      return;
    }
    final options = _parseTitles(buf.toString());
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pude sugerir títulos.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder:
          (_) => _TitlePickerDialog(options: options, accent: widget.accent),
    );
    if (chosen == null || chosen.trim().isEmpty) return;
    apply(chosen.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Título aplicado'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  List<String> _parseTitles(String raw) {
    final out = <String>[];
    for (final line in raw.split('\n')) {
      var s = line.trim();
      if (s.isEmpty) continue;
      s = s.replaceFirst(RegExp(r'^\s*([-*•]|\d+[.)])\s*'), '');
      s = s.replaceAll(RegExp('^["“”\']+|["“”\']+\$'), '').trim();
      if (s.isEmpty) continue;
      out.add(s);
      if (out.length >= 3) break;
    }
    return out;
  }

  Widget _quickActions() {
    // (glyph, label, prompt, sendWithHistory)
    final items = <(IconData, String, String, bool)>[
      (YuLiIcons.listChecks, 'Resumir', 'Resume el contexto en pocas líneas.', false),
      (
        YuLiIcons.squareCheck,
        'Extraer tareas',
        'Lista las tareas accionables del contexto, una por línea, sin numerar.',
        false,
      ),
      (YuLiIcons.type, 'Título', 'Sugiere 3 títulos cortos para el contexto.', false),
      (YuLiIcons.arrowRight, 'Traducir', 'Traduce el contexto al inglés.', false),
      (
        YuLiIcons.eraser,
        'Limpiar',
        'Reescribe y limpia el contexto: corrige ortografía y redacción, '
            'mantén el significado.',
        false,
      ),
      // Uses full chat history (not a one-shot quick action).
      (
        YuLiIcons.textQuote,
        'Resumir chat',
        'Resume nuestra conversación hasta ahora en 3-4 puntos clave.',
        true,
      ),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hair(
            widget.isBoard
                ? '> ACCIONES SOBRE EL TABLERO'
                : '> ACCIONES SOBRE LA NOTA',
          ),
          const SizedBox(height: 9),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _qaChip(it.$1, it.$2, it.$3, withHistory: it.$4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hair(String label) {
    return Row(
      children: [
        Text(
          label,
          style: yMono(
            size: 10,
            weight: FontWeight.w700,
            tracking: 1.6,
            color: yMuted,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 2, color: yInk.withValues(alpha: 0.14)),
        ),
      ],
    );
  }

  Widget _qaChip(
    IconData icon,
    String label,
    String prompt, {
    required bool withHistory,
  }) {
    // "Título" with an apply target → suggest+pick popup; otherwise the normal
    // one-shot that streams the answer into the chat.
    final isTitleApply = label == 'Título' && widget.onApplyTitle != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          _s.streaming
              ? null
              : isTitleApply
              ? _suggestTitle
              : () => _send(prompt, quickAction: !withHistory),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: _s.streaming ? yCream2 : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: widget.accent),
            const SizedBox(width: 7),
            Text(
              label.toUpperCase(),
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 0.8,
                color: yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              enabled: !_s.streaming,
              style: yBody(size: 15, color: yInk),
              onSubmitted: _s.streaming ? null : _send,
              textInputAction: TextInputAction.send,
              decoration: _fieldDeco('Escribe a YuLi…'),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _s.streaming ? null : () => _send(_input.text),
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _s.streaming ? yMuted : widget.accent,
                border: Border.all(color: yBorderStrong, width: yLineMid),
                boxShadow:
                    _s.streaming
                        ? null
                        : const [
                          BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
                        ],
              ),
              child:
                  _s.streaming
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: yCream,
                        ),
                      )
                      : const Icon(YuLiIcons.arrowUp, color: yCream, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  void _editContext() {
    _anchorInput.text = _s.anchor ?? '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final insets = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: insets),
          child: Container(
            decoration: const BoxDecoration(
              color: yCream,
              border: Border(
                top: BorderSide(color: yBorderStrong, width: yLineMid),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'CONTEXTO',
                    style: yMono(
                      size: 11,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: TextField(
                      controller: _anchorInput,
                      maxLines: null,
                      style: yBody(size: 14, color: yInk),
                      decoration: _fieldDeco('Contexto de la conversación'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _primaryButton('GUARDAR', () {
                          _s.setAnchor(_anchorInput.text);
                          Navigator.pop(sheetCtx);
                        }),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _s.setAnchor('');
                          Navigator.pop(sheetCtx);
                        },
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: yCream,
                            border: Border.all(
                              color: yBorderStrong,
                              width: yLineMid,
                            ),
                          ),
                          child: Text(
                            'LIMPIAR',
                            style: yMono(
                              size: 11,
                              weight: FontWeight.w700,
                              tracking: 1.2,
                              color: yInk,
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
        );
      },
    );
  }

  InputDecoration _fieldDeco(String hint) => InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.all(10),
    hintText: hint,
    hintStyle: yBody(size: 14, color: yMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
    ),
  );

  Widget _primaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.accent,
          border: Border.all(color: yBorderStrong, width: yLineMid),
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

class _AiCubeMark extends StatelessWidget {
  final Color accent;
  final double yaw;
  final double pitch;
  final double roll;

  const _AiCubeMark({
    required this.accent,
    required this.yaw,
    required this.pitch,
    required this.roll,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: CustomPaint(
        painter: _AiCubePainter(
          accent: accent,
          yaw: yaw,
          pitch: pitch,
          roll: roll,
        ),
      ),
    );
  }
}

class _AiCubePainter extends CustomPainter {
  final Color accent;
  final double yaw;
  final double pitch;
  final double roll;

  const _AiCubePainter({
    required this.accent,
    required this.yaw,
    required this.pitch,
    required this.roll,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const r = 10.5;
    const camera = 48.0;
    final verts = <_CubePoint>[
      for (final x in [-r, r])
        for (final y in [-r, r])
          for (final z in [-r, r]) _rotate(x, y, z),
    ];
    final points =
        verts
            .map(
              (p) => Offset(
                size.width / 2 + p.x * camera / (camera - p.z),
                size.height / 2 + p.y * camera / (camera - p.z),
              ),
            )
            .toList();
    final faces =
        <_CubeFace>[
            _CubeFace([0, 1, 3, 2], _shade(0.88)),
            _CubeFace([4, 6, 7, 5], _shade(1.04)),
            _CubeFace([0, 4, 5, 1], _shade(0.72)),
            _CubeFace([2, 3, 7, 6], _shade(1.12)),
            _CubeFace([0, 2, 6, 4], _shade(0.8)),
            _CubeFace([1, 5, 7, 3], _shade(0.96)),
          ].where((face) => face.visibleFromCamera(verts)).toList()
          ..sort((a, b) => a.depth(verts).compareTo(b.depth(verts)));

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.1
          ..strokeJoin = StrokeJoin.bevel
          ..color = yInk;

    for (final face in faces) {
      final path =
          Path()..moveTo(
            points[face.indexes.first].dx,
            points[face.indexes.first].dy,
          );
      for (final i in face.indexes.skip(1)) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      fill.color = face.color;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  _CubePoint _rotate(double x, double y, double z) {
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final cx = math.cos(pitch);
    final sx = math.sin(pitch);
    final cz = math.cos(roll);
    final sz = math.sin(roll);

    final x1 = x * cy + z * sy;
    final z1 = -x * sy + z * cy;
    final y2 = y * cx - z1 * sx;
    final z2 = y * sx + z1 * cx;
    final x3 = x1 * cz - y2 * sz;
    final y3 = x1 * sz + y2 * cz;
    return _CubePoint(x3, y3, z2);
  }

  Color _shade(double amount) {
    final argb = accent.toARGB32();
    final a = (argb >> 24) & 0xFF;
    final r = (((argb >> 16) & 0xFF) * amount).clamp(0, 255).round();
    final g = (((argb >> 8) & 0xFF) * amount).clamp(0, 255).round();
    final b = ((argb & 0xFF) * amount).clamp(0, 255).round();
    return Color.fromARGB(a, r, g, b);
  }

  @override
  bool shouldRepaint(covariant _AiCubePainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.roll != roll;
  }
}

class _CubePoint {
  final double x;
  final double y;
  final double z;

  const _CubePoint(this.x, this.y, this.z);
}

class _CubeFace {
  final List<int> indexes;
  final Color color;

  const _CubeFace(this.indexes, this.color);

  double depth(List<_CubePoint> verts) {
    return indexes.fold<double>(0, (sum, i) => sum + verts[i].z) /
        indexes.length;
  }

  bool visibleFromCamera(List<_CubePoint> verts) {
    final a = verts[indexes[0]];
    final b = verts[indexes[1]];
    final c = verts[indexes[2]];
    final ux = b.x - a.x;
    final uy = b.y - a.y;
    final vx = c.x - a.x;
    final vy = c.y - a.y;
    return ux * vy - uy * vx > 0;
  }
}

/// Review checklist for "Extraer tareas": pick/edit which lines become FIGHT
/// tasks, then create them linked to the host note.
class _TaskReviewSheet extends ConsumerStatefulWidget {
  final List<String> candidates;
  final int noteId;
  final int? folderId;
  final Color accent;

  const _TaskReviewSheet({
    required this.candidates,
    required this.noteId,
    required this.folderId,
    required this.accent,
  });

  @override
  ConsumerState<_TaskReviewSheet> createState() => _TaskReviewSheetState();
}

class _TaskReviewSheetState extends ConsumerState<_TaskReviewSheet> {
  late final List<TextEditingController> _ctrls;
  late final List<bool> _sel;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _ctrls =
        widget.candidates.map((c) => TextEditingController(text: c)).toList();
    _sel = List<bool>.filled(widget.candidates.length, true);
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  int get _count {
    var n = 0;
    for (var i = 0; i < _sel.length; i++) {
      if (_sel[i] && _ctrls[i].text.trim().isNotEmpty) n++;
    }
    return n;
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final taskRepo = ref.read(taskRepositoryProvider);
    final noteRepo = ref.read(noteRepositoryProvider);
    final now = DateTime.now();
    var created = 0;
    for (var i = 0; i < _ctrls.length; i++) {
      if (!_sel[i]) continue;
      final content = _ctrls[i].text.trim();
      if (content.isEmpty) continue;
      try {
        final task = await taskRepo.save(
          Task(
            id: 0,
            content: content,
            status: TaskStatus.pending,
            folderId: widget.folderId,
            createdAt: now,
            expiresAt: DateTime(now.year, now.month, now.day, 23, 59, 59),
          ),
        );
        await noteRepo.linkTask(widget.noteId, task.id);
        created++;
      } catch (_) {}
    }
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          created == 1
              ? '1 tarea creada en FIGHT'
              : '$created tareas creadas en FIGHT',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: yCream,
          border: Border(
            top: BorderSide(color: yBorderStrong, width: yLineMid),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'REVISAR TAREAS',
                    style: yMono(
                      size: 11,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '→ @FIGHT',
                    style: yMono(size: 9, tracking: 1, color: yMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Marca/edita las que quieras crear.',
                style: yBody(size: 12, color: yMuted),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _ctrls.length,
                    itemBuilder:
                        (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _sel[i] = !_sel[i]),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _sel[i] ? widget.accent : yCream,
                                    border: Border.all(
                                      color: yBorderStrong,
                                      width: yLineMid,
                                    ),
                                  ),
                                  child:
                                      _sel[i]
                                          ? const Icon(
                                            YuLiIcons.check,
                                            size: 14,
                                            color: yCream,
                                          )
                                          : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _ctrls[i],
                                  maxLines: null,
                                  style: yBody(size: 14, color: yInk),
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    border: const UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: yBorderStrong,
                                        width: yLineThin,
                                      ),
                                    ),
                                    enabledBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: yBorderStrong,
                                        width: yLineThin,
                                      ),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: widget.accent,
                                        width: yLineMid,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _count == 0 || _creating ? null : _create,
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _count == 0 ? yMuted : widget.accent,
                          border: Border.all(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
                        ),
                        child:
                            _creating
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: yCream,
                                  ),
                                )
                                : Text(
                                  'CREAR $_count',
                                  style: yMono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    tracking: 1.2,
                                    color: yCream,
                                  ),
                                ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: yCream,
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                      child: Text(
                        'CANCELAR',
                        style: yMono(
                          size: 11,
                          weight: FontWeight.w700,
                          tracking: 1.2,
                          color: yInk,
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
    );
  }
}

/// Manages a canvas's context sources (linked notes + external urls). Notes
/// re-sync from local; urls are fetched once via Jina and refreshed only here,
/// per-source.
class _SourcesSheet extends ConsumerStatefulWidget {
  final int canvasNoteId;
  final int folderId;
  final Color accent;
  final Future<void> Function() onChanged;
  const _SourcesSheet({
    required this.canvasNoteId,
    required this.folderId,
    required this.accent,
    required this.onChanged,
  });

  @override
  ConsumerState<_SourcesSheet> createState() => _SourcesSheetState();
}

class _SourcesSheetState extends ConsumerState<_SourcesSheet> {
  bool _busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 3)),
    );
  }

  String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'recién';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  Future<void> _addNote() async {
    final notes =
        ref.read(notesByFolderProvider(widget.folderId)).valueOrNull ??
        const [];
    final existing =
        (ref
                    .read(canvasContextSourcesProvider(widget.canvasNoteId))
                    .valueOrNull ??
                const [])
            .where((s) => s.isNote)
            .map((s) => s.ref)
            .toSet();
    final candidates =
        notes
            .where(
              (n) =>
                  n.id != widget.canvasNoteId &&
                  n.kind == NoteKind.block &&
                  !existing.contains(n.id.toString()),
            )
            .toList();
    if (candidates.isEmpty) {
      _snack('No hay más notas en esta carpeta para agregar.');
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: const BoxDecoration(
              color: yCream,
              border: Border(
                top: BorderSide(color: yBorderStrong, width: yLineMid),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'AGREGAR NOTA',
                    style: yMono(
                      size: 11,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      itemBuilder: (_, i) {
                        final n = candidates[i];
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.of(ctx).pop(n.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: yBorderStrong,
                                  width: yLineThin,
                                ),
                              ),
                            ),
                            child: Text(
                              (n.title?.isEmpty ?? true)
                                  ? 'Sin título'
                                  : n.title!,
                              style: ySans(
                                size: 14,
                                weight: FontWeight.w700,
                                color: yInk,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (picked == null) return;
    final title = candidates.firstWhere((n) => n.id == picked).title;
    await ref
        .read(noteRepositoryProvider)
        .addContextSource(
          widget.canvasNoteId,
          CanvasSourceKind.note,
          picked.toString(),
          label: title,
        );
    await widget.onChanged();
  }

  Future<void> _addUrl() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: yCream,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            title: Text(
              'Agregar enlace',
              style: ySans(size: 18, weight: FontWeight.w700),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://…'),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                child: const Text('Agregar'),
              ),
            ],
          ),
    );
    if (url == null || url.trim().isEmpty) return;
    final clean = url.trim();
    setState(() => _busy = true);
    try {
      final doc = await ref.read(webReaderProvider).fetch(clean);
      await writeUrlContent(clean, doc.content);
      await ref
          .read(noteRepositoryProvider)
          .addContextSource(
            widget.canvasNoteId,
            CanvasSourceKind.url,
            clean,
            label: doc.title,
            fetchedAt: DateTime.now(),
          );
      await widget.onChanged();
    } on WebReaderException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo leer la página.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refetch(CanvasContextSource s) async {
    setState(() => _busy = true);
    try {
      final doc = await ref.read(webReaderProvider).fetch(s.ref);
      await writeUrlContent(s.ref, doc.content);
      await ref
          .read(noteRepositoryProvider)
          .updateContextSourceFetch(
            s.id,
            label: doc.title,
            fetchedAt: DateTime.now(),
          );
      await widget.onChanged();
    } on WebReaderException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo actualizar la página.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(CanvasContextSource s) async {
    await ref.read(noteRepositoryProvider).removeContextSource(s.id);
    // Drop its cached compaction / fetched content so SharedPreferences
    // doesn't keep orphaned entries.
    if (s.isUrl) {
      await clearCompactCache('url:${contextStableHash(s.ref)}');
      await clearUrlContent(s.ref);
    } else {
      await clearCompactCache('note:${s.ref}');
    }
    await widget.onChanged();
  }

  Future<void> _toggle(CanvasContextSource s) async {
    await ref
        .read(noteRepositoryProvider)
        .setContextSourceEnabled(s.id, !s.enabled);
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final sources =
        ref
            .watch(canvasContextSourcesProvider(widget.canvasNoteId))
            .valueOrNull ??
        const [];
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'FUENTES DE CONTEXTO',
                  style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk,
                  ),
                ),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'El chat usa estas fuentes como contexto. Las notas se '
              'sincronizan al abrir; los enlaces se leen una vez y se '
              'actualizan solo con su ↻.',
              style: yBody(size: 12, color: yMuted),
            ),
            const SizedBox(height: 12),
            if (sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Sin fuentes. Agrega una nota o un enlace.',
                  style: yBody(size: 13, color: yMuted),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final s in sources) _sourceRow(s)],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _addBtn(YuLiIcons.fileText, 'Nota', _addNote),
                ),
                const SizedBox(width: 8),
                Expanded(child: _addBtn(YuLiIcons.link, 'Enlace', _addUrl)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _viewSource(CanvasContextSource s) async {
    String raw;
    String label;
    String compactKey;
    if (s.isNote) {
      final nid = s.noteId;
      if (nid == null) return;
      final note = await ref.read(noteRepositoryProvider).getById(nid);
      if (note == null) return;
      final blocks = await ref.read(noteBlocksProvider(nid).future);
      label =
          (note.title?.trim().isEmpty ?? true) ? 'Nota' : note.title!.trim();
      raw = _srcExtractContext(blocks);
      compactKey = 'note:$nid';
    } else {
      label = (s.label?.trim().isEmpty ?? true) ? s.ref : s.label!.trim();
      raw = (await readUrlContent(s.ref)) ?? '';
      compactKey = 'url:${contextStableHash(s.ref)}';
    }
    if (raw.trim().isEmpty) return;
    if (!mounted) return;

    String? compacted;
    if (raw.length > kAnchorLongChars) {
      compacted = await readCompactCache(compactKey, raw);
    }
    final display = compacted ?? raw;
    final wasCompacted = compacted != null && compacted.length < raw.length;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (_) => _SourceViewDialog(
            label: label,
            isUrl: s.isUrl,
            content: display,
            wasCompacted: wasCompacted,
            originalLen: wasCompacted ? raw.length : null,
            compactedLen: wasCompacted ? compacted!.length : null,
            url: s.isUrl ? s.ref : null,
            accent: widget.accent,
          ),
    );
  }

  static String _srcExtractContext(List<NoteBlock> blocks) {
    final buf = StringBuffer();
    for (final b in blocks) {
      if (b is TextBlock) {
        if (b.markdown.trim().isNotEmpty) buf.writeln('${b.markdown}\n');
      } else if (b is BulletsBlock) {
        for (final it in b.items) {
          if (it.trim().isNotEmpty) buf.writeln('- $it');
        }
        buf.writeln();
      } else if (b is MathBlock) {
        if (b.latex.trim().isNotEmpty) buf.writeln('\$\$${b.latex}\$\$\n');
      }
    }
    return buf.toString().trim();
  }

  Widget _sourceRow(CanvasContextSource s) {
    final String title;
    if (s.isNote) {
      final n = ref.watch(noteByIdProvider(s.noteId ?? -1)).valueOrNull;
      title =
          (n?.title?.trim().isEmpty ?? true) ? 'Sin título' : n!.title!.trim();
    } else {
      title = (s.label?.trim().isEmpty ?? true) ? s.ref : s.label!.trim();
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : () => _viewSource(s),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: yBorderStrong, width: yLineThin),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : () => _toggle(s),
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  s.enabled ? YuLiIcons.squareCheck : YuLiIcons.square,
                  size: 18,
                  color: s.enabled ? widget.accent : yMuted,
                ),
              ),
            ),
            Icon(
              s.isNote ? YuLiIcons.fileText : YuLiIcons.link,
              size: 16,
              color: s.enabled ? widget.accent : yMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ySans(
                      size: 14,
                      weight: FontWeight.w700,
                      color: s.enabled ? yInk : yMuted,
                    ),
                  ),
                  if (s.isUrl)
                    Text(
                      '${s.ref}  ·  ${_ago(s.fetchedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: yMono(size: 9, tracking: 0.3, color: yMuted),
                    ),
                ],
              ),
            ),
            if (s.isUrl) ...[
              const SizedBox(width: 4),
              _iconBtn(
                YuLiIcons.refresh,
                'Actualizar',
                _busy ? null : () => _refetch(s),
              ),
            ],
            const SizedBox(width: 4),
            _iconBtn(YuLiIcons.close, 'Quitar', _busy ? null : () => _remove(s)),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
    message: tip,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: onTap == null ? yMuted : yInk),
      ),
    ),
  );

  Widget _addBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: widget.accent, width: yLineMid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: yInk),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: yMono(
                  size: 12,
                  weight: FontWeight.w700,
                  tracking: 1.2,
                  color: yInk,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Pick one of the AI-suggested titles (tap to select → fills the field) and
/// optionally edit it before applying. Returns the final string, or null.
class _TitlePickerDialog extends StatefulWidget {
  final List<String> options;
  final Color accent;
  const _TitlePickerDialog({required this.options, required this.accent});

  @override
  State<_TitlePickerDialog> createState() => _TitlePickerDialogState();
}

class _TitlePickerDialogState extends State<_TitlePickerDialog> {
  late final TextEditingController _ctrl;
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.options.first);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pick(int i) => setState(() {
    _sel = i;
    _ctrl.text = widget.options[i];
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SUGERIR TÍTULO',
              style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yInk,
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < widget.options.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pick(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _sel == i ? widget.accent : yCream,
                          border: Border.all(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.options[i],
                          style: ySans(
                            size: 15,
                            weight: FontWeight.w600,
                            color: yInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Container(height: 2, color: yInk.withValues(alpha: 0.14)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              style: yBody(size: 15, color: yInk),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
                hintText: 'Editar título…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: yCream,
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                      child: Text(
                        'CANCELAR',
                        style: yMono(
                          size: 12,
                          weight: FontWeight.w700,
                          tracking: 1.2,
                          color: yInk,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(_ctrl.text.trim()),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                      child: Text(
                        'APLICAR',
                        style: yMono(
                          size: 12,
                          weight: FontWeight.w700,
                          tracking: 1.2,
                          color: yCream,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceViewDialog extends StatelessWidget {
  final String label;
  final bool isUrl;
  final String content;
  final bool wasCompacted;
  final int? originalLen;
  final int? compactedLen;
  final String? url;
  final Color accent;

  const _SourceViewDialog({
    required this.label,
    required this.isUrl,
    required this.content,
    required this.wasCompacted,
    this.originalLen,
    this.compactedLen,
    this.url,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    return Dialog(
      backgroundColor: yCream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: yBorderStrong, width: yLineMid),
      ),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenW * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: const BoxDecoration(
                color: yCream2,
                border: Border(
                  bottom: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CONTEXTO DE FUENTE',
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.2,
                      color: yMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ySans(
                      size: 16,
                      weight: FontWeight.w700,
                      color: yInk,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isUrl) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: yAmber.withValues(alpha: 0.12),
                          border: Border.all(color: yAmber, width: yLineThin),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                YuLiIcons.info,
                                size: 14,
                                color: yAmber,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Contenido optimizado para la IA. Si es '
                                'muy largo, la IA puede comprimirlo para '
                                'ahorrar tokens.',
                                style: yMono(
                                  size: 10,
                                  tracking: 0.4,
                                  color: yInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (wasCompacted) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Compresión aplicada: $originalLen → $compactedLen caracteres',
                          style: yMono(size: 9, tracking: 0.4, color: yMuted),
                        ),
                      ),
                      Container(
                        height: yLineThin,
                        color: yInk.withValues(alpha: 0.14),
                      ),
                      const SizedBox(height: 12),
                    ],
                    NoteMarkdownPreview(data: fixMarkdownTables(content), accent: accent),
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: yBorderStrong, width: yLineThin),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (url != null) ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: url!));
                        HapticFeedback.selectionClick();
                      },
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: yCream,
                          border: Border.all(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
                        ),
                        child: Text(
                          'COPIAR ENLACE',
                          style: yMono(
                            size: 10,
                            weight: FontWeight.w700,
                            tracking: 1.2,
                            color: yInk,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: yInk,
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                      child: Text(
                        'CERRAR',
                        style: yMono(
                          size: 10,
                          weight: FontWeight.w700,
                          tracking: 1.2,
                          color: yCream,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
