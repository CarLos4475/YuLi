import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/canvas_ocr.dart';
import '../../providers/canvas_ocr_provider.dart';
import '../../providers/canvas_ocr_settings_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/ink_recognizer_provider.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'canvas_ocr_search.dart';

final canvasOcrSearchOpenProvider = StateProvider.autoDispose.family<bool, int>(
  (ref, id) => false,
);
final canvasOcrHighlightProvider = StateProvider.autoDispose.family<Rect?, int>(
  (ref, id) => null,
);
final canvasOcrHintProvider = StateProvider.autoDispose
    .family<CanvasOcrHint?, int>((ref, id) => null);

class CanvasOcrHint {
  final Rect bounds;
  final List<String> alternatives;
  const CanvasOcrHint(this.bounds, this.alternatives);
}

class CanvasOcrButton extends ConsumerStatefulWidget {
  final List<int> blockIds;
  final Color accent;
  const CanvasOcrButton({
    super.key,
    required this.blockIds,
    required this.accent,
  });
  @override
  ConsumerState<CanvasOcrButton> createState() => _CanvasOcrButtonState();
}

class _CanvasOcrButtonState extends ConsumerState<CanvasOcrButton> {
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    for (final id in widget.blockIds) {
      ref.read(canvasOcrCoordinatorProvider).schedule(id);
    }
  });
  @override
  void didUpdateWidget(CanvasOcrButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.blockIds, widget.blockIds)) _schedule();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.blockIds.isEmpty) return const SizedBox.shrink();
    return _OcrIconAction(
      label: 'Buscar en la escritura',
      icon: YuLiIcons.search,
      accent: widget.accent,
      size: 28,
      onTap:
          () =>
              ref
                  .read(
                    canvasOcrSearchOpenProvider(widget.blockIds.first).notifier,
                  )
                  .state = true,
    );
  }
}

class CanvasOcrHeader extends ConsumerWidget {
  final List<int> blockIds;
  final Color accent;
  final void Function(int, Rect) onLocate;
  final Widget child;
  const CanvasOcrHeader({
    super.key,
    required this.blockIds,
    required this.accent,
    required this.onLocate,
    required this.child,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (blockIds.isEmpty) return child;
    final open = ref.watch(canvasOcrSearchOpenProvider(blockIds.first));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Offstage(offstage: open, child: child),
        if (open)
          CanvasOcrSearchBar(
            blockIds: blockIds,
            accent: accent,
            onLocate: onLocate,
          ),
      ],
    );
  }
}

class CanvasOcrSearchBar extends ConsumerStatefulWidget {
  final List<int> blockIds;
  final Color accent;
  final void Function(int, Rect) onLocate;
  const CanvasOcrSearchBar({
    super.key,
    required this.blockIds,
    required this.accent,
    required this.onLocate,
  });
  @override
  ConsumerState<CanvasOcrSearchBar> createState() => _CanvasOcrSearchBarState();
}

