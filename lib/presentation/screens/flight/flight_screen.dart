import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/flight_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/note_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/folder.dart';
import 'folder_detail_screen.dart';
import 'note_editor_screen.dart';
import 'new_folder_dialog.dart';

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
      MaterialPageRoute(
        builder: (_) => FolderDetailScreen(folder: folder),
      ),
    );
  }

  Future<void> _navigateToPendingNote(int noteId) async {
    final note = await ref.read(noteRepositoryProvider).getById(noteId);
    if (note == null || !mounted) return;
    final folder =
        await ref.read(folderRepositoryProvider).getById(note.folderId);
    if (folder == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(note: note, folder: folder),
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

    final sorted = _sortFolders(folders, counts, pinned, toolbar.sort);

    return Column(
      children: [
        ModeHeader(
          mode: 'FLIGHT',
          subtitle:
              'MODO NOTAS · ${folders.length} CARPETAS · $totalNotes NOTAS',
          color: yFlight,
          onBack: () =>
              ref.read(currentModeProvider.notifier).state = AppMode.home,
          headerRight: [
            _SearchBar(totalNotes: totalNotes),
            IconSquareBtn(icon: Icons.help_outline),
          ],
        ),
        const _Toolbar(),
        Expanded(
          child: Container(
            color: yCream,
            child: sorted.isEmpty
                ? _Empty()
                : _FolderGrid(folders: sorted, counts: counts),
          ),
        ),
      ],
    );
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
        border: Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showDialog(
              context: context,
              builder: (_) => const NewFolderDialog(),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: yFlight,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('+',
                      style: TextStyle(
                          fontSize: 18, color: yCream, height: 1.0)),
                  const SizedBox(width: 8),
                  Text('NUEVA CARPETA',
                      style: yBody(
                        size: 13,
                        weight: FontWeight.w700,
                        color: yCream,
                      ).copyWith(letterSpacing: 1.2)),
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
            value: 'TODAS',
            onTap: () {},
          ),
          const Spacer(),
          ViewToggleBtn(
            glyph: '▣',
            active: toolbar.view == FlightView.grid,
            onTap: () => notifier.setView(FlightView.grid),
          ),
          const SizedBox(width: 4),
          ViewToggleBtn(
            glyph: '≡',
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

  void _showSortMenu(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(flightToolbarProvider.notifier);
    showMenu<FlightSort>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 120, 0, 0),
      color: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      items: [
        const PopupMenuItem(
            value: FlightSort.recent, child: Text('Reciente')),
        const PopupMenuItem(
            value: FlightSort.alphabetical, child: Text('A–Z')),
        const PopupMenuItem(
            value: FlightSort.count, child: Text('Más notas')),
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
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: yInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'buscar en $totalNotes notas…',
                style: yBody(
                  size: 13,
                  weight: FontWeight.w500,
                  color: yMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: yMuted, width: 1.5),
              ),
              child: Text('⌘ K',
                  style: yMono(
                    size: 10,
                    tracking: 1,
                    color: yMuted,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSearch(BuildContext context, WidgetRef ref) {
    return showDialog(
      context: context,
      builder: (_) => const _SearchDialog(),
    );
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
    final hits = _query.isEmpty
        ? <NoteSearchHit>[]
        : ref.watch(globalNoteSearchProvider(_query)).valueOrNull ?? [];

    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.all(60),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: yInk, width: yLineHeavy),
        ),
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.search, color: yInk),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: ySans(
                        size: 18, weight: FontWeight.w500, color: yInk),
                    decoration: InputDecoration(
                      hintText: 'Buscar en todas las notas…',
                      hintStyle: ySans(
                          size: 18,
                          weight: FontWeight.w500,
                          color: yMuted),
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
            Container(height: 1, color: yInk),
            const SizedBox(height: 8),
            Expanded(
              child: hits.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty ? '' : 'Sin resultados',
                        style: yBody(
                            size: 14, color: yMuted),
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
                                Text(h.note.title ?? '(sin título)',
                                    style: ySans(
                                      size: 15,
                                      weight: FontWeight.w700,
                                      color: yInk,
                                    )),
                                const SizedBox(height: 2),
                                Text(h.folderName,
                                    style: yMono(
                                      size: 10,
                                      tracking: 1.2,
                                      color: yMuted,
                                    )),
                              ],
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (_, _) => Container(
                        height: 1,
                        color: yInk.withValues(alpha: 0.15),
                      ),
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
        final cols = c.maxWidth >= 1100
            ? 3
            : c.maxWidth >= 700
                ? 2
                : 1;

        if (toolbar.view == FlightView.list) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
            itemBuilder: (_, i) => _FolderListRow(
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
            mainAxisExtent: 200,
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
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FolderDetailScreen(folder: folder)),
      ),
      onLongPress: () =>
          ref.read(pinnedFoldersProvider.notifier).toggle(folder.id),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: folder.color,
              border: Border.all(color: yInk, width: yLineHeavy),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              folder.name,
                              style: ySans(
                                size: 28,
                                weight: FontWeight.w700,
                                letterSpacing: -0.8,
                                color: yCream,
                                height: 1.0,
                              ),
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
                    ],
                  ),
                ),
                Container(
                    height: 2,
                    color: yCream.withValues(alpha: 0.25)),
                // Recent notes preview
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < recents.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Opacity(
                              opacity: 1 - i * 0.18,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('▸',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontFamily: 'monospace',
                                        color: yCream.withValues(alpha: 0.7),
                                      )),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      recents[i].title ?? '(sin título)',
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
                ),
                // Footer enter affordance
                Container(
                    height: 2,
                    color: yCream.withValues(alpha: 0.25)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ABRIR CARPETA',
                          style: yMono(
                            size: 10,
                            weight: FontWeight.w700,
                            tracking: 1.4,
                            color: yCream.withValues(alpha: 0.85),
                          )),
                      Text('→',
                          style: TextStyle(
                              fontSize: 16, color: yCream, height: 1.0)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (pinned)
            Positioned(
              top: -2,
              right: 16,
              child: Transform.rotate(
                angle: 0.035,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
                  decoration: BoxDecoration(
                    color: yAmber2,
                    border: Border.all(color: yInk, width: yLineThin),
                  ),
                  child: Text('★ FIJADA',
                      style: yMono(
                        size: 9,
                        weight: FontWeight.w700,
                        tracking: 1.4,
                        color: yInk,
                      )),
                ),
              ),
            ),
        ],
      ),
    );
  }
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FolderDetailScreen(folder: folder)),
      ),
      onLongPress: () =>
          ref.read(pinnedFoldersProvider.notifier).toggle(folder.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: folder.color,
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Row(
          children: [
            if (pinned) ...[
              Text('★',
                  style:
                      TextStyle(fontSize: 14, color: yAmber2, height: 1.0)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                folder.name,
                style: ySans(
                  size: 18,
                  weight: FontWeight.w700,
                  color: yCream,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(count.toString().padLeft(2, '0'),
                style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.2,
                  color: yCream.withValues(alpha: 0.85),
                )),
            const SizedBox(width: 8),
            Text('→',
                style: TextStyle(fontSize: 16, color: yCream, height: 1.0)),
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
      onTap: () => showDialog(
        context: context,
        builder: (_) => const NewFolderDialog(),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: yInk,
            width: yLineHeavy,
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
                border: Border.all(color: yInk, width: yLineHeavy),
              ),
              child: Text('+',
                  style: TextStyle(
                      fontSize: 32, color: yInk, height: 1.0)),
            ),
            const SizedBox(height: 10),
            Text('Nueva carpeta',
                style: ySans(
                  size: 16,
                  weight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: yInk,
                )),
            const SizedBox(height: 6),
            Text('ELIGE UN COLOR',
                style: yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yMuted,
                )),
          ],
        ),
      ),
    );
  }
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
