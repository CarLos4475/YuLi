import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/ai_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/flight_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/note_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_action_sheet.dart';
import '../../widgets/yuli_design.dart';
import '../../widgets/yuli_ai_fab.dart';
import '../yuli_ai/yuli_ai_chat_sheet.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
import 'folder_detail_screen.dart';
import 'note_editor_screen.dart';
import 'notebook_editor_screen.dart';
import 'whiteboard_editor_screen.dart';
import 'new_folder_dialog.dart';
import '../../widgets/edit_item_dialog.dart';

class FlightScreen extends ConsumerStatefulWidget {
  const FlightScreen({super.key});

  @override
  ConsumerState<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends ConsumerState<FlightScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pendingNoteId = ref.read(pendingNoteNavigationProvider);
      if (pendingNoteId != null) {
        ref.read(pendingNoteNavigationProvider.notifier).state = null;
        await _navigateToPendingNote(pendingNoteId);
      }
      final pendingFolderId = ref.read(pendingFolderNavigationProvider);
      if (pendingFolderId != null) {
        ref.read(pendingFolderNavigationProvider.notifier).state = null;
        await _navigateToPendingFolder(pendingFolderId);
      }
    });
  }

  Future<void> _navigateToPendingFolder(int folderId) async {
    final folder = await ref.read(folderRepositoryProvider).getById(folderId);
    if (folder == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FolderDetailScreen(folder: folder)),
    );
  }

  Future<void> _navigateToPendingNote(int noteId) async {
    final note = await ref.read(noteRepositoryProvider).getById(noteId);
    if (note == null || !mounted) return;
    final folder = await ref
        .read(folderRepositoryProvider)
        .getById(note.folderId);
    if (folder == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => switch (note.kind) {
              NoteKind.whiteboard => WhiteboardEditorScreen(
                note: note,
                folder: folder,
              ),
              NoteKind.notebook => NotebookEditorScreen(
                note: note,
                folder: folder,
              ),
              _ => NoteEditorScreen(note: note, folder: folder),
            },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(activeFoldersProvider).valueOrNull ?? [];
    final allNotes = ref.watch(recentNotesProvider).valueOrNull ?? [];
    final pinned = ref.watch(pinnedFoldersProvider);
    final toolbar = ref.watch(flightToolbarProvider);

    // Counts/sorts derived locally — no extra streams.
    final counts = <int, int>{};
    for (final n in allNotes) {
      counts[n.folderId] = (counts[n.folderId] ?? 0) + 1;
    }
    final totalNotes = counts.values.fold<int>(0, (s, v) => s + v);

    final filtered = _filterFolders(folders, counts, pinned, toolbar.filter);
    final sorted = _sortFolders(filtered, counts, pinned, toolbar.sort);

    return Stack(
      children: [
        Column(
          children: [
            ModeHeader(
              mode: 'FLIGHT',
              subtitle:
                  'MODO NOTAS · ${folders.length} CARPETAS · $totalNotes NOTAS',
              color: yFlight,
              onBack:
                  () =>
                      ref.read(currentModeProvider.notifier).state =
                          AppMode.home,
              headerRight: [
                _SearchBar(totalNotes: totalNotes),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      () => showModeHelp(
                        context,
                        mode: 'FLIGHT',
                        accent: yFlight,
                        description:
                            'Organiza tus notas en carpetas con colores. '
                            'Crea notas de texto con bloques, cuadernos con páginas '
                            'o pizarras infinitas para dibujo con stylus.',
                        tips: [
                          'Crea carpetas para agrupar notas por tema',
                          'Usa notas bloque para texto, math y listas',
                          'Los cuadernos tienen páginas A4 con dibujo',
                          'Las pizarras son lienzos infinitos con zoom',
                        ],
                      ),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: yCream,
                      shape: BoxShape.circle,
                      border: Border.all(color: yBorderStrong, width: yLineMid),
                    ),
                    child: Text(
                      '?',
                      style: yMono(
                        size: 16,
                        weight: FontWeight.w700,
                        color: yInk,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const _Toolbar(),
            Expanded(
              child: Container(
                color: yCream,
                child:
                    sorted.isEmpty
                        ? _Empty()
                        : _FolderGrid(folders: sorted, counts: counts),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: YuliAiFab(
            accent: yFlight,
            onTap:
                () => showYuliAiChat(
                  context,
                  ref,
                  accent: yFlight,
                  surfaceContext: const YuliAiSurfaceContext(
                    mode: 'Flight',
                    view: 'Carpetas',
                    details: 'Vista general de carpetas, notas y pizarras.',
                  ),
                ),
          ),
        ),
      ],
    );
  }

  List<Folder> _filterFolders(
    List<Folder> folders,
    Map<int, int> counts,
    Set<int> pinned,
    FlightFilter filter,
  ) {
    switch (filter) {
      case FlightFilter.all:
        return folders;
      case FlightFilter.withNotes:
        return folders.where((f) => (counts[f.id] ?? 0) > 0).toList();
      case FlightFilter.empty:
        return folders.where((f) => (counts[f.id] ?? 0) == 0).toList();
      case FlightFilter.pinned:
        return folders.where((f) => pinned.contains(f.id)).toList();
    }
  }

  List<Folder> _sortFolders(
    List<Folder> folders,
    Map<int, int> counts,
    Set<int> pinned,
    FlightSort sort,
  ) {
    final list = List<Folder>.from(folders);
    int cmp(Folder a, Folder b) {
      switch (sort) {
        case FlightSort.alphabetical:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case FlightSort.count:
          return (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
        case FlightSort.recent:
          return b.createdAt.compareTo(a.createdAt);
      }
    }

    list.sort((a, b) {
      final pa = pinned.contains(a.id) ? 0 : 1;
      final pb = pinned.contains(b.id) ? 0 : 1;
      if (pa != pb) return pa - pb;
      return cmp(a, b);
    });
    return list;
  }
}

// ─── Toolbar ──────────────────────────────────────────────────────────────

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolbar = ref.watch(flightToolbarProvider);
    final notifier = ref.read(flightToolbarProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                () => showDialog(
                  context: context,
                  builder: (_) => const NewFolderDialog(),
                ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: yFlight,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '+',
                    style: TextStyle(fontSize: 18, color: yCream, height: 1.0),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'NUEVA CARPETA',
                    style: yBody(
                      size: 13,
                      weight: FontWeight.w700,
                      color: yCream,
                    ).copyWith(letterSpacing: 1.2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          ToolChip(
            label: 'ORDEN',
            value: _sortLabel(toolbar.sort),
            onTap: () => _showSortMenu(context, ref),
          ),
          const SizedBox(width: 6),
          ToolChip(
            label: 'FILTRO',
            value: _filterLabel(toolbar.filter),
            onTap: () => _showFilterMenu(context, ref),
          ),
          const Spacer(),
          ViewToggleBtn(
            icon: YuLiIcons.layoutGrid,
            active: toolbar.view == FlightView.grid,
            onTap: () => notifier.setView(FlightView.grid),
          ),
          const SizedBox(width: 4),
          ViewToggleBtn(
            icon: YuLiIcons.menu,
            active: toolbar.view == FlightView.list,
            onTap: () => notifier.setView(FlightView.list),
          ),
        ],
      ),
    );
  }

  String _sortLabel(FlightSort s) {
    switch (s) {
      case FlightSort.recent:
        return 'RECIENTE ↓';
      case FlightSort.alphabetical:
        return 'A–Z';
      case FlightSort.count:
        return 'MÁS NOTAS';
    }
  }

  String _filterLabel(FlightFilter f) {
    switch (f) {
      case FlightFilter.all:
        return 'TODAS';
      case FlightFilter.withNotes:
        return 'CON NOTAS';
      case FlightFilter.empty:
        return 'VACÍAS';
      case FlightFilter.pinned:
        return 'FIJADAS';
    }
  }

  void _showFilterMenu(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(flightToolbarProvider.notifier);
    showMenu<FlightFilter>(
      context: context,
      position: const RelativeRect.fromLTRB(280, 120, 0, 0),
      color: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      items: const [
        PopupMenuItem(value: FlightFilter.all, child: Text('Todas')),
        PopupMenuItem(value: FlightFilter.withNotes, child: Text('Con notas')),
        PopupMenuItem(value: FlightFilter.empty, child: Text('Vacías')),
        PopupMenuItem(value: FlightFilter.pinned, child: Text('Fijadas')),
      ],
    ).then((f) {
      if (f != null) notifier.setFilter(f);
    });
  }

  void _showSortMenu(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(flightToolbarProvider.notifier);
    showMenu<FlightSort>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 120, 0, 0),
      color: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      items: [
        const PopupMenuItem(value: FlightSort.recent, child: Text('Reciente')),
        const PopupMenuItem(value: FlightSort.alphabetical, child: Text('A–Z')),
        const PopupMenuItem(value: FlightSort.count, child: Text('Más notas')),
      ],
    ).then((s) {
      if (s != null) notifier.setSort(s);
    });
  }
}

// ─── Search bar (in header) — opens dialog ────────────────────────────────

class _SearchBar extends ConsumerWidget {
  final int totalNotes;
  const _SearchBar({required this.totalNotes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSearch(context, ref),
      child: Container(
        width: 280,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Row(
          children: [
            Icon(YuLiIcons.search, size: 16, color: yInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Buscar en $totalNotes notas…',
                style: yBody(size: 13, weight: FontWeight.w500, color: yMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearch(BuildContext context, WidgetRef ref) {
    return showDialog(context: context, builder: (_) => const _SearchDialog());
  }
}

class _SearchDialog extends ConsumerStatefulWidget {
  const _SearchDialog();

  @override
  ConsumerState<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<_SearchDialog> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits =
        _query.isEmpty
            ? <NoteSearchHit>[]
            : ref.watch(globalNoteSearchProvider(_query)).valueOrNull ?? [];

    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.all(60),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(YuLiIcons.search, color: yInk),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: ySans(
                      size: 18,
                      weight: FontWeight.w500,
                      color: yInk,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar en todas las notas…',
                      hintStyle: ySans(
                        size: 18,
                        weight: FontWeight.w500,
                        color: yMuted,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isCollapsed: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: yBorderStrong),
            const SizedBox(height: 8),
            Expanded(
              child:
                  hits.isEmpty
                      ? Center(
                        child: Text(
                          _query.isEmpty ? '' : 'Sin resultados',
                          style: yBody(size: 14, color: yMuted),
                        ),
                      )
                      : ListView.separated(
                        itemBuilder: (_, i) {
                          final h = hits[i];
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              Navigator.pop(context);
                              ref
                                  .read(pendingNoteNavigationProvider.notifier)
                                  .state = h.note.id;
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.note.title ?? '(sin título)',
                                    style: ySans(
                                      size: 15,
                                      weight: FontWeight.w700,
                                      color: yInk,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    h.folderName,
                                    style: yMono(
                                      size: 10,
                                      tracking: 1.2,
                                      color: yMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        separatorBuilder:
                            (_, _) => Container(height: 1, color: yBorderSoft),
                        itemCount: hits.length,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Folder grid / list ───────────────────────────────────────────────────

class _FolderGrid extends ConsumerWidget {
  final List<Folder> folders;
  final Map<int, int> counts;

  const _FolderGrid({required this.folders, required this.counts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolbar = ref.watch(flightToolbarProvider);
    final pinned = ref.watch(pinnedFoldersProvider);

    return LayoutBuilder(
      builder: (ctx, c) {
        final cols =
            c.maxWidth >= 1100
                ? 3
                : c.maxWidth >= 700
                ? 2
                : 1;

        if (toolbar.view == FlightView.list) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
            itemBuilder:
                (_, i) => _FolderListRow(
                  folder: folders[i],
                  count: counts[folders[i].id] ?? 0,
                  pinned: pinned.contains(folders[i].id),
                ),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemCount: folders.length,
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 264,
          ),
          itemBuilder: (_, i) {
            if (i >= folders.length) {
              return _NewFolderTile();
            }
            return _FolderCard(
              folder: folders[i],
              count: counts[folders[i].id] ?? 0,
              pinned: pinned.contains(folders[i].id),
            );
          },
          itemCount: folders.length + 1,
        );
      },
    );
  }
}

// ─── Folder card (rich) ───────────────────────────────────────────────────

class _FolderCard extends ConsumerWidget {
  final Folder folder;
  final int count;
  final bool pinned;

  const _FolderCard({
    required this.folder,
    required this.count,
    required this.pinned,
  });

  String _lastEditLabel(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    if (diff.inDays < 30) return 'hace ${(diff.inDays / 7).floor()} sem';
    return 'hace ${(diff.inDays / 30).floor()} m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrichmentAsync = ref.watch(folderEnrichmentProvider(folder.id));
    final enrichment = enrichmentAsync.valueOrNull;

    final lastEdit = enrichment?.lastEditedAt;
    final recents = enrichment?.recentNotes ?? [];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FolderDetailScreen(folder: folder),
            ),
          ),
      onLongPress:
          () => _showFolderContextMenu(context, ref, folder, pinned, count),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            left: 8,
            top: 8,
            right: -8,
            bottom: -8,
            child: CustomPaint(painter: _FolderShapePainter(color: yInk)),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _FolderShapePainter(color: folder.color, border: true),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 64, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          folder.name,
                          style: ySans(
                            size: 28,
                            weight: FontWeight.w700,
                            color: yCream,
                            height: 1.0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'NOTAS',
                            style: yMono(
                              size: 9,
                              weight: FontWeight.w700,
                              tracking: 1.2,
                              color: yCream.withValues(alpha: 0.85),
                            ),
                          ),
                          Text(
                            count.toString().padLeft(2, '0'),
                            style: yMono(
                              size: 24,
                              weight: FontWeight.w700,
                              tracking: 1.0,
                              color: yCream,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastEdit == null
                        ? 'SIN NOTAS'
                        : 'EDITADA ${_lastEditLabel(lastEdit).toUpperCase()}',
                    style: yMono(
                      size: 10,
                      tracking: 1.4,
                      color: yCream.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(height: 1.5, color: yCream.withValues(alpha: 0.32)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < recents.take(3).length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Opacity(
                              opacity: 1 - i * 0.18,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    YuLiIcons.chevronRight,
                                    size: 12,
                                    color: yCream.withValues(alpha: 0.72),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      recents[i].title ?? 'Sin titulo',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: yBody(
                                        size: 12,
                                        color: yCream,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(height: 2, color: yBorderStrong),
                  SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ABRIR CARPETA',
                          style: yMono(
                            size: 10,
                            weight: FontWeight.w700,
                            tracking: 1.4,
                            color: yCream.withValues(alpha: 0.85),
                          ),
                        ),
                        Icon(YuLiIcons.arrowRight, size: 20, color: yCream),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (pinned)
            Positioned(
              top: 44,
              right: 18,
              child: Transform.rotate(
                angle: 0.035,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
                  decoration: BoxDecoration(
                    color: yAmber2,
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(YuLiIcons.star, size: 10, color: yInk),
                      const SizedBox(width: 4),
                      Text(
                        'FIJADA',
                        style: yMono(
                          size: 9,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yInk,
                        ),
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

class _FolderShapePainter extends CustomPainter {
  final Color color;
  final bool border;

  const _FolderShapePainter({required this.color, this.border = false});

  @override
  void paint(Canvas canvas, Size size) {
    final bodyTop = size.height * 0.17;
    final tabEnd = size.width * 0.40;
    final tabDrop = size.height * 0.105;
    final path =
        Path()
          ..moveTo(0, bodyTop)
          ..lineTo(16, bodyTop - tabDrop)
          ..lineTo(tabEnd, bodyTop - tabDrop)
          ..lineTo(tabEnd + 34, bodyTop)
          ..lineTo(size.width, bodyTop)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = color);
    if (border) {
      canvas.drawPath(
        path,
        Paint()
          ..color = yBorderStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = yLineMid
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FolderShapePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.border != border;
}

class _FolderListRow extends ConsumerWidget {
  final Folder folder;
  final int count;
  final bool pinned;

  const _FolderListRow({
    required this.folder,
    required this.count,
    required this.pinned,
  });

  void _showFolderListMenu(BuildContext context, WidgetRef ref) {
    _showFolderContextMenu(context, ref, folder, pinned, count);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FolderDetailScreen(folder: folder),
            ),
          ),
      onLongPress: () => _showFolderListMenu(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: folder.color,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Row(
          children: [
            if (pinned) ...[
              Text(
                '★',
                style: TextStyle(fontSize: 14, color: yAmber2, height: 1.0),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                folder.name,
                style: ySans(size: 18, weight: FontWeight.w700, color: yCream),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              count.toString().padLeft(2, '0'),
              style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: yCream.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '→',
              style: TextStyle(fontSize: 16, color: yCream, height: 1.0),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewFolderTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          () => showDialog(
            context: context,
            builder: (_) => const NewFolderDialog(),
          ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: yBorderStrong,
            width: yLineMid,
            style: BorderStyle.solid,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: Text(
                '+',
                style: TextStyle(fontSize: 32, color: yInk, height: 1.0),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Nueva carpeta',
              style: ySans(
                size: 16,
                weight: FontWeight.w700,
                letterSpacing: -0.3,
                color: yInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ELIGE UN COLOR',
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showFolderContextMenu(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
  bool pinned,
  int noteCount,
) {
  final repo = ref.read(folderRepositoryProvider);
  showModalBottomSheet(
    context: context,
    backgroundColor: yCream,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder:
        (ctx) => YuLiActionSheet(
          title: folder.name,
          badge: 'Carpeta',
          badgeIcon: YuLiIcons.folder,
          accent: folder.color,
          children: [
            YuLiActionTile(
              icon: YuLiIcons.pen,
              label: 'Editar',
              accent: folder.color,
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder:
                      (_) => EditItemDialog(
                        title: 'Renombrar carpeta',
                        initialName: folder.name,
                        initialColor: folder.color,
                        onSave: (name, color) async {
                          await repo.update(
                            folder.copyWith(name: name, color: color),
                          );
                        },
                        onDelete: () async {
                          await repo.softDelete(folder.id);
                        },
                      ),
                );
              },
            ),
            YuLiActionTile(
              icon: YuLiIcons.palette,
              label: 'Cambiar color',
              accent: folder.color,
              onTap: () async {
                Navigator.pop(ctx);
                final selected = await showFolderColorDialog(
                  context,
                  title: 'Cambiar color de carpeta',
                  folderName: folder.name,
                  noteCount: noteCount,
                  initialColor: folder.color,
                );
                if (selected != null) {
                  await repo.update(folder.copyWith(color: selected));
                }
              },
            ),
            YuLiActionTile(
              icon: YuLiIcons.star,
              label: pinned ? 'Desfijar' : 'Fijar',
              accent: folder.color,
              onTap: () {
                Navigator.pop(ctx);
                ref.read(pinnedFoldersProvider.notifier).toggle(folder.id);
              },
            ),
            YuLiActionTile(
              icon: YuLiIcons.trash,
              label: 'Eliminar',
              accent: folder.color,
              destructive: true,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder:
                      (d) => AlertDialog(
                        backgroundColor: yCream,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        title: Text(
                          'Eliminar carpeta',
                          style: ySans(size: 18, weight: FontWeight.w700),
                        ),
                        content: Text(
                          '¿Eliminar "${folder.name}"? Se moverá a la papelera.',
                          style: yBody(size: 14),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(d, true),
                            child: const Text('Eliminar'),
                          ),
                        ],
                      ),
                );
                if (ok == true) await repo.softDelete(folder.id);
              },
            ),
          ],
        ),
  );
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          'SIN CARPETAS — toca + para crear una',
          style: yMono(size: 11, color: yMuted, tracking: 1.4),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
