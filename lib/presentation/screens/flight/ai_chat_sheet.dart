import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/ai_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/note_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../../domain/services/ai_assistant.dart';
import '../../../domain/models/note.dart' show NoteKind;
import '../../../domain/models/note_block.dart';
import '../../../domain/models/task.dart';
import '../../../domain/models/canvas_context_source.dart';
import '../../../data/services/context_cache.dart';
import '../../../data/services/ai_chat_image_storage.dart';
import '../../../data/services/web_reader.dart' show WebReaderException;
import 'ai_chat_session.dart';
import 'ai_chat_settings_dialog.dart';
import 'ai_chat_visuals.dart';
import 'ai_modes.dart';
import 'mode_builder_screen.dart';
import 'context_assembler.dart' as ctx;
// Reuse the notes' markdown renderer (markdown_widget + flutter_math_fork) so
// the assistant's markdown/LaTeX renders exactly like a note.
import 'note_block_widgets.dart' show NoteMarkdownPreview, fixMarkdownTables;
import '../yuli_ai/ai_knowledge_contracts.dart';
import '../yuli_ai/ai_widget_contracts.dart';
import '../yuli_ai/ai_widget_renderer.dart';
import '../yuli_ai/yuli_ai_tools.dart'
    show yuliToolDefs, flightToolSystem, runYuliTool, ConsultingIndicator;

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
  List<AiImageInput> pendingImages = const [],
  AiChatDockController? dockController,
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
  if (!context.mounted) {
    await Future.wait(pendingImages.map(deleteAiChatImage));
    return;
  }
  if (!hasKey) {
    unawaited(Future.wait(pendingImages.map(deleteAiChatImage)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configura tu API key de YuLi AI en Ajustes'),
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
      if (!context.mounted) {
        await Future.wait(pendingImages.map(deleteAiChatImage));
        return;
      }
      if (choice == _CtxAction.add) {
        session.appendAnchor(ctx);
      } else if (choice == _CtxAction.replace) {
        session.setAnchor(ctx);
      }
      // cancel → keep current anchor, still open the chat.
    }
  }

  if (!context.mounted) {
    await Future.wait(pendingImages.map(deleteAiChatImage));
    return;
  }
  // A note editor mounts a docked panel (AiChatDockScope) → open it in place
  // (note + YuLi side by side). Other contexts (no dock) fall back to the modal.
  final dock = dockController ?? AiChatDockScope.maybeOf(context);
  if (dock != null) {
    if (pendingImages.isNotEmpty) dock.attachImages(pendingImages);
    dock.open();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => _AiChatSheet(
          session: session,
          accent: accent,
          prefillMessage: prefillMessage,
          initialImages: pendingImages,
          onSendToCanvas: onSendToCanvas,
          onApplyTitle: onApplyTitle,
        ),
  );
}

enum _CtxAction { add, replace }

class _FlightAiContext {
  final String prompt;
  final String? folderScope;

  const _FlightAiContext({required this.prompt, required this.folderScope});
}

String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

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

/// Open/closed state of a docked chat panel. A `ChangeNotifier` (not a setState)
/// so toggling it NEVER rebuilds the host editor — only the [AiChatDock] listens
/// (same decoupling as the floating pins / palettes).
class AiChatDockController extends ChangeNotifier {
  bool _open = false;
  final List<AiImageInput> _pendingImages = [];
  bool get isOpen => _open;
  List<AiImageInput> get pendingImages => List.unmodifiable(_pendingImages);

  void attachImages(Iterable<AiImageInput> images) {
    final available = kMaxAiImagesPerMessage - _pendingImages.length;
    if (available <= 0) {
      for (final image in images) {
        unawaited(deleteAiChatImage(image));
      }
      return;
    }
    final incoming = images.toList();
    _pendingImages.addAll(incoming.take(available));
    for (final image in incoming.skip(available)) {
      unawaited(deleteAiChatImage(image));
    }
    notifyListeners();
  }

  List<AiImageInput> takeImages() {
    final images = List<AiImageInput>.from(_pendingImages);
    if (images.isEmpty) return const [];
    _pendingImages.clear();
    notifyListeners();
    return images;
  }

  void removeImage(AiImageInput image) {
    if (!_pendingImages.remove(image)) return;
    notifyListeners();
    unawaited(deleteAiChatImage(image));
  }

  void open() {
    if (_open) return;
    _open = true;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  void toggle() => _open ? close() : open();

  @override
  void dispose() {
    final images = List<AiImageInput>.from(_pendingImages);
    _pendingImages.clear();
    unawaited(Future.wait(images.map(deleteAiChatImage)));
    super.dispose();
  }
}

/// Provides the [AiChatDockController] to descendants so [showAiChat] can find
/// and open the mounted panel instead of a modal sheet.
class AiChatDockScope extends InheritedWidget {
  final AiChatDockController controller;

  const AiChatDockScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static AiChatDockController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AiChatDockScope>()?.controller;

  @override
  bool updateShouldNotify(AiChatDockScope old) => controller != old.controller;
}

/// Edge-docked chat panel for the note editors: a handle on the right edge that
/// slides the chat in/out. Mounted as a SIBLING of the canvas Listener (so a
/// tap on it never leaks a stroke) and wrapped in a RepaintBoundary; the open
/// state is a [ChangeNotifier], so opening/closing or streaming NEVER repaints
/// the canvas. Its transparent area passes pointers through to the canvas, so
/// the note stays interactive next to the chat.
class AiChatDock extends StatefulWidget {
  final AiChatDockController controller;
  final AiChatSession session;
  final Color accent;
  final void Function(String markdown)? onSendToCanvas;

  /// AI context is linked/synced → the handle hard-blinks (the indicator that
  /// used to live on the header AI button now rides the tab).
  final bool linked;

  const AiChatDock({
    super.key,
    required this.controller,
    required this.session,
    required this.accent,
    this.onSendToCanvas,
    this.linked = false,
  });