class _CanvasOcrSearchBarState extends ConsumerState<CanvasOcrSearchBar> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _generation = 0;
  List<CanvasOcrMatch> _matches = [];
  List<CanvasOcrPage>? _cachedPages;
  int _index = 0;
  int? _highlightedBlock;
  StateController<Rect?>? _highlightState;
  bool _busy = false;
  bool _downloading = false;
  bool? _modelReady;
  String? _message;
  String? _indexStatus;

  @override
  void initState() {
    super.initState();
    _checkModel();
    _queueSearch();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    final state = _highlightState;
    if (state != null) {
      Future.microtask(() {
        if (state.mounted) state.state = null;
      });
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(CanvasOcrSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.blockIds, widget.blockIds)) {
      _generation++;
      _cachedPages = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _queueSearch();
      });
    }
  }

  void _clearHighlight() {
    final state = _highlightState;
    _highlightedBlock = null;
    _highlightState = null;
    if (state != null && state.mounted) state.state = null;
  }

  void _queueSearch() {
    _generation++;
    _debounce?.cancel();
    _clearHighlight();
    setState(() {
      _busy = true;
      _matches = [];
      _index = 0;
    });
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    final generation = _generation;
    try {
      var pages = _cachedPages;
      if (pages == null) {
        pages = <CanvasOcrPage>[];
        final repo = ref.read(canvasOcrRepositoryProvider);
        for (final id in widget.blockIds) {
          final page = await repo.read(id);
          if (!mounted || generation != _generation) return;
          if (page != null) pages.add(page);
        }
        _cachedPages = pages;
      }
      final matches = await compute(searchCanvasOcrIsolate, (
        pages,
        _query.text,
      ));
      if (!mounted || generation != _generation) return;
      final pending =
          pages.length != widget.blockIds.length ||
          pages.any((p) => !p.isCurrent);
      final unchecked = pages.any(
        (p) => p.segments.any((s) => !s.spellingChecked),
      );
      setState(() {
        _matches = matches;
        _index = 0;
        _busy = false;
        _message = null;
        _indexStatus =
            pending
                ? 'Reconociendo escritura…'
                : unchecked
                ? 'Ortografía pendiente de revisión'
                : null;
      });
      if (matches.isNotEmpty) _select(0);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message = 'No se pudo buscar. Inténtalo de nuevo.';
        });
      }
    }
  }

  void _select(int index) {
    if (_matches.isEmpty) return;
    _clearHighlight();
    setState(() => _index = (index + _matches.length) % _matches.length);
    final match = _matches[_index];
    _highlightedBlock = match.blockId;
    _highlightState = ref.read(
      canvasOcrHighlightProvider(match.blockId).notifier,
    );
    _highlightState!.state = match.bounds;
    widget.onLocate(match.blockId, match.bounds);
  }

  void _close() {
    _clearHighlight();
    _focus.unfocus();
    ref
        .read(canvasOcrSearchOpenProvider(widget.blockIds.first).notifier)
        .state = false;
  }

  Future<void> _checkModel() async {
    try {
      final ready = await ref.read(inkRecognizerProvider).isModelReady('es');
      if (mounted) setState(() => _modelReady = ready);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'El reconocimiento requiere Android o iOS.');
      }
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final ready = await ref.read(inkRecognizerProvider).downloadModel('es');
      if (!mounted) return;
      setState(() {
        _modelReady = ready;
        _message = ready ? null : 'No se pudo descargar español.';
      });
      if (ready) {
        for (final id in widget.blockIds) {
          ref.read(canvasOcrCoordinatorProvider).schedule(id);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'No se pudo descargar español. Revisa la conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final id in widget.blockIds) {
      ref.listen(canvasOcrBlockVersionProvider(id), (_, _) {
        _cachedPages = null;
        _queueSearch();
      });
    }
    if (_highlightedBlock != null) {
      ref.watch(canvasOcrHighlightProvider(_highlightedBlock!));
    }
    final statuses = ref.watch(canvasOcrStatusProvider);
    final warning =
        widget.blockIds
            .map((id) => statuses[id])
            .whereType<String>()
            .where((s) => s.contains('No se pudo') || s.contains('Demasiada'))
            .firstOrNull;
    final settings = ref.watch(canvasOcrSettingsProvider).valueOrNull;
    final status =
        _message ??
        (settings?.automatic != true
            ? 'Reconocimiento automático desactivado'
            : settings?.spelling != true
            ? (_indexStatus == 'Reconociendo escritura…' ? _indexStatus : null)
            : warning ?? _indexStatus);
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: const BoxDecoration(
          color: yCream2,
          border: Border(
            bottom: BorderSide(color: yBorderStrong, width: yLineThin),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      YuLiIcons.search,
                      size: 16,
                      color: widget.accent,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      focusNode: _focus,
                      autofocus: true,
                      maxLength: 256,
                      onChanged: (_) => _queueSearch(),
                      onSubmitted:
                          (_) => _select(
                            _index +
                                (HardwareKeyboard.instance.isShiftPressed
                                    ? -1
                                    : 1),
                          ),
                      style: yBody(size: 14),
                      decoration: const InputDecoration(
                        hintText: 'Buscar…',
                        counterText: '',
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      _busy
                          ? '… / …'
                          : '${_matches.isEmpty ? 0 : _index + 1} / ${_matches.length}${_matches.length == 1000 ? '+' : ''}',
                      style: yMono(size: 11, color: yMuted),
                    ),
                  ),
                  _OcrIconAction(
                    label: 'Coincidencia anterior',
                    icon: YuLiIcons.chevronLeft,
                    accent: widget.accent,
                    onTap: _matches.isEmpty ? null : () => _select(_index - 1),
                  ),
                  _OcrIconAction(
                    label: 'Coincidencia siguiente',
                    icon: YuLiIcons.chevronRight,
                    accent: widget.accent,
                    onTap: _matches.isEmpty ? null : () => _select(_index + 1),
                  ),
                  _OcrIconAction(
                    label: 'Cerrar búsqueda',
                    icon: YuLiIcons.close,
                    accent: widget.accent,
                    onTap: _close,
                  ),
                ],
              ),
            ),
            if (_modelReady == false)
              GestureDetector(
                onTap: _downloading ? null : _download,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _downloading
                        ? 'Descargando español…'
                        : 'Descargar español para buscar escritura',
                    style: yBody(size: 12, color: widget.accent),
                  ),
                ),
              ),
            if (status != null && _modelReady != false)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: yBody(size: 11, color: yMuted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CanvasOcrMarks extends ConsumerStatefulWidget {
  final int blockId;
  final Offset pageOffset;
  final TransformationController transform;
  final Color accent;
  const CanvasOcrMarks({
    super.key,
    required this.blockId,
    required this.transform,
    required this.accent,
    this.pageOffset = Offset.zero,
  });
  @override
  ConsumerState<CanvasOcrMarks> createState() => _CanvasOcrMarksState();
}

class _CanvasOcrMarksState extends ConsumerState<CanvasOcrMarks> {
  CanvasOcrPage? _cachedPage;
  Offset? _cachedOffset;
  List<Rect> _regions = const [];
  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_dismiss);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
  }

  void _pointer(PointerEvent event) {
    if (event is PointerDownEvent) _dismiss();
  }

  void _dismiss() {
    if (mounted && ref.read(canvasOcrHintProvider(widget.blockId)) != null) {
      ref.read(canvasOcrHintProvider(widget.blockId).notifier).state = null;
    }
  }

  @override
  void didUpdateWidget(CanvasOcrMarks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform != widget.transform) {
      oldWidget.transform.removeListener(_dismiss);
      widget.transform.addListener(_dismiss);
    }
  }

  @override
  void dispose() {
    widget.transform.removeListener(_dismiss);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(canvasOcrPageProvider(widget.blockId)).valueOrNull;
    ref.listen(canvasOcrSettingsProvider, (_, next) {
      if (next.valueOrNull?.spelling != true) {
        ref.read(canvasOcrHintProvider(widget.blockId).notifier).state = null;
      }
    });
    final highlight = ref.watch(canvasOcrHighlightProvider(widget.blockId));
    final spelling =
        ref.watch(canvasOcrSettingsProvider).valueOrNull?.spelling == true;
    final storedHint = ref.watch(canvasOcrHintProvider(widget.blockId));
    final hint = spelling ? storedHint : null;
    if (!identical(page, _cachedPage) || _cachedOffset != widget.pageOffset) {
      _cachedPage = page;
      _cachedOffset = widget.pageOffset;
      _regions = <Rect>[];
      if (page != null && page.isCurrent) {
        for (final s in page.segments) {
          for (final suggestion in s.spelling) {
            final box = s.wordBoundsFor(suggestion);
            if (box != null) _regions.add(box.shift(widget.pageOffset));
          }
        }
      }
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, limits) {
            final rect =
                hint == null
                    ? null
                    : MatrixUtils.transformRect(
                      widget.transform.value,
                      hint.bounds.shift(widget.pageOffset),
                    );
            final width = math.min(240.0, math.max(0.0, limits.maxWidth - 16));
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: CanvasOcrMarksPainter(
                      spelling ? _regions : const [],
                      widget.transform,
                      widget.accent,
                      page?.isCurrent == true
                          ? highlight?.shift(widget.pageOffset)
                          : null,
                    ),
                  ),
                ),
                if (rect != null && page?.isCurrent == true)
                  Positioned(
                    left: (rect.center.dx - width / 2).clamp(
                      8.0,
                      math.max(8.0, limits.maxWidth - width - 8),
                    ),
                    top: (rect.top >= 76 ? rect.top - 72 : rect.bottom + 8)
                        .clamp(4.0, math.max(4.0, limits.maxHeight - 72)),
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: yCream,
                        border: Border.all(
                          color: widget.accent,
                          width: yLineThin,
                        ),
                        boxShadow: const [
                          BoxShadow(color: yBorderSoft, offset: Offset(2, 2)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'El corrector sugiere',
                            style: yMono(size: 10, color: yMuted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hint!.alternatives.isEmpty
                                ? 'Sin alternativas disponibles'
                                : hint.alternatives.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: yBody(size: 14, weight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class CanvasOcrMarksPainter extends CustomPainter {
  final List<Rect> regions;
  final TransformationController transform;
  final Color accent;
  final Rect? highlight;
  CanvasOcrMarksPainter(
    this.regions,
    this.transform,
    this.accent,
    this.highlight,
  ) : super(repaint: transform);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint =
        Paint()
          ..color = accent
          ..strokeWidth = 1.3;
    for (final region in regions) {
      final rect = MatrixUtils.transformRect(transform.value, region);
      if (!rect.inflate(4).overlaps(Offset.zero & size)) continue;
      canvas.drawLine(
        Offset(rect.left, rect.bottom + 3),
        Offset(rect.right, rect.bottom + 3),
        paint,
      );
    }
    if (highlight != null) {
      final rect = MatrixUtils.transformRect(
        transform.value,
        highlight!,
      ).inflate(3);
      canvas.drawRect(rect, Paint()..color = accent.withValues(alpha: .16));
      canvas.drawRect(
        rect,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CanvasOcrMarksPainter old) =>
      !listEquals(old.regions, regions) ||
      old.transform != transform ||
      old.accent != accent ||
      old.highlight != highlight;
}

bool showCanvasSpellingAt(
  WidgetRef ref,
  int blockId,
  Offset point,
  PointerDeviceKind kind,
) {
  if (kind != PointerDeviceKind.touch) return false;
  if (ref.read(canvasOcrSettingsProvider).valueOrNull?.spelling != true) {
    return false;
  }
  final page = ref.read(canvasOcrPageProvider(blockId)).valueOrNull;
  if (page == null || !page.isCurrent) return false;
  for (final segment in page.segments) {
    for (final suggestion in segment.spelling) {
      final box = segment.wordBoundsFor(suggestion);
      if (box == null || !box.inflate(3).contains(point)) continue;
      ref.read(canvasOcrHintProvider(blockId).notifier).state = CanvasOcrHint(
        box,
        suggestion.alternatives,
      );
      return true;
    }
  }
  return false;
}

class _OcrIconAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final double size;
  final VoidCallback? onTap;
  const _OcrIconAction({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.size = 36,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: 17,
            color: onTap == null ? yMuted.withValues(alpha: .4) : accent,
          ),
        ),
      ),
    ),
  );
}
