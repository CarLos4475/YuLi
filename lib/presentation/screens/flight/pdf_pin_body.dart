import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'pin_dialog.dart';
import 'pin_recents.dart';

/// What the PDF dialog returns: either "open the file picker for a new PDF", or
/// "re-pin this recent file" (by its source path). Null = the user cancelled.
sealed class PdfPromptResult {
  const PdfPromptResult();
}

class PdfPromptPickNew extends PdfPromptResult {
  const PdfPromptPickNew();
}

class PdfPromptRecent extends PdfPromptResult {
  final String path;
  final String? title;
  const PdfPromptRecent(this.path, this.title);
}

/// YuLi dialog for the PDF pin: a big ELEGIR ARCHIVO action plus the recents
/// list (recents whose file was deleted are already pruned by [PinRecents.pdf]).
/// Returns the user's intent; the caller runs the file picker / copy.
Future<PdfPromptResult?> promptPdf(
  BuildContext context, {
  required Color accent,
}) async {
  final recents = await PinRecents.pdf();
  if (!context.mounted) return null;
  return showDialog<PdfPromptResult>(
    context: context,
    builder: (ctx) => PinDialogShell(
      icon: YuLiIcons.fileText,
      title: 'AGREGAR PDF',
      accent: accent,
      footer: Row(
        children: [
          const Spacer(),
          PinGhostButton(label: 'CANCELAR', onTap: () => Navigator.pop(ctx)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PinBigActionButton(
            icon: YuLiIcons.folder,
            label: 'ELEGIR ARCHIVO PDF',
            accent: accent,
            onTap: () => Navigator.pop(ctx, const PdfPromptPickNew()),
          ),
          PinRecentsList(
            recents: recents,
            leadingIcon: YuLiIcons.fileText,
            accent: accent,
            onPick: (r) => Navigator.pop(ctx, PdfPromptRecent(r.value, r.title)),
          ),
        ],
      ),
    ),
  );
}

/// Body of a floating PDF pin: a pinch-zoom page view plus a brutalist control
/// bar (prev/next, tappable N/TOTAL, page slider, reset zoom). Owns the pdfx
/// controller so its lifetime survives the window's per-gesture rebuilds AND a
/// collapse/restore (the parent keeps this State alive via the pin's ValueKey
/// and never unmounts the body). All gestures are absorbed by the view, so
/// panning/zooming the PDF never reaches the canvas underneath.
class PdfPinBody extends StatefulWidget {
  final String filePath;

  /// Page to open at (1-based) — the persisted last page.
  final int initialPage;

  /// Note/folder accent — fills the primary control + the slider track.
  final Color accent;

  /// Fires when the visible page changes, so the owner can persist it.
  final ValueChanged<int>? onPageChanged;

  const PdfPinBody({
    super.key,
    required this.filePath,
    this.initialPage = 1,
    required this.accent,
    this.onPageChanged,
  });

  @override
  State<PdfPinBody> createState() => _PdfPinBodyState();
}

class _PdfPinBodyState extends State<PdfPinBody> {
  late final PdfControllerPinch _controller = PdfControllerPinch(
    document: PdfDocument.openFile(widget.filePath),
    initialPage: widget.initialPage,
  );

  // Non-null only while the page slider is being dragged: the target page the
  // thumb is over. Lets the thumb + the N/TOTAL readout track the finger live
  // without turning the actual page until release.
  final ValueNotifier<double?> _dragPage = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _controller.pageListenable.addListener(_reportPage);
  }

  void _reportPage() => widget.onPageChanged?.call(_controller.pageListenable.value);

  @override
  void dispose() {
    _controller.pageListenable.removeListener(_reportPage);
    _dragPage.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    final total = _controller.pagesCount ?? 1;
    _controller.animateToPage(
      pageNumber: page.clamp(1, total),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _resetZoom() => _controller.value = Matrix4.identity();

  Future<void> _promptPage(int current, int total) async {
    final ctrl = TextEditingController(text: '$current');
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: yBorderStrong, width: yLineMid),
          borderRadius: BorderRadius.zero,
        ),
        title: Text(
          'IR A PÁGINA · 1–$total',
          style: yMono(size: 11, weight: FontWeight.w700, tracking: 1.2),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: yMono(size: 14, weight: FontWeight.w700),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCELAR', style: yMono(size: 11, color: yMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: Text('IR', style: yMono(size: 11, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (target != null) _goTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: yCream2,
            child: PdfViewPinch(
              controller: _controller,
              padding: 6,
              builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                documentLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator(color: yInk)),
                errorBuilder: (_, error) => _message('PDF NO DISPONIBLE'),
              ),
            ),
          ),
        ),
        _controlBar(),
      ],
    );
  }

  Widget _message(String text) => Center(
        child: Text(
          text,
          style: yMono(
            size: 10,
            weight: FontWeight.w700,
            tracking: 1.2,
            color: yMuted,
          ),
        ),
      );

  Widget _controlBar() {
    return ValueListenableBuilder<PdfLoadingState>(
      valueListenable: _controller.loadingState,
      builder: (context, state, _) {
        final ready = state == PdfLoadingState.success;
        final total = _controller.pagesCount ?? 1;
        return Container(
          height: 36,
          decoration: const BoxDecoration(
            color: yCream,
            border:
                Border(top: BorderSide(color: yBorderStrong, width: yLineThin)),
          ),
          // Right padding so the last control never sits under the resize handle.
          padding: const EdgeInsets.only(left: 6, right: 26),
          child: ValueListenableBuilder<int>(
            valueListenable: _controller.pageListenable,
            builder: (context, page, _) {
              return ValueListenableBuilder<double?>(
                valueListenable: _dragPage,
                builder: (context, drag, _) {
                  // While dragging, everything that reads "current page" shows
                  // the target the thumb is over.
                  final shown =
                      (drag?.round() ?? page).clamp(1, total).toInt();
                  return Row(
                    children: [
                      _iconBtn(
                        YuLiIcons.chevronLeft,
                        enabled: ready && page > 1,
                        onTap: () => _goTo(page - 1),
                      ),
                      _primaryBtn(
                        YuLiIcons.chevronRight,
                        enabled: ready && page < total,
                        onTap: () => _goTo(page + 1),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: ready ? () => _promptPage(page, total) : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: yBorderSoft, width: yLineThin),
                          ),
                          child: Text(
                            ready ? '$shown / $total' : '· / ·',
                            style: yMono(
                              size: 10,
                              weight: FontWeight.w700,
                              tracking: 0.6,
                              color: yInk,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            thumbColor: widget.accent,
                            activeTrackColor: widget.accent,
                            inactiveTrackColor: yBorderSoft,
                            overlayColor: widget.accent.withValues(alpha: 0.15),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12),
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: (drag ?? page.toDouble())
                                .clamp(1, total.toDouble()),
                            min: 1,
                            max: total < 2 ? 2 : total.toDouble(),
                            // Thumb + readout follow the finger live; the page
                            // only turns on release (no render per tick).
                            onChanged: ready && total > 1
                                ? (v) => _dragPage.value = v
                                : null,
                            onChangeEnd: ready && total > 1
                                ? (v) {
                                    _goTo(v.round());
                                    _dragPage.value = null;
                                  }
                                : null,
                          ),
                        ),
                      ),
                      _iconBtn(
                        YuLiIcons.maximize,
                        enabled: ready,
                        onTap: _resetZoom,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _iconBtn(IconData icon,
      {required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Icon(icon, size: 16, color: enabled ? yInk : yBorderSoft),
      ),
    );
  }

  /// Filled accent square (the design's primary control).
  Widget _primaryBtn(IconData icon,
      {required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: enabled ? widget.accent : yBorderSoft,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