  @override
  State<AiChatDock> createState() => _AiChatDockState();
}

class _AiChatDockState extends State<AiChatDock>
    with SingleTickerProviderStateMixin {
  static const double _w = 450;
  static const double _handleW = 30;
  static const double _handleH = 56;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.controller.isOpen ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onToggle);
  }

  void _onToggle() =>
      widget.controller.isOpen ? _anim.forward() : _anim.reverse();

  @override
  void dispose() {
    widget.controller.removeListener(_onToggle);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_anim.value);
          final h = MediaQuery.of(context).size.height;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The panel, sliding from the right edge (off-screen at t=0).
              Positioned(
                top: 0,
                bottom: 0,
                width: _w,
                right: _w * (t - 1),
                child:
                    t < 0.02
                        ? const SizedBox.shrink()
                        : _AiChatSheet(
                          session: widget.session,
                          accent: widget.accent,
                          dockController: widget.controller,
                          onSendToCanvas: widget.onSendToCanvas,
                          embedded: true,
                          onClose: widget.controller.close,
                        ),
              ),
              // The handle rides the panel's left edge: at the screen edge when
              // closed, at the panel edge when open. Carries the active mode's
              // icon (rebuilds only this tiny widget on mode change / streaming).
              Positioned(
                top: h * 0.30,
                right: (_w - 8) * t,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.controller.toggle,
                  child: Container(
                    width: _handleW,
                    height: _handleH,
                    decoration: BoxDecoration(
                      color: widget.accent,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.accent.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(-4, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: widget.session,
                          builder:
                              (_, _) => Icon(
                                widget.session.mode.icon,
                                size: 15,
                                color: yCream,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Icon(
                          t > 0.5
                              ? YuLiIcons.chevronRight
                              : YuLiIcons.chevronLeft,
                          size: 13,
                          color: yCream,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AiChatSheet extends ConsumerStatefulWidget {
  final AiChatSession session;
  final Color accent;
  final String? prefillMessage;
  final List<AiImageInput> initialImages;
  final AiChatDockController? dockController;
  final void Function(String markdown)? onSendToCanvas;
  final void Function(String title)? onApplyTitle;

  /// Docked-panel mode: fills the dock (no modal frame); the close button and
  /// "Enviar a lienzo" call [onClose] instead of Navigator.pop.
  final bool embedded;
  final VoidCallback? onClose;

  const _AiChatSheet({
    required this.session,
    required this.accent,
    this.prefillMessage,
    this.initialImages = const [],
    this.dockController,
    this.onSendToCanvas,
    this.onApplyTitle,
    this.embedded = false,
    this.onClose,
  });

  @override
  ConsumerState<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<_AiChatSheet> {
  final _input = TextEditingController();
  final _anchorInput = TextEditingController();
  final _scroll = ScrollController();
  int? _remaining;
  List<AiImageInput> _pendingImages = [];
  bool _pickingImage = false;
  bool _stickToBottom = true;

  AiChatSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _pendingImages = List<AiImageInput>.from(
      widget.dockController?.pendingImages ?? widget.initialImages,
    );
    widget.dockController?.addListener(_onDockDraft);
    _s.addListener(_onSession);
    _scroll.addListener(_onScroll);
    _loadRemaining();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScroll());
    final prefill = widget.prefillMessage?.trim();
    if (prefill != null && prefill.isNotEmpty) _input.text = prefill;
    // If this canvas is linked to a source note, resync the context on open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resyncFromSources());
  }

  // ─── Canvas context sources (notes + urls) — assembly & sync ──────────────

  DateTime? _syncedAt;

  /// Whether the context bar is expanded. Collapsed by default so the chat gets
  /// the vertical space; the header context button toggles it.
  bool _showContext = false;

  /// Rebuild the anchor from ALL context sources. For **block notes** the
  /// note's own content is the primary source (implicit, no DB row) followed by
  /// any additional sources (other notes + urls). For **canvases**, reads all DB
  /// sources (notes + urls), no implicit self-source.
  Future<void> _resyncFromSources() async {
    final repo = ref.read(noteRepositoryProvider);
    final note = await repo.getById(_s.noteId);
    if (note == null) return;
    final isBlock = note.kind == NoteKind.block;

    final primaryPieces = <String>[];
    final relatedPieces = <String>[];

    // Block note: own content is always the first (implicit) source.
    if (isBlock && _s.settings.useNoteContext) {
      final blocks = await ref.read(noteBlocksProvider(_s.noteId).future);
      final label =
          (note.title?.trim().isEmpty ?? true) ? 'Nota' : note.title!.trim();
      final raw = _extractNoteContext(blocks);
      if (raw.trim().isNotEmpty) {
        final piece = await _compactPiece('note:${note.id}', raw);
        primaryPieces.add('## $label\n\n$piece');
      }
    }

    // Additional sources from DB: URLs for block notes; notes + URLs for canvases.
    final sources =
        _s.settings.useRelatedSources
            ? await repo.getContextSources(_s.noteId)
            : const <CanvasContextSource>[];
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
      relatedPieces.add('## $label\n\n$piece');
    }

    if (primaryPieces.isEmpty && relatedPieces.isEmpty) return;

    _s.setSyncedContexts(
      primary:
          _s.settings.useNoteContext
              ? primaryPieces.join('\n\n---\n\n')
              : (_s.anchor ?? ''),
      related:
          _s.settings.useRelatedSources
              ? relatedPieces.join('\n\n---\n\n')
              : (_s.relatedAnchor ?? ''),
    );
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
            onEditAnchor:
                note.kind == NoteKind.block
                    ? null
                    : () {
                      Navigator.of(context).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _editContext();
                      });
                    },
          ),
    );
  }

  @override
  void dispose() {
    widget.dockController?.removeListener(_onDockDraft);
    if (widget.dockController == null) {
      unawaited(Future.wait(_pendingImages.map(deleteAiChatImage)));
    }
    _s.removeListener(_onSession);
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _anchorInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSession() {
    if (_stickToBottom) _scrollToBottom();
    if (!_s.streaming) _loadRemaining();
  }

  void _onDockDraft() {
    final images = widget.dockController?.pendingImages ?? const [];
    if (!mounted || listEquals(images, _pendingImages)) return;
    setState(() => _pendingImages = List<AiImageInput>.from(images));
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.maxScrollExtent - _scroll.offset <= 48;
    _stickToBottom = atBottom;
    _s.saveChatScroll(_scroll.offset, atBottom: atBottom);
  }

  void _restoreScroll() {
    if (!_scroll.hasClients) return;
    if (_s.chatScrollAtBottom || !_s.hasChatScrollOffset) {
      _stickToBottom = true;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      return;
    }
    _stickToBottom = false;
    _scroll.jumpTo(
      _s.chatScrollOffset.clamp(0, _scroll.position.maxScrollExtent),
    );
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
    unawaited(_sendAsync(text, quickAction: quickAction));
  }

  Future<void> _sendAsync(String text, {bool quickAction = false}) async {
    // Anchor is OPTIONAL in v2 (modes work as pure dialogue), so DON'T gate on
    // hasAnchor — that silently blocked sending on a canvas with no linked
    // sources (pizarra/cuaderno), where the button looked dead.
    if (text.trim().isEmpty || _s.streaming) return;
    final settings = _s.settings;
    final images = quickAction ? const <AiImageInput>[] : _pendingImages;
    if (images.isNotEmpty && settings.model == AiModel.pro) {
      _showProImageUnavailable();
      return;
    }
    if (!quickAction) {
      _stickToBottom = true;
      _input.clear();
      if (widget.dockController != null) {
        widget.dockController!.takeImages();
      } else {
        setState(() => _pendingImages = []);
      }
    }
    final retrievalQuery = _retrievalQuery(text);
    final flightContext =
        quickAction ||
                !(settings.useTools ||
                    settings.useActionDrafts ||
                    settings.useMemory)
            ? const _FlightAiContext(prompt: '', folderScope: null)
            : await _flightAiContext();
    final retrievedWidgets =
        quickAction
            ? const <AiWidgetSpec>[]
            : ref
                .read(aiWidgetRetrieverProvider)
                .retrieve(
                  text,
                  surface: AiWidgetSurface.flight,
                  context: retrievalQuery,
                  k: 8,
                );
    final widgetSpecs =
        retrievedWidgets
            .where((spec) {
              return switch (spec.policy) {
                AiWidgetPolicy.study => settings.useInteractiveReplies,
                AiWidgetPolicy.appData => settings.useTools,
                AiWidgetPolicy.appWrite => settings.useActionDrafts,
                AiWidgetPolicy.memory => settings.useMemory,
              };
            })
            .take(3)
            .toList();
    final widgetPrompt = aiWidgetPrompt(
      widgetSpecs,
      surface: AiWidgetSurface.flight,
    );
    final knowledgePrompt =
        quickAction || !settings.useRelatedSources
            ? ''
            : aiKnowledgePrompt(
              ref
                  .read(aiKnowledgeRetrieverProvider)
                  .retrieve(retrievalQuery, surface: AiKnowledgeSurface.flight),
              surface: AiKnowledgeSurface.flight,
            );
    final memoryPrompt =
        quickAction || !settings.useMemory
            ? ''
            : await ref
                .read(aiMemoryStoreProvider)
                .promptForTurn(
                  retrievalQuery,
                  noteScope: 'note:${_s.noteId}',
                  folderScope: flightContext.folderScope,
                );
    await _s.send(
      ref.read(aiAssistantProvider),
      ref.read(aiUsageLimiterProvider),
      text,
      quickAction: quickAction,
      // Same DB tools as YuLi AI, but the note chat only reaches for them when
      // the user EXPLICITLY asks (strict guidance). Off for one-shot actions.
      tools: quickAction || !settings.useTools ? const [] : yuliToolDefs,
      toolGuidance:
          quickAction || !settings.useTools ? null : flightToolSystem(),
      onToolCall:
          quickAction || !settings.useTools ? null : (c) => runYuliTool(ref, c),
      knowledgeDocs: [
        if (knowledgePrompt.isNotEmpty) knowledgePrompt,
        if (flightContext.prompt.isNotEmpty) flightContext.prompt,
      ],
      memoryDocs: memoryPrompt.isEmpty ? const [] : [memoryPrompt],
      widgetDocs: widgetPrompt.isEmpty ? const [] : [widgetPrompt],
      images: images,
    );
  }

  String _retrievalQuery(String text) {
    final recent = _s.messages.reversed
        .where((m) => m.role != AiRole.system)
        .take(4)
        .map((m) => m.text)
        .toList()
        .reversed
        .join('\n');
    final anchor =
        _s.settings.useNoteContext && _s.hasAnchor
            ? _s.anchor?.substring(0, math.min(900, _s.anchor!.length)) ?? ''
            : '';
    final related =
        _s.settings.useRelatedSources && _s.hasRelatedAnchor
            ? _s.relatedAnchor?.substring(
                  0,
                  math.min(600, _s.relatedAnchor!.length),
                ) ??
                ''
            : '';
    return '$anchor\n$related\n$recent\n$text';
  }

  Future<_FlightAiContext> _flightAiContext() async {
    final note = await ref.read(noteRepositoryProvider).getById(_s.noteId);
    if (note == null) {
      return const _FlightAiContext(prompt: '', folderScope: null);
    }
    final folder = await ref
        .read(folderRepositoryProvider)
        .getById(note.folderId);
    final folderScope = folder == null ? null : 'folder:${folder.id}';
    final folderLine =
        folder == null
            ? ''
            : '- Carpeta actual: id=${folder.id}, nombre="${folder.name}", color="${_hex(folder.color)}".\n';
    final prompt =
        'Contexto actual de Flight para este turno. Usalo como contexto de producto, '
        'no lo reveles como IDs internos salvo que sea necesario para widgets.\n'
        '- Nota actual: id=${note.id}, titulo="${note.displayTitle}", tipo=${note.kind.name}.\n'
        '$folderLine'
        'Si el usuario pide crear una tarea desde esta nota y no especifica otra carpeta, '
        'usa la carpeta actual en TASK_DRAFT con su id, nombre y color. '
        'Si propone memoria de esta materia/carpeta, prefiere scope "$folderScope"; '
        'si es especifica de la nota, usa scope "note:${note.id}". '
        'Si pide crear una tarea y mandarla/enlazarla a Lab, usa TASK_DRAFT con labLink; '
        'si solo pide tarea, no incluyas labLink; si solo pide card Lab, usa LAB_CARD_DRAFT.';
    return _FlightAiContext(prompt: prompt, folderScope: folderScope);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            8,
            8,
            8,
            MediaQuery.of(context).viewInsets.bottom + 8,
          ),
          child: AiFrostedSurface(
            accent: widget.accent,
            child: SafeArea(
              child: AnimatedBuilder(
                animation: _s,
                builder: (_, _) => _buildChat(),
              ),
            ),
          ),
        ),
      );
    }
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 8, insets + 8),
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: AiFrostedSurface(
          accent: widget.accent,
          child: SafeArea(
            top: false,
            child: AnimatedBuilder(
              animation: _s,
              builder: (_, _) => _buildChat(),
            ),
          ),
        ),
      ),
    );
  }

  /// Open a bottom sheet listing the other notes in the same folder so the
  /// user can pick one to import as the chat anchor.
  /// Extract a plain-text context from a note's blocks (same rules as the
  /// note editor: text + bullets + math; skip tasks & drawings).
  String _extractNoteContext(List<NoteBlock> blocks) =>
      ctx.extractNoteContext(blocks);

  Widget _buildChat() {
    return Column(
      children: [
        _header(),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child:
              _showContext
                  ? _contextBar()
                  : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            children: [
              if (_s.messages.isEmpty) _greeting(),
              for (int i = 0; i < _s.messages.length; i++)
                _bubble(_s.messages[i], i),
            ],
          ),
        ),
        _inputBar(),
      ],
    );
  }

  /// Branches: block notes get the implicit "NOTA COMO CONTEXTO" bar; canvases
  /// show the SINCRONIZADA / CONTEXTO bar as before.
  Widget _contextBar() {
    final hostKind = ref.watch(noteByIdProvider(_s.noteId)).valueOrNull?.kind;
    final sources =
        ref.watch(canvasContextSourcesProvider(_s.noteId)).valueOrNull ??
        const [];
    if (!_s.settings.useNoteContext) {
      if (_s.settings.useRelatedSources && sources.isNotEmpty) {
        return _linkedContextBar(sources.length);
      }
      return _disabledContextBar(hostKind ?? NoteKind.block);
    }
    if (hostKind == NoteKind.block) return _noteContextBar();
    if (sources.isNotEmpty) return _linkedContextBar(sources.length);
    return _normalContextBar();
  }

  Widget _disabledContextBar(NoteKind hostKind) {
    final label = switch (hostKind) {
      NoteKind.block => 'ESTA NOTA NO SE ENVIARÁ',
      NoteKind.whiteboard => 'ESTA PIZARRA NO SE ENVIARÁ',
      NoteKind.notebook => 'ESTE CUADERNO NO SE ENVIARÁ',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 5),
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: aiHairline),
      ),
      child: Row(
        children: [
          const Icon(YuLiIcons.fileText, size: 15, color: aiMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: yBody(size: 10.5, weight: FontWeight.w700, color: aiMuted),
            ),
          ),
          AiStatusPill(
            label: 'Cambiar',
            accent: widget.accent,
            onTap: _openChatMenu,
          ),
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
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 5),
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: aiHairline),
      ),
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
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 5),
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: aiHairline),
      ),
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
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: aiHairline),
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
          _ghostIcon(
            YuLiIcons.close,
            'Quitar contexto',
            () => _s.setAnchor(''),
          ),
        ],
      ),
    );
  }

  /// SINCRONIZADA ▸ N fuentes · hace Xmin   ↻(notas)   ⚙(gestionar)
  Widget _linkedContextBar(int count) {
    final ago = _syncedAt == null ? '' : ' · ${_agoLabel(_syncedAt!)}';
    final label = count == 1 ? '1 fuente' : '$count fuentes';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 5),
      padding: const EdgeInsets.fromLTRB(12, 7, 7, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: aiHairline),
      ),
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
          _ghostIcon(
            YuLiIcons.refresh,
            'Re-sincronizar notas',
            _resyncFromSources,
          ),
          const SizedBox(width: 6),
          _ghostIcon(
            YuLiIcons.slidersHorizontal,
            'Gestionar fuentes',
            _showSourcesSheet,
          ),
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
    return AiSoftIconButton(icon: icon, tooltip: tip, onTap: onTap, size: 32);
  }

  void _openModeCatalog() {
    showDialog<void>(context: context, builder: (_) => _modeCatalogContent());
  }

  Future<void> _openChatMenu() async {
    final before = _s.settings;
    final hostKind =
        ref.read(noteByIdProvider(_s.noteId)).valueOrNull?.kind ??
        NoteKind.block;
    final result = await showDialog<AiChatMenuResult>(
      context: context,
      builder:
          (_) => AiChatSettingsDialog(
            initial: before,
            accent: widget.accent,
            hostKind: hostKind,
            canSummarize:
                !_s.streaming &&
                _s.messages.any((m) => m.role != AiRole.system),
          ),
    );
    if (result == null || !mounted) return;
    _s.setSettings(result.settings);
    final contextChanged =
        before.useNoteContext != result.settings.useNoteContext ||
        before.useRelatedSources != result.settings.useRelatedSources;
    if (contextChanged) await _resyncFromSources();
    if (result.summarize && mounted) {
      _send('Resume nuestra conversación hasta ahora en 3-4 puntos clave.');
    }
  }

  String _settingsSummary() {
    final settings = _s.settings;
    final model = settings.model == AiModel.flash ? 'FLASH' : 'PRO';
    final length = switch (settings.responseLength) {
      AiResponseLength.brief => 'BREVE',
      AiResponseLength.normal => 'NORMAL',
      AiResponseLength.detailed => 'DETALLADA',
    };
    final history = switch (settings.historyDepth) {
      AiHistoryDepth.recent => 'RECIENTE',
      AiHistoryDepth.normal => 'HISTORIAL NORMAL',
      AiHistoryDepth.full => 'TODO EL CHAT',
    };
    return '$model · $length · $history';
  }

  /// Gallery of modes (cards) — pick one to switch. A floating centred dialog
  /// (not a full-height sheet): fixed header, the cards scroll, and the "CREAR
  /// MODO" button stays pinned at the bottom. Wrapped in a Consumer so adding/
  /// deleting a custom mode rebuilds it (it's a separate route — the host State's
  /// rebuild wouldn't reach it).
  Widget _modeCatalogContent() {
    return Consumer(
      builder: (context, ref, _) {
        final store = ref.watch(customModesStoreProvider);
        final modes = [...kAiModes, ...store.modes];
        final size = MediaQuery.of(context).size;
        final maxH = size.height * 0.84 < 680 ? size.height * 0.84 : 680.0;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 20,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 590, maxHeight: maxH),
            child: AiFrostedSurface(
              accent: widget.accent,
              role: AiFrostedSurfaceRole.dialog,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: widget.accent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            YuLiIcons.sparkles,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PERSONALIDAD',
                                style: ySans(
                                  size: 18,
                                  weight: FontWeight.w700,
                                  color: aiInk,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Elige cómo quieres que te responda YuLi.',
                                style: yBody(size: 11.5, color: aiMuted),
                              ),
                            ],
                          ),
                        ),
                        AiSoftIconButton(
                          icon: YuLiIcons.close,
                          tooltip: 'Cerrar',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final columns = c.maxWidth < 430 ? 1 : 2;
                          final cardW =
                              columns == 1 ? c.maxWidth : (c.maxWidth - 10) / 2;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final m in modes) _modeCard(m, cardW),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: aiHairline)),
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                    child: _createModeButton(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _createModeButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openModeBuilder,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: widget.accent,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: 0.24),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(YuLiIcons.plus, size: 17, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'CREAR PERSONALIDAD',
              style: yBody(
                size: 11.5,
                weight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the guided builder as a floating dialog (over a scrim, not a full
  /// screen). The catalog sheet closes first; on save we switch to the new mode.
  Future<void> _openModeBuilder() async {
    Navigator.of(context).pop(); // close the catalog sheet
    final created = await showDialog<AiMode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ModeBuilderDialog(accent: widget.accent),
    );
    if (created != null && mounted) _s.setMode(created);
  }

  /// Edits a custom mode: reuses the guided builder seeded with the current
  /// persona/icon (YuLi adapts it from plain feedback), re-runs the sanitizer on
  /// save, and keeps the same id. If the edited mode is the active one, refresh
  /// it in place so the new persona applies without losing the thread.
  Future<void> _editMode(AiMode m) async {
    Navigator.of(context).pop(); // close the catalog
    final updated = await showDialog<AiMode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ModeBuilderDialog(accent: widget.accent, editing: m),
    );
    if (updated != null && mounted && _s.mode.id == updated.id) {
      _s.refreshMode(updated);
    }
  }

  /// Deletes a custom mode (with confirm). If it's the active mode, falls back
  /// to the default so the session never points at a deleted mode.
  Future<void> _deleteMode(AiMode m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: yCream,
            shape: const RoundedRectangleBorder(),
            title: Text(
              'BORRAR PERSONALIDAD',
              style: yMono(size: 13, weight: FontWeight.w800, color: yInk),
            ),
            content: Text(
              '¿Borrar la personalidad "${m.name}"? No se puede deshacer.',
              style: yBody(size: 14, color: yInk),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('CANCELAR', style: yMono(size: 11, color: yMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'BORRAR',
                  style: yMono(size: 11, weight: FontWeight.w800, color: yInk),
                ),
              ),
            ],
          ),
    );
    if (ok != true) return;
    if (_s.mode.id == m.id) _s.setMode(defaultAiMode);
    await ref.read(customModesStoreProvider).remove(m.id);
  }

  Widget _modeCard(AiMode m, double width) {
    final selected = m.id == _s.mode.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        _s.setMode(m);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      },
      child: Container(
        width: width,
        height: 136,
        decoration: BoxDecoration(
          color:
              selected
                  ? widget.accent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                selected ? widget.accent.withValues(alpha: 0.48) : aiHairline,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(m.icon, size: 16, color: widget.accent),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: yBody(
                      size: 12,
                      weight: FontWeight.w800,
                      color: aiInk,
                    ),
                  ),
                ),
                if (selected)
                  Icon(YuLiIcons.check, size: 16, color: widget.accent),
                if (m.custom) ...[
                  const SizedBox(width: 8),
                  AiSoftIconButton(
                    icon: YuLiIcons.pen,
                    tooltip: 'Editar personalidad',
                    onTap: () => _editMode(m),
                    size: 28,
                  ),
                  const SizedBox(width: 4),
                  AiSoftIconButton(
                    icon: YuLiIcons.trash,
                    tooltip: 'Borrar personalidad',
                    onTap: () => _deleteMode(m),
                    size: 28,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              m.blurb,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: yBody(size: 12, color: aiInk),
            ),
            const SizedBox(height: 6),
            Text(
              m.sample,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: yBody(
                size: 11,
                color: aiMuted,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  /// Mode-aware empty-state hero shown when the thread is empty: the active mode
  /// presents itself + an invitation that depends on the mode and whether
  /// there's context.
  Widget _greeting() {
    final m = _s.mode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(m.icon, size: 20, color: widget.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: ySans(
                        size: 15,
                        weight: FontWeight.w700,
                        color: aiInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(m.blurb, style: yBody(size: 12, color: aiMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _greetingLine(m.id, _s.hasAnchor),
            style: yBody(
              size: 16,
              weight: FontWeight.w600,
              color: aiInk,
            ).copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }

  String _greetingLine(String modeId, bool hasCtx) {
    switch (modeId) {
      case 'tutor':
        return hasCtx
            ? 'Listo para guiarte sobre esto. ¿Por dónde empezamos?'
            : '¿Qué quieres aprender? Te guío — la respuesta la encuentras tú.';
      case 'socratic':
        return hasCtx
            ? 'Dame tu postura sobre esto y la ponemos a prueba.'
            : 'Tírame una afirmación y la ponemos a prueba.';
      case 'clarity':
        return hasCtx
            ? '¿Qué parte de esto quieres que te explique simple?'
            : '¿Qué quieres que te explique desde cero?';
      case 'examiner':
        return hasCtx
            ? 'Cuando digas, te empiezo a examinar sobre esto.'
            : 'Dime el tema y te empiezo a preguntar.';
      case 'expert':
        return hasCtx
            ? 'Contexto cargado. ¿Qué quieres profundizar?'
            : '¿Sobre qué vamos a fondo?';
      default:
        return hasCtx
            ? 'Tengo tu contexto cargado. ¿Qué hacemos con él?'
            : '¿En qué te ayudo?';
    }
  }

  static const _kDailyCap = 150;

  Widget _header() {
    final used =
        _remaining == null
            ? null
            : (_kDailyCap - _remaining!).clamp(0, _kDailyCap);
    final mode = _s.mode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.accent,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(YuLiIcons.box, size: 21, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YuLi AI',
                  maxLines: 1,
                  style: ySans(
                    size: 18,
                    weight: FontWeight.w700,
                    color: aiInk,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_settingsSummary()}${used == null ? '' : ' · $used/$_kDailyCap'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: yBody(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: aiMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openModeCatalog,
            child: Container(
              height: 34,
              constraints: const BoxConstraints(maxWidth: 106),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: widget.accent.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(mode.icon, size: 14, color: widget.accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      mode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: yBody(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: widget.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          AiSoftIconButton(
            icon: YuLiIcons.moreHorizontal,
            tooltip: 'Opciones del chat',
            onTap: _openChatMenu,
          ),
          const SizedBox(width: 4),
          AiSoftIconButton(
            icon: YuLiIcons.close,
            tooltip: 'Cerrar',
            onTap: _dismiss,
          ),
        ],
      ),
    );
  }

  Widget _aiAvatar() {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.accent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: widget.accent.withValues(alpha: 0.28),
            blurRadius: 12,
            spreadRadius: -5,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(YuLiIcons.sparkles, size: 17, color: Colors.white),
    );
  }

  Widget _aiMsgFrame(Widget content, {List<Widget>? actions}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiAvatar(),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'YuLi',
                        style: yBody(
                          size: 11,
                          weight: FontWeight.w700,
                          color: aiMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: widget.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.accent.withValues(alpha: 0.45),
                              blurRadius: 7,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 2, right: 6),
                      child: content,
                    ),
                    if (actions != null && actions.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(spacing: 6, runSpacing: 6, children: actions),
                    ],
                  ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.38),
              Colors.white.withValues(alpha: 0.18),
            ],
          ),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
        ),
        child: Text(
          label,
          style: yBody(size: 10, weight: FontWeight.w700, color: aiInk),
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
    _dismiss();
  }

  /// Close the chat: in the docked panel slide it shut; as a modal, pop.
  void _dismiss() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _bubble(AiChatMsg m, int i) {
    if (m.role == AiRole.system) return _systemNotice(m, i);
    if (m.role == AiRole.user) return _userBubble(m);

    // Assistant.
    final streaming = _s.streaming && i == _s.messages.length - 1;
    Widget content;

    if (m.text == kConsultingLabel) {
      content = ConsultingIndicator(accent: widget.accent);
    } else if (m.text.isEmpty && streaming) {
      content = AiThinkingIndicator(accent: widget.accent);
    } else if (streaming) {
      final visible = AiWidgetParser.stripStreamingWidgetDraft(m.text);
      content =
          AiWidgetParser.isStreamingWidgetDraft(m.text)
              ? _streamingWidgetPreview(visible)
              : SelectableText(m.text, style: yBody(size: 14, color: yInk));
    } else if (m.truncated) {
      content = SelectableText(m.text, style: yBody(size: 14, color: yInk));
    } else if (AiWidgetParser.hasWidgets(m.text)) {
      content = AiWidgetRenderer(
        text: m.text,
        accent: widget.accent,
        surface: AiWidgetSurface.flight,
        onSendMessage: (message) => _send(message),
        onActionResult: _s.addLocalAssistant,
        noteId: _s.noteId,
      );
    } else {
      content = NoteMarkdownPreview(
        data: fixMarkdownTables(m.text),
        accent: widget.accent,
        tight: true,
        padding: EdgeInsets.zero,
        scrollWideTables: false,
        textStyle: yBody(size: 14, color: yInk, height: 1.5),
      );
    }
    if (!streaming && m.truncated) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [content, const SizedBox(height: 10), _truncatedNotice()],
      );
    }
    final isLast = i == _s.messages.length - 1;
    final actions =
        (!streaming && m.text.isNotEmpty)
            ? <Widget>[
              // Mode-flavored follow-ups: only on the latest reply (where
              // "profundiza/ejemplo" unambiguously refers to it). The active
              // mode colors how they're answered — no per-action prompt needed.
              if (isLast) ...[
                _msgActionBtn('Profundiza', () => _send('Profundiza en eso.')),
                _msgActionBtn(
                  'Más simple',
                  () => _send('Explícalo más simple.'),
                ),
                _msgActionBtn(
                  'Ejemplo',
                  () => _send('Dame un ejemplo concreto de eso.'),
                ),
              ],
              // Pin to the canvas as a text block (whiteboard/notebook only).
              if (widget.onSendToCanvas != null)
                _msgActionBtn('Enviar a lienzo', () => _sendToCanvas(m.text)),
              _msgActionBtn('Copiar', () => _copy(m.text)),
              _msgActionBtn(
                'Rehacer',
                () => _s.regenerate(
                  i,
                  ref.read(aiAssistantProvider),
                  ref.read(aiUsageLimiterProvider),
                ),
              ),
            ]
            : null;
    return _aiMsgFrame(content, actions: actions);
  }

  Widget _truncatedNotice() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: widget.accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(YuLiIcons.triangleAlert, size: 15, color: widget.accent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Respuesta incompleta',
              style: yBody(size: 11, weight: FontWeight.w700, color: aiInk),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                () => _send(
                  'Continúa exactamente desde donde terminó tu respuesta '
                  'anterior, sin repetir lo que ya mostraste.',
                ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: widget.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Continuar',
                    style: yBody(
                      size: 10,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    YuLiIcons.arrowRight,
                    size: 12,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _streamingWidgetPreview(String visible) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visible.trim().isNotEmpty)
          SelectableText(visible, style: yBody(size: 14, color: yInk)),
        if (visible.trim().isNotEmpty) const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: widget.accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: widget.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Preparando widget',
                style: yMono(
                  size: 10,
                  weight: FontWeight.w800,
                  tracking: 0.8,
                  color: yInk,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _userBubble(AiChatMsg message) {
    final images = message.images;
    return Padding(
      padding: const EdgeInsets.only(left: 58, bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 6),
            child: Text(
              'Tú',
              style: yBody(size: 11, weight: FontWeight.w700, color: aiMuted),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding:
                  images.isEmpty
                      ? const EdgeInsets.fromLTRB(15, 11, 15, 12)
                      : const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: widget.accent.withValues(alpha: 0.2)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (images.isNotEmpty) _messageImageGrid(images),
                  if (images.isNotEmpty && message.text.isNotEmpty)
                    const SizedBox(height: 8),
                  if (message.text.isNotEmpty)
                    Padding(
                      padding:
                          images.isEmpty
                              ? EdgeInsets.zero
                              : const EdgeInsets.fromLTRB(7, 0, 7, 5),
                      child: SelectableText(
                        message.text,
                        style: yBody(
                          size: 15,
                          weight: FontWeight.w500,
                          color: aiInk,
                        ),
                      ),
                    ),
                ],
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

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _composerContextStrip(),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 7, 7, 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.56),
                  Colors.white.withValues(alpha: 0.32),
                  widget.accent.withValues(alpha: 0.07),
                ],
              ),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: -7,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_pendingImages.isNotEmpty) ...[
                  SizedBox(
                    height: 82,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _pendingImages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder:
                          (_, index) =>
                              _pendingImagePreview(_pendingImages[index]),
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        enabled: !_s.streaming,
                        style: yBody(size: 15, color: aiInk),
                        onSubmitted: _s.streaming ? null : _send,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          hintText: 'Escribe a YuLi…',
                          hintStyle: yBody(size: 14, color: aiMuted),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          filled: true,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AiSoftIconButton(
                      icon: YuLiIcons.image,
                      tooltip: 'Adjuntar imagen',
                      color:
                          _s.streaming ||
                                  _pickingImage ||
                                  _s.settings.model == AiModel.pro
                              ? aiMuted
                              : widget.accent,
                      background: Colors.white.withValues(alpha: 0.42),
                      onTap:
                          _s.streaming || _pickingImage ? null : _onImageButton,
                      size: 42,
                    ),
                    const SizedBox(width: 7),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _s.streaming ? null : () => _send(_input.text),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _s.streaming ? aiMuted : widget.accent,
                          shape: BoxShape.circle,
                          boxShadow:
                              _s.streaming
                                  ? null
                                  : [
                                    BoxShadow(
                                      color: widget.accent.withValues(
                                        alpha: 0.26,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                        ),
                        child:
                            _s.streaming
                                ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(
                                  YuLiIcons.arrowUp,
                                  color: Colors.white,
                                  size: 20,
                                ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onImageButton() {
    if (_s.settings.model == AiModel.pro) {
      _showProImageUnavailable();
      return;
    }
    unawaited(_pickImage());
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    final prepared = <AiImageInput>[];
    try {
      final remaining = kMaxAiImagesPerMessage - _pendingImages.length;
      if (remaining <= 0) {
        _showImageLimit();
        return;
      }
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 95,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (picked.isEmpty) return;
      final selected = picked.take(remaining).toList();
      for (final image in selected) {
        prepared.add(await prepareAiChatImage(image.path));
      }
      if (!mounted) {
        await Future.wait(prepared.map(deleteAiChatImage));
        return;
      }
      if (widget.dockController != null) {
        widget.dockController!.attachImages(prepared);
      } else {
        setState(() => _pendingImages = [..._pendingImages, ...prepared]);
      }
      if (picked.length > remaining) _showImageLimit();
    } catch (_) {
      await Future.wait(prepared.map(deleteAiChatImage));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pude preparar esa imagen.')),
      );
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _removePendingImage(AiImageInput image) {
    if (widget.dockController != null) {
      widget.dockController!.removeImage(image);
    } else {
      setState(() => _pendingImages.remove(image));
      unawaited(deleteAiChatImage(image));
    }
  }

  void _showImageLimit() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Puedes adjuntar hasta 4 imágenes por mensaje.'),
      ),
    );
  }

  void _showProImageUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Por el momento, el modo Pro no admite imágenes.'),
        duration: Duration(milliseconds: 1800),
      ),
    );
  }

  Widget _pendingImagePreview(AiImageInput image) {
    return SizedBox(
      width: 126,
      height: 82,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _chatImage(image, width: 118, height: 74, radius: 14),
          Positioned(
            top: -4,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _removePendingImage(image),
              child: Container(
                width: 29,
                height: 29,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.accent.withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      spreadRadius: -4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(YuLiIcons.close, size: 16, color: widget.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatImage(
    AiImageInput image, {
    required double width,
    required double height,
    required double radius,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showImagePreview(image),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(image.path),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder:
              (_, _, _) => Container(
                width: width,
                height: height,
                alignment: Alignment.center,
                color: aiPaperSoft,
                child: const Icon(YuLiIcons.imageOff, color: aiMuted, size: 24),
              ),
        ),
      ),
    );
  }

  Widget _messageImageGrid(List<AiImageInput> images) {
    if (images.length == 1) {
      return _chatImage(images.first, width: 250, height: 142, radius: 13);
    }
    return SizedBox(
      width: 250,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final image in images)
            _chatImage(
              image,
              width: 123,
              height: images.length == 2 ? 142 : 98,
              radius: 11,
            ),
        ],
      ),
    );
  }

  Future<void> _showImagePreview(AiImageInput image) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar imagen',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 190),
      pageBuilder:
          (dialogContext, _, _) => BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Material(
              color: Colors.black.withValues(alpha: 0.18),
              child: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 5,
                          child: Center(
                            child: Image.file(
                              File(image.path),
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (_, _, _) => const Icon(
                                    YuLiIcons.imageOff,
                                    color: Colors.white,
                                    size: 42,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: AiSoftIconButton(
                        icon: YuLiIcons.close,
                        tooltip: 'Cerrar imagen',
                        color: aiInk,
                        background: Colors.white.withValues(alpha: 0.72),
                        onTap: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      transitionBuilder:
          (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
              child: child,
            ),
          ),
    );
  }

  Widget _composerContextStrip() {
    final hostKind =
        ref.watch(noteByIdProvider(_s.noteId)).valueOrNull?.kind ??
        NoteKind.block;
    final sources =
        ref.watch(canvasContextSourcesProvider(_s.noteId)).valueOrNull ??
        const <CanvasContextSource>[];
    final contextLabel = switch (hostKind) {
      NoteKind.block => 'Esta nota',
      NoteKind.whiteboard => 'Esta pizarra',
      NoteKind.notebook => 'Este cuaderno',
    };
    final effectiveContextLabel =
        _s.settings.useNoteContext
            ? contextLabel
            : _s.settings.useRelatedSources
            ? 'Sólo fuentes'
            : 'Sin contexto';
    final historyLabel = switch (_s.settings.historyDepth) {
      AiHistoryDepth.recent => 'Reciente',
      AiHistoryDepth.normal => 'Normal',
      AiHistoryDepth.full => 'Todo el chat',
    };
    final lengthLabel = switch (_s.settings.responseLength) {
      AiResponseLength.brief => 'Breve',
      AiResponseLength.normal => 'Respuesta media',
      AiResponseLength.detailed => 'Detallada',
    };
    final costScore =
        (_s.settings.model == AiModel.pro ? 2 : 0) +
        (_s.settings.responseLength == AiResponseLength.detailed ? 2 : 0) +
        (_s.settings.historyDepth == AiHistoryDepth.full ? 2 : 0) +
        (_s.settings.useRelatedSources ? 1 : 0) +
        (_s.settings.useTools ? 1 : 0);
    final costLabel =
        costScore >= 5
            ? 'Gasto alto'
            : costScore >= 2
            ? 'Gasto medio'
            : 'Gasto bajo';
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          AiStatusPill(
            icon: YuLiIcons.fileText,
            label: effectiveContextLabel,
            accent: widget.accent,
            active: _s.settings.useNoteContext || _s.settings.useRelatedSources,
            onTap: () => setState(() => _showContext = !_showContext),
          ),
          const SizedBox(width: 6),
          AiStatusPill(
            icon: YuLiIcons.link,
            label:
                sources.isEmpty
                    ? 'Gestionar contexto'
                    : sources.length == 1
                    ? '1 fuente'
                    : '${sources.length} fuentes',
            accent: widget.accent,
            active: _s.settings.useRelatedSources && sources.isNotEmpty,
            highImpact: _s.settings.useRelatedSources && sources.isNotEmpty,
            onTap: _showSourcesSheet,
          ),
          const SizedBox(width: 6),
          AiStatusPill(
            icon: YuLiIcons.clock,
            label: historyLabel,
            accent: widget.accent,
            highImpact: _s.settings.historyDepth == AiHistoryDepth.full,
            onTap: _openChatMenu,
          ),
          const SizedBox(width: 6),
          AiStatusPill(
            icon: YuLiIcons.textQuote,
            label: lengthLabel,
            accent: widget.accent,
            highImpact: _s.settings.responseLength == AiResponseLength.detailed,
            onTap: _openChatMenu,
          ),
          const SizedBox(width: 6),
          AiStatusPill(
            label: costLabel,
            accent: widget.accent,
            active: costScore >= 5,
            highImpact: costScore >= 2,
            onTap: _openChatMenu,
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
          padding: EdgeInsets.fromLTRB(8, 8, 8, insets + 8),
          child: AiFrostedSurface(
            accent: widget.accent,
            role: AiFrostedSurfaceRole.dialog,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'EDITAR CONTEXTO',
                    style: ySans(
                      size: 18,
                      weight: FontWeight.w700,
                      color: aiInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Escribe información que YuLi debe tener presente en esta conversación.',
                    style: yBody(size: 12, color: aiMuted),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.52),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: aiHairline),
                    ),
                    child: TextField(
                      controller: _anchorInput,
                      maxLines: null,
                      style: yBody(size: 14, color: aiInk),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.all(14),
                        hintText: 'Contexto de la conversación',
                        hintStyle: yBody(size: 14, color: aiMuted),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
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
                            color: Colors.white.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: aiHairline),
                          ),
                          child: Text(
                            'LIMPIAR',
                            style: yMono(
                              size: 11,
                              weight: FontWeight.w700,
                              tracking: 1.2,
                              color: aiInk,
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

  Widget _primaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.accent,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
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
  final VoidCallback? onEditAnchor;
  const _SourcesSheet({
    required this.canvasNoteId,
    required this.folderId,
    required this.accent,
    required this.onChanged,
    this.onEditAnchor,
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
    return Padding(
      padding: const EdgeInsets.all(8),
      child: AiFrostedSurface(
        accent: widget.accent,
        role: AiFrostedSurfaceRole.dialog,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: widget.accent.withValues(alpha: 0.26),
                      ),
                    ),
                    child: Icon(YuLiIcons.link, size: 18, color: widget.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GESTIONAR CONTEXTO',
                          style: ySans(
                            size: 17,
                            weight: FontWeight.w700,
                            color: aiInk,
                          ),
                        ),
                        Text(
                          'Elige qué información puede consultar YuLi.',
                          style: yBody(size: 12, color: aiMuted),
                        ),
                      ],
                    ),
                  ),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.accent,
                        ),
                      ),
                    ),
                  AiSoftIconButton(
                    icon: YuLiIcons.close,
                    tooltip: 'Cerrar',
                    size: 34,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (widget.onEditAnchor != null) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onEditAnchor,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.accent.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(YuLiIcons.pencil, size: 17, color: widget.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EDITAR CONTEXTO MANUAL',
                                style: ySans(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: aiInk,
                                ),
                              ),
                              Text(
                                'Escribe instrucciones o datos que no están en una nota.',
                                style: yBody(size: 11, color: aiMuted),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          YuLiIcons.chevronRight,
                          size: 17,
                          color: widget.accent,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (sources.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.36),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: aiHairline),
                  ),
                  child: Text(
                    widget.onEditAnchor == null
                        ? 'Agrega una nota o un enlace para darle más información a YuLi.'
                        : 'Agrega una nota, un enlace o escribe contexto manual.',
                    style: yBody(size: 13, color: aiMuted),
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: aiHairline),
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
                      color: s.enabled ? aiInk : aiMuted,
                    ),
                  ),
                  if (s.isUrl)
                    Text(
                      '${s.ref}  ·  ${_ago(s.fetchedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: yMono(size: 9, tracking: 0.3, color: aiMuted),
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
            _iconBtn(
              YuLiIcons.close,
              'Quitar',
              _busy ? null : () => _remove(s),
            ),
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
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: aiHairline),
        ),
        child: Icon(icon, size: 14, color: onTap == null ? aiMuted : aiInk),
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
            color: widget.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: widget.accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: widget.accent),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: yMono(
                  size: 12,
                  weight: FontWeight.w700,
                  tracking: 1.2,
                  color: aiInk,
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
                    NoteMarkdownPreview(
                      data: fixMarkdownTables(content),
                      accent: accent,
                    ),
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
