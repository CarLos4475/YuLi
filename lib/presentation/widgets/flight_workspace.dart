import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/folder.dart';
import '../../domain/models/note.dart';
import '../../domain/models/note_block.dart';
import '../providers/database_providers.dart';
import '../providers/flight_workspace_providers.dart';
import '../screens/flight/pin_dialog.dart';
import '../theme/lab_icons.dart';
import 'yuli_design.dart';

FlightWorkspaceTarget flightWorkspaceTarget({
  required Note note,
  required Folder folder,
  DrawingBlock? canvas,
  int? canvasOrdinal,
}) {
  final noteLabel =
      note.displayTitle.trim().isEmpty
          ? _kindFallback(note.kind)
          : note.displayTitle.trim();
  final canvasLabel =
      canvas == null
          ? null
          : canvas.name?.trim().isNotEmpty == true
          ? canvas.name!.trim()
          : 'Pizarra ${canvasOrdinal ?? canvas.position + 1}';
  return FlightWorkspaceTarget(
    noteId: note.id,
    folderId: folder.id,
    canvasBlockId: canvas?.id,
    kind: note.kind,
    label: canvasLabel == null ? noteLabel : '$noteLabel · $canvasLabel',
    folderLabel: folder.name,
  );
}

String flightWikiLinkLabel(FlightWorkspaceTarget target) {
  var label = target.label;
  if (target.canvasBlockId != null) {
    final separator = label.lastIndexOf(' · ');
    if (separator >= 0) {
      label =
          '${label.substring(0, separator)}#${label.substring(separator + 3)}';
    }
  }
  final clean =
      label
          .replaceAll(RegExp(r'[\[\]\r\n]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  return clean.length <= 120 ? clean : clean.substring(0, 120).trimRight();
}

Future<void> showFlightWorkspace({
  required BuildContext context,
  required WidgetRef ref,
  required FlightWorkspaceTarget current,
  required Color accent,
  required ValueChanged<FlightWorkspaceTarget> onOpen,
}) async {
  final target = await showGeneralDialog<FlightWorkspaceTarget>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar explorador',
    barrierColor: yInk.withValues(alpha: 0.34),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder:
        (_, _, _) => Align(
          alignment: Alignment.centerLeft,
          child: _FlightWorkspacePanel(current: current, accent: accent),
        ),
    transitionBuilder:
        (_, animation, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
  );
  if (target == null || !context.mounted) return;
  ref.read(flightWorkspaceTabsProvider.notifier).open(target);
  onOpen(target);
}

class FlightWorkspaceTabsBar extends ConsumerWidget {
  final FlightWorkspaceTarget current;
  final Color accent;
  final ValueChanged<FlightWorkspaceTarget> onOpen;
  final VoidCallback onExplore;

  const FlightWorkspaceTabsBar({
    super.key,
    required this.current,
    required this.accent,
    required this.onOpen,
    required this.onExplore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(flightWorkspaceTabsProvider);
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineThin),
        ),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Abrir explorador',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onExplore,
              child: Container(
                width: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: yBorderStrong, width: yLineThin),
                  ),
                ),
                child: Icon(YuLiIcons.folder, size: 18, color: accent),
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              buildDefaultDragHandles: false,
              itemCount: tabs.length,
              onReorder: ref.read(flightWorkspaceTabsProvider.notifier).reorder,
              proxyDecorator:
                  (child, _, _) => Material(
                    color: const Color(0x00000000),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: yInk.withValues(alpha: 0.18),
                            offset: const Offset(3, 3),
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  ),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final selected = tab.key == current.key;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(tab.key),
                  index: index,
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: tab.label,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: selected ? null : () => onOpen(tab),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 118,
                          maxWidth: 220,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: selected ? accent : yCream,
                          border: const Border(
                            right: BorderSide(
                              color: yBorderStrong,
                              width: yLineThin,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _kindIcon(tab.kind),
                              size: 14,
                              color: selected ? yCream : yMuted,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                tab.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ySans(
                                  size: 12,
                                  weight:
                                      selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                  color: selected ? yCream : yInk2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                final next =
                                    selected && tabs.length > 1
                                        ? tabs[index == tabs.length - 1
                                            ? index - 1
                                            : index + 1]
                                        : null;
                                ref
                                    .read(flightWorkspaceTabsProvider.notifier)
                                    .close(tab);
                                if (!selected) return;
                                if (next != null) {
                                  onOpen(next);
                                } else {
                                  Navigator.maybePop(context);
                                }
                              },
                              child: Icon(
                                YuLiIcons.close,
                                size: 13,
                                color: selected ? yCream : yMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FlightWorkspacePanel extends ConsumerStatefulWidget {
  final FlightWorkspaceTarget current;
  final Color accent;

  const _FlightWorkspacePanel({required this.current, required this.accent});

  @override
  ConsumerState<_FlightWorkspacePanel> createState() =>
      _FlightWorkspacePanelState();
}

class _FlightWorkspacePanelState extends ConsumerState<_FlightWorkspacePanel> {
  late Future<_WorkspaceSnapshot> _snapshot;
  final _queryController = TextEditingController();
  Offset? _dragPointerStart;
  double _dragDistance = 0;
  bool _workspaceDragActive = false;
  _WorkspaceNotice? _notice;

  @override
  void initState() {
    super.initState();
    ref
        .read(flightWorkspaceExpansionProvider.notifier)
        .ensureExpanded('folder:${widget.current.folderId}');
    _snapshot = _loadSnapshot();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<_WorkspaceSnapshot> _loadSnapshot() async {
    final folders = await ref.read(folderRepositoryProvider).getActive();
    final noteLists = await Future.wait(
      folders.map(
        (folder) => ref.read(noteRepositoryProvider).getByFolder(folder.id),
      ),
    );
    final notes = noteLists.expand((items) => items).toList();
    final blocks = await ref
        .read(noteBlockRepositoryProvider)
        .getByNoteIds(notes.map((note) => note.id).toList());
    final snapshot = _WorkspaceSnapshot.build(
      folders: folders,
      notes: notes,
      blocks: blocks,
      current: widget.current,
    );
    final availableKeys = {
      for (final targets in snapshot.targetsByFolder.values)
        for (final target in targets) target.key,
    };
    if (mounted) {
      ref.read(flightWorkspaceTabsProvider.notifier).retainKeys(availableKeys);
    }
    return snapshot;
  }

  Set<int> _branchIds(_WorkspaceSnapshot data, int noteId) {
    final childrenByParent = <int, List<int>>{};
    for (final note in data.notesById.values) {
      final parentId = note.parentNoteId;
      if (parentId == null) continue;
      childrenByParent.putIfAbsent(parentId, () => []).add(note.id);
    }
    final result = <int>{};
    final pending = <int>[noteId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!result.add(current)) continue;
      pending.addAll(childrenByParent[current] ?? const []);
    }
    return result;
  }

  _WorkspaceDropValidity _dropValidity(
    _WorkspaceSnapshot data,
    _WorkspaceDragData drag,
    _WorkspaceDropDestination destination,
  ) {
    final source = data.notesById[drag.noteId];
    if (source == null || !source.isWikiCreated) {
      return const _WorkspaceDropValidity.invalid('SOLO ELEMENTOS [[ ]]');
    }
    final branchIds = _branchIds(data, source.id);
    if (destination.parentNoteId != null &&
        branchIds.contains(destination.parentNoteId)) {
      return const _WorkspaceDropValidity.invalid('NO DENTRO DE SÍ MISMO');
    }
    if (destination.beforeNoteId == source.id) {
      return const _WorkspaceDropValidity.invalid('YA ESTÁ AQUÍ');
    }
    final branchLabels =
        branchIds
            .map((id) => data.notesById[id]?.displayTitle ?? '')
            .map(_normalize)
            .where((label) => label.isNotEmpty)
            .toSet();
    final collision =
        source.folderId != destination.folderId &&
        data.notesById.values.any(
          (note) =>
              note.isActive &&
              note.folderId == destination.folderId &&
              !branchIds.contains(note.id) &&
              branchLabels.contains(_normalize(note.displayTitle)),
        );
    if (collision) {
      return const _WorkspaceDropValidity.invalid('NOMBRE REPETIDO');
    }
    return _WorkspaceDropValidity.valid(destination.actionLabel);
  }

  Future<void> _moveWorkspaceChild(
    _WorkspaceDragData drag,
    _WorkspaceDropDestination destination,
  ) async {
    try {
      final affectedIds = await ref
          .read(noteRepositoryProvider)
          .moveWorkspaceBranch(
            drag.noteId,
            folderId: destination.folderId,
            parentNoteId: destination.parentNoteId,
            parentCanvasBlockId: destination.parentCanvasBlockId,
            beforeNoteId: destination.beforeNoteId,
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ref
          .read(flightWorkspaceExpansionProvider.notifier)
          .ensureExpanded('folder:${destination.folderId}');
      if (destination.parentNoteId != null) {
        ref
            .read(flightWorkspaceExpansionProvider.notifier)
            .ensureExpanded(
              'target:${destination.parentNoteId}:${destination.parentCanvasBlockId ?? 0}',
            );
      }
      final nextSnapshot = await _loadSnapshot();
      if (!mounted) return;
      final targetsByKey = {
        for (final targets in nextSnapshot.targetsByFolder.values)
          for (final target in targets) target.key: target,
      };
      final tabs = [...ref.read(flightWorkspaceTabsProvider)];
      for (final tab in tabs) {
        final refreshed = targetsByKey[tab.key];
        if (refreshed != null) {
          ref.read(flightWorkspaceTabsProvider.notifier).refresh(refreshed);
        }
      }
      final refreshedCurrent = targetsByKey[widget.current.key];
      if (affectedIds.contains(widget.current.noteId) &&
          refreshedCurrent != null) {
        _open(refreshedCurrent);
        return;
      }
      setState(() {
        _snapshot = Future.value(nextSnapshot);
        _notice = _WorkspaceNotice(
          'Movido a ${destination.destinationLabel}',
          isError: false,
        );
      });
    } on StateError catch (error) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _notice = _WorkspaceNotice(error.message.toString(), isError: true);
      });
    }
  }

  void _open(FlightWorkspaceTarget target) {
    Navigator.pop(context, target);
  }

  Future<void> _manageWorkspaceChild(int noteId) async {
    HapticFeedback.mediumImpact();
    final notes = await ref.read(noteRepositoryProvider).watchAllActive().first;
    final noteById = {for (final note in notes) note.id: note};
    final note = noteById[noteId];
    if (note == null || !note.isWikiCreated || !mounted) return;
    final childrenByParent = <int, List<int>>{};
    for (final item in notes) {
      final parentId = item.parentNoteId;
      if (parentId == null) continue;
      childrenByParent.putIfAbsent(parentId, () => []).add(item.id);
    }
    final branchIds = <int>[];
    final visited = <int>{};
    final pending = <int>[noteId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      branchIds.add(current);
      pending.addAll(childrenByParent[current] ?? const []);
    }
    final descendants = branchIds.length - 1;
    final choice = await showDialog<_WorkspaceDeleteChoice>(
      context: context,
      builder:
          (dialogContext) => PinDialogShell(
            icon: YuLiIcons.trash,
            title: 'GESTIONAR ELEMENTO',
            accent: widget.accent,
            footer: Row(
              children: [
                const Spacer(),
                PinGhostButton(
                  label: 'CANCELAR',
                  onTap: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  note.displayTitle,
                  style: ySans(size: 18, weight: FontWeight.w800, color: yInk),
                ),
                const SizedBox(height: 8),
                Text(
                  descendants == 0
                      ? 'Este elemento se enviará a Papelera.'
                      : 'Este elemento contiene $descendants ${descendants == 1 ? 'descendiente' : 'descendientes'}. Elige qué debe ocurrir con ellos.',
                  style: yBody(size: 12, color: yMuted, height: 1.4),
                ),
                const SizedBox(height: 14),
                _WorkspaceDeleteAction(
                  icon: YuLiIcons.trash,
                  title: descendants == 0 ? 'ELIMINAR' : 'ELIMINAR RAMA',
                  description:
                      descendants == 0
                          ? 'Enviar este elemento a Papelera.'
                          : 'Enviar este elemento y sus $descendants descendientes a Papelera.',
                  accent: widget.accent,
                  onTap:
                      () => Navigator.pop(
                        dialogContext,
                        _WorkspaceDeleteChoice.branch,
                      ),
                ),
                if (descendants > 0) ...[
                  const SizedBox(height: 12),
                  _WorkspaceDeleteAction(
                    icon: YuLiIcons.folder,
                    title: 'CONSERVAR HIJOS',
                    description:
                        'Eliminar solo este elemento. Sus hijos directos aparecerán en la carpeta y conservarán sus propias ramas.',
                    accent: widget.accent,
                    onTap:
                        () => Navigator.pop(
                          dialogContext,
                          _WorkspaceDeleteChoice.keepChildren,
                        ),
                  ),
                ],
              ],
            ),
          ),
    );
    if (choice == null || !mounted) return;
    final repository = ref.read(noteRepositoryProvider);
    final removedIds = switch (choice) {
      _WorkspaceDeleteChoice.branch => await repository.softDeleteBranch(
        noteId,
      ),
      _WorkspaceDeleteChoice.keepChildren => <int>[noteId],
    };
    if (choice == _WorkspaceDeleteChoice.keepChildren) {
      await repository.softDeleteKeepingChildren(noteId);
    }
    if (!mounted || removedIds.isEmpty) return;
    _closeRemovedNotes(removedIds.toSet());
  }

  void _closeRemovedNotes(Set<int> noteIds) {
    final tabs = ref.read(flightWorkspaceTabsProvider);
    final currentIndex = tabs.indexWhere(
      (target) => target.key == widget.current.key,
    );
    final surviving =
        tabs.where((target) => !noteIds.contains(target.noteId)).toList();
    for (final noteId in noteIds) {
      ref.read(flightWorkspaceTabsProvider.notifier).closeNote(noteId);
    }
    if (!noteIds.contains(widget.current.noteId)) {
      setState(() => _snapshot = _loadSnapshot());
      return;
    }
    if (surviving.isNotEmpty) {
      final nextIndex = math.min(
        math.max(currentIndex, 0),
        surviving.length - 1,
      );
      _open(surviving[nextIndex]);
      return;
    }
    final navigator = Navigator.of(context);
    navigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted) navigator.maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(460.0, MediaQuery.sizeOf(context).width * 0.92);
    return Material(
      color: const Color(0x00000000),
      child: SafeArea(
        child: Container(
          width: width,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(
              right: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
          ),
          child: Column(
            children: [
              _panelHeader(),
              _searchField(),
              Expanded(
                child: FutureBuilder<_WorkspaceSnapshot>(
                  future: _snapshot,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(color: widget.accent),
                      );
                    }
                    return _panelBody(snapshot.data!);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: widget.accent,
        border: const Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      child: Row(
        children: [
          const Icon(YuLiIcons.gitGraph, color: yCream, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EXPLORADOR',
                  style: ySans(
                    size: 20,
                    weight: FontWeight.w800,
                    color: yCream,
                  ),
                ),
                Text(
                  widget.current.folderLabel.toUpperCase(),
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.2,
                    color: yCream.withValues(alpha: 0.76),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.close, color: yInk, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: TextField(
        controller: _queryController,
        onChanged: (_) => setState(() {}),
        textCapitalization: TextCapitalization.sentences,
        style: ySans(size: 14, color: yInk),
        decoration: InputDecoration(
          prefixIcon: const Icon(YuLiIcons.search, color: yMuted, size: 17),
          hintText: 'Buscar notas y pizarras',
          hintStyle: ySans(size: 14, color: yMuted),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  Widget _panelBody(_WorkspaceSnapshot data) {
    final query = _normalize(_queryController.text);
    final folders =
        data.folders.where((folder) {
          if (query.isEmpty) return true;
          if (_normalize(folder.name).contains(query)) return true;
          return data.targetsByFolder[folder.id]?.any(
                (target) => _normalize(target.label).contains(query),
              ) ??
              false;
        }).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder:
              (child, animation) => SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: FadeTransition(opacity: animation, child: child),
              ),
          child:
              _notice == null
                  ? const SizedBox.shrink(key: ValueKey('no-notice'))
                  : _WorkspaceNoticeBanner(
                    key: ValueKey('${_notice!.message}:${_notice!.isError}'),
                    notice: _notice!,
                    accent: widget.accent,
                    onClose: () => setState(() => _notice = null),
                  ),
        ),
        _tabsSection(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 7),
          child: Text(
            'CARPETAS',
            style: yMono(
              size: 10,
              weight: FontWeight.w800,
              tracking: 1.3,
              color: yMuted,
            ),
          ),
        ),
        for (final folder in folders) _folderSection(folder, data, query),
      ],
    );
  }

  Widget _tabsSection() {
    final tabs = ref.watch(flightWorkspaceTabsProvider);
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 7),
          child: Text(
            'ABIERTAS',
            style: yMono(
              size: 10,
              weight: FontWeight.w800,
              tracking: 1.3,
              color: yMuted,
            ),
          ),
        ),
        for (final tab in tabs)
          _targetRow(
            tab,
            selected: tab.key == widget.current.key,
            showFolder: true,
            onClose: () => _closeTab(tab, tabs),
          ),
      ],
    );
  }

  Widget _folderSection(Folder folder, _WorkspaceSnapshot data, String query) {
    final targets = data.targetsByFolder[folder.id] ?? const [];
    final visibleTargets =
        query.isEmpty
            ? targets
            : targets
                .where((target) => _normalize(target.label).contains(query))
                .toList();
    final expansionKey = 'folder:${folder.id}';
    final expanded =
        query.isNotEmpty ||
        ref.watch(flightWorkspaceExpansionProvider).contains(expansionKey);
    final folderDestination = _WorkspaceDropDestination(
      key: 'folder:${folder.id}',
      folderId: folder.id,
      actionLabel: 'SOLTAR EN CARPETA',
      destinationLabel: folder.name,
    );
    return Column(
      children: [
        _dropTarget(
          data: data,
          destination: folderDestination,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                query.isNotEmpty
                    ? null
                    : () => ref
                        .read(flightWorkspaceExpansionProvider.notifier)
                        .toggle(expansionKey),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: yBorderSoft, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    expanded ? YuLiIcons.chevronDown : YuLiIcons.chevronRight,
                    size: 15,
                    color: yMuted,
                  ),
                  const SizedBox(width: 5),
                  Icon(YuLiIcons.folder, size: 17, color: folder.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ySans(
                        size: 14,
                        weight:
                            folder.id == widget.current.folderId
                                ? FontWeight.w800
                                : FontWeight.w600,
                        color: yInk,
                      ),
                    ),
                  ),
                  Text(
                    '${targets.length}',
                    style: yMono(size: 9, color: yMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          if (query.isNotEmpty)
            for (final target in visibleTargets)
              _draggableWorkspaceChild(
                data: data,
                noteId: target.noteId,
                label:
                    data.notesById[target.noteId]?.displayTitle ?? target.label,
                child: _dropTarget(
                  data: data,
                  destination: _destinationForTarget(target),
                  child: _targetRow(
                    target,
                    selected: target.key == widget.current.key,
                    indent: 18,
                  ),
                ),
              )
          else
            for (final node in data.rootsByFolder[folder.id] ?? const [])
              _workspaceTree(node, data, const {}, 18),
      ],
    );
  }

  Widget _workspaceTree(
    FlightWorkspaceTreeNode node,
    _WorkspaceSnapshot data,
    Set<String> ancestors,
    double indent,
  ) {
    final cyclic = ancestors.contains(node.key);
    final expansionKey = 'target:${node.key}';
    final expanded = ref
        .watch(flightWorkspaceExpansionProvider)
        .contains(expansionKey);
    final nextAncestors = {...ancestors, node.key};
    final canExpand = node.children.isNotEmpty && !cyclic;
    final note = node.noteId == null ? null : data.notesById[node.noteId];
    final target = node.target;
    final Widget row;
    if (target != null) {
      row = _dropTarget(
        data: data,
        destination: _destinationForTarget(target),
        child: _targetRow(
          target,
          label: node.label,
          selected: target.key == widget.current.key,
          indent: indent,
          expandable: canExpand,
          expanded: expanded,
          onToggle:
              !canExpand
                  ? null
                  : () => ref
                      .read(flightWorkspaceExpansionProvider.notifier)
                      .toggle(expansionKey),
        ),
      );
    } else {
      row = _dropTarget(
        data: data,
        destination: _WorkspaceDropDestination.invalid(
          key: 'container:${node.key}',
          folderId: node.folderId,
          label: 'ELIGE UNA PIZARRA',
        ),
        child: _containerRow(
          node,
          indent: indent,
          expanded: expanded,
          onToggle:
              !canExpand
                  ? null
                  : () => ref
                      .read(flightWorkspaceExpansionProvider.notifier)
                      .toggle(expansionKey),
        ),
      );
    }
    final interactiveRow = _draggableWorkspaceChild(
      data: data,
      noteId: node.noteId,
      label: node.label,
      child: row,
    );
    return Column(
      children: [
        if (note != null && target == null)
          _reorderTarget(data: data, before: note, indent: indent),
        interactiveRow,
        if (expanded && !cyclic)
          for (final child in node.children)
            _workspaceTree(child, data, nextAncestors, indent + 18),
      ],
    );
  }

  _WorkspaceDropDestination _destinationForTarget(
    FlightWorkspaceTarget target,
  ) => _WorkspaceDropDestination(
    key: 'inside:${target.key}',
    folderId: target.folderId,
    parentNoteId: target.noteId,
    parentCanvasBlockId:
        target.kind == NoteKind.whiteboard ? target.canvasBlockId : null,
    actionLabel:
        target.kind == NoteKind.whiteboard
            ? 'SOLTAR EN PIZARRA'
            : 'SOLTAR DENTRO',
    destinationLabel: target.label,
  );

  Widget _reorderTarget({
    required _WorkspaceSnapshot data,
    required Note before,
    required double indent,
  }) {
    final destination = _WorkspaceDropDestination(
      key: 'before:${before.id}',
      folderId: before.folderId,
      parentNoteId: before.parentNoteId,
      parentCanvasBlockId: before.parentCanvasBlockId,
      beforeNoteId: before.id,
      actionLabel: 'INSERTAR AQUÍ',
      destinationLabel: 'esta posición',
    );
    return _dropTarget(
      data: data,
      destination: destination,
      compact: true,
      indent: indent,
      child: const SizedBox.shrink(),
    );
  }

  Widget _draggableWorkspaceChild({
    required _WorkspaceSnapshot data,
    required int? noteId,
    required String label,
    required Widget child,
  }) {
    final note = noteId == null ? null : data.notesById[noteId];
    if (note == null || !note.isWikiCreated) return child;
    final drag = _WorkspaceDragData(noteId: note.id, label: label);
    return Listener(
      onPointerDown: (event) {
        _dragPointerStart = event.position;
        _dragDistance = 0;
      },
      child: LongPressDraggable<_WorkspaceDragData>(
        data: drag,
        delay: const Duration(milliseconds: 360),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        maxSimultaneousDrags: 1,
        onDragStarted: () {
          HapticFeedback.mediumImpact();
          setState(() {
            _workspaceDragActive = true;
            _notice = null;
          });
        },
        onDragUpdate: (details) {
          final start = _dragPointerStart;
          if (start == null) return;
          _dragDistance = math.max(
            _dragDistance,
            (details.globalPosition - start).distance,
          );
        },
        onDragEnd: (details) {
          final shouldManage = !details.wasAccepted && _dragDistance < 12;
          _dragPointerStart = null;
          _dragDistance = 0;
          if (mounted) setState(() => _workspaceDragActive = false);
          if (shouldManage) _manageWorkspaceChild(note.id);
        },
        feedback: _WorkspaceDragFeedback(
          label: label,
          kind: note.kind,
          accent: widget.accent,
        ),
        childWhenDragging: Opacity(opacity: 0.36, child: child),
        child: child,
      ),
    );
  }

  Widget _dropTarget({
    required _WorkspaceSnapshot data,
    required _WorkspaceDropDestination destination,
    required Widget child,
    bool compact = false,
    double indent = 0,
  }) {
    return DragTarget<_WorkspaceDragData>(
      key: ValueKey(destination.key),
      onWillAcceptWithDetails: (details) {
        if (destination.invalidLabel != null) return false;
        return _dropValidity(data, details.data, destination).valid;
      },
      onAcceptWithDetails: (details) {
        _moveWorkspaceChild(details.data, destination);
      },
      builder: (context, candidateData, rejectedData) {
        final drag =
            candidateData.isNotEmpty
                ? candidateData.first
                : rejectedData.isNotEmpty
                ? rejectedData.first
                : null;
        final active = _workspaceDragActive && drag != null;
        final validity =
            drag == null
                ? null
                : destination.invalidLabel != null
                ? _WorkspaceDropValidity.invalid(destination.invalidLabel!)
                : _dropValidity(data, drag, destination);
        final valid = validity?.valid == true;
        final signalColor = valid ? widget.accent : yFight;
        if (compact) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            height: active ? 30 : (_workspaceDragActive ? 8 : 0),
            margin: EdgeInsets.only(left: 14 + indent, right: 14),
            padding:
                active
                    ? const EdgeInsets.symmetric(horizontal: 8)
                    : EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: active ? signalColor.withValues(alpha: 0.14) : null,
              border: Border(
                top: BorderSide(
                  color: active ? signalColor : const Color(0x00000000),
                  width: active ? yLineThin : 0,
                ),
              ),
            ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: active ? 1 : 0,
              child: Text(
                validity?.label ?? '',
                style: yMono(
                  size: 9,
                  weight: FontWeight.w800,
                  tracking: 0.7,
                  color: signalColor,
                ),
              ),
            ),
          );
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: active ? signalColor.withValues(alpha: 0.13) : null,
            border: Border(
              left: BorderSide(
                color: active ? signalColor : const Color(0x00000000),
                width: active ? 4 : 0,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child:
                    active
                        ? Container(
                          width: double.infinity,
                          color: signalColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: Text(
                            validity?.label ?? '',
                            style: yMono(
                              size: 9,
                              weight: FontWeight.w800,
                              tracking: 0.7,
                              color: yCream,
                            ),
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _containerRow(
    FlightWorkspaceTreeNode node, {
    required double indent,
    required bool expanded,
    required VoidCallback? onToggle,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Container(
        padding: EdgeInsets.only(left: 14 + indent, right: 14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Icon(
                  expanded ? YuLiIcons.chevronDown : YuLiIcons.chevronRight,
                  size: 14,
                  color: yMuted,
                ),
              ),
              Icon(YuLiIcons.layoutGrid, size: 16, color: widget.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  node.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ySans(size: 13, weight: FontWeight.w800, color: yInk),
                ),
              ),
              Text(
                '${node.children.length}',
                style: yMono(size: 9, color: yMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _targetRow(
    FlightWorkspaceTarget target, {
    String? label,
    bool selected = false,
    bool showFolder = false,
    double indent = 0,
    bool expandable = false,
    bool expanded = false,
    VoidCallback? onToggle,
    VoidCallback? onClose,
  }) {
    return Container(
      color: selected ? Color.lerp(yCream, widget.accent, 0.15) : null,
      padding: EdgeInsets.only(left: 14 + indent),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: selected ? null : () => _open(target),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    if (expandable)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggle,
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: Icon(
                            expanded
                                ? YuLiIcons.chevronDown
                                : YuLiIcons.chevronRight,
                            size: 14,
                            color: yMuted,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 24),
                    Icon(
                      _kindIcon(target.kind),
                      size: 16,
                      color: selected ? widget.accent : yMuted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label ?? target.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ySans(
                              size: 13,
                              weight:
                                  selected ? FontWeight.w800 : FontWeight.w600,
                              color: yInk,
                            ),
                          ),
                          if (showFolder)
                            Text(
                              target.folderLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: yMono(size: 8, color: yMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onClose != null)
            Semantics(
              button: true,
              label: 'Cerrar ${target.label}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    YuLiIcons.close,
                    size: 15,
                    color: selected ? widget.accent : yMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _closeTab(
    FlightWorkspaceTarget target,
    List<FlightWorkspaceTarget> tabs,
  ) {
    final selected = target.key == widget.current.key;
    final index = tabs.indexWhere((item) => item.key == target.key);
    final next =
        selected && tabs.length > 1 && index >= 0
            ? tabs[index == tabs.length - 1 ? index - 1 : index + 1]
            : null;
    ref.read(flightWorkspaceTabsProvider.notifier).close(target);
    if (!selected) return;
    if (next != null) {
      _open(next);
    } else {
      final navigator = Navigator.of(context);
      navigator.pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) navigator.maybePop();
      });
    }
  }
}

class _WorkspaceSnapshot {
  final List<Folder> folders;
  final Map<int, Note> notesById;
  final Map<int, List<FlightWorkspaceTarget>> targetsByFolder;
  final Map<int, List<FlightWorkspaceTreeNode>> rootsByFolder;

  const _WorkspaceSnapshot({
    required this.folders,
    required this.notesById,
    required this.targetsByFolder,
    required this.rootsByFolder,
  });

  factory _WorkspaceSnapshot.build({
    required List<Folder> folders,
    required List<Note> notes,
    required List<NoteBlock> blocks,
    required FlightWorkspaceTarget current,
  }) {
    final tree = buildFlightWorkspaceTree(
      folders: folders,
      notes: notes,
      blocks: blocks,
    );
    return _WorkspaceSnapshot(
      folders: folders,
      notesById: {for (final note in notes) note.id: note},
      targetsByFolder: tree.targetsByFolder,
      rootsByFolder: tree.rootsByFolder,
    );
  }
}

class FlightWorkspaceTreeNode {
  final String key;
  final String label;
  final NoteKind kind;
  final int folderId;
  final int? noteId;
  final FlightWorkspaceTarget? target;
  final List<FlightWorkspaceTreeNode> children;
  final bool preservesChildOrder;
  final int workspaceOrder;

  FlightWorkspaceTreeNode({
    required this.key,
    required this.label,
    required this.kind,
    required this.folderId,
    this.noteId,
    required this.target,
    this.preservesChildOrder = false,
    this.workspaceOrder = 0,
    List<FlightWorkspaceTreeNode>? children,
  }) : children = children ?? [];
}

class FlightWorkspaceTree {
  final Map<int, List<FlightWorkspaceTarget>> targetsByFolder;
  final Map<int, List<FlightWorkspaceTreeNode>> rootsByFolder;

  const FlightWorkspaceTree({
    required this.targetsByFolder,
    required this.rootsByFolder,
  });
}

FlightWorkspaceTree buildFlightWorkspaceTree({
  required List<Folder> folders,
  required List<Note> notes,
  required List<NoteBlock> blocks,
}) {
  final folderById = {for (final folder in folders) folder.id: folder};
  final blocksByNote = <int, List<NoteBlock>>{};
  for (final block in blocks) {
    blocksByNote.putIfAbsent(block.noteId, () => []).add(block);
  }
  final targetsByFolder = <int, List<FlightWorkspaceTarget>>{};
  final rootByNote = <int, FlightWorkspaceTreeNode>{};
  final anchorsByNote = <int, List<FlightWorkspaceTreeNode>>{};
  final rootsByFolder = <int, List<FlightWorkspaceTreeNode>>{};

  void addTarget(FlightWorkspaceTarget target) {
    targetsByFolder.putIfAbsent(target.folderId, () => []).add(target);
  }

  for (final note in notes) {
    final folder = folderById[note.folderId];
    if (folder == null) continue;
    late final FlightWorkspaceTreeNode root;
    if (note.kind == NoteKind.whiteboard) {
      final noteLabel =
          note.displayTitle.trim().isEmpty
              ? _kindFallback(note.kind)
              : note.displayTitle.trim();
      final canvases =
          (blocksByNote[note.id] ?? const []).whereType<DrawingBlock>().toList()
            ..sort((a, b) => a.position.compareTo(b.position));
      final canvasNodes = <FlightWorkspaceTreeNode>[];
      if (canvases.isEmpty) {
        final target = FlightWorkspaceTarget(
          noteId: note.id,
          folderId: folder.id,
          kind: note.kind,
          label: '$noteLabel · Pizarra 1',
          folderLabel: folder.name,
        );
        addTarget(target);
        canvasNodes.add(
          FlightWorkspaceTreeNode(
            key: target.key,
            label: 'Pizarra 1',
            kind: note.kind,
            folderId: folder.id,
            noteId: note.id,
            target: target,
          ),
        );
      } else {
        for (var index = 0; index < canvases.length; index++) {
          final canvas = canvases[index];
          final target = flightWorkspaceTarget(
            note: note,
            folder: folder,
            canvas: canvas,
            canvasOrdinal: index + 1,
          );
          addTarget(target);
          canvasNodes.add(
            FlightWorkspaceTreeNode(
              key: target.key,
              label:
                  canvas.name?.trim().isNotEmpty == true
                      ? canvas.name!.trim()
                      : 'Pizarra ${index + 1}',
              kind: note.kind,
              folderId: folder.id,
              noteId: note.id,
              target: target,
            ),
          );
        }
      }
      root = FlightWorkspaceTreeNode(
        key: 'whiteboard:${note.id}',
        label: noteLabel,
        kind: note.kind,
        folderId: folder.id,
        noteId: note.id,
        target: null,
        preservesChildOrder: true,
        workspaceOrder: note.workspaceOrder,
        children: canvasNodes,
      );
      anchorsByNote[note.id] = canvasNodes;
    } else {
      final target = flightWorkspaceTarget(note: note, folder: folder);
      addTarget(target);
      root = FlightWorkspaceTreeNode(
        key: target.key,
        label: target.label,
        kind: note.kind,
        folderId: folder.id,
        noteId: note.id,
        target: target,
        workspaceOrder: note.workspaceOrder,
      );
      anchorsByNote[note.id] = [root];
    }
    rootByNote[note.id] = root;
    rootsByFolder.putIfAbsent(note.folderId, () => []).add(root);
  }

  for (final note in notes) {
    final parentNoteId = note.parentNoteId;
    if (parentNoteId == null) continue;
    final child = rootByNote[note.id];
    final parentAnchors = anchorsByNote[parentNoteId];
    if (child == null || parentAnchors == null || parentAnchors.isEmpty) {
      continue;
    }
    final requestedKey = '$parentNoteId:${note.parentCanvasBlockId ?? 0}';
    final parent = parentAnchors.firstWhere(
      (node) => node.key == requestedKey,
      orElse: () => parentAnchors.first,
    );
    if (parent.key == child.key ||
        parent.children.any((node) => node.key == child.key)) {
      continue;
    }
    rootsByFolder[note.folderId]?.removeWhere((node) => node.key == child.key);
    parent.children.add(child);
  }

  int compareNodes(FlightWorkspaceTreeNode a, FlightWorkspaceTreeNode b) {
    final order = a.workspaceOrder.compareTo(b.workspaceOrder);
    if (order != 0) return order;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  void sortChildren(FlightWorkspaceTreeNode node, Set<String> ancestors) {
    if (!ancestors.add(node.key)) return;
    if (!node.preservesChildOrder) node.children.sort(compareNodes);
    for (final child in node.children) {
      sortChildren(child, {...ancestors});
    }
  }

  for (final targets in targetsByFolder.values) {
    targets.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
  }
  for (final roots in rootsByFolder.values) {
    roots.sort(compareNodes);
    for (final root in roots) {
      sortChildren(root, <String>{});
    }
  }

  return FlightWorkspaceTree(
    targetsByFolder: targetsByFolder,
    rootsByFolder: rootsByFolder,
  );
}

enum _WorkspaceDeleteChoice { branch, keepChildren }

class _WorkspaceDragData {
  final int noteId;
  final String label;

  const _WorkspaceDragData({required this.noteId, required this.label});
}

class _WorkspaceDropDestination {
  final String key;
  final int folderId;
  final int? parentNoteId;
  final int? parentCanvasBlockId;
  final int? beforeNoteId;
  final String actionLabel;
  final String destinationLabel;
  final String? invalidLabel;

  const _WorkspaceDropDestination({
    required this.key,
    required this.folderId,
    this.parentNoteId,
    this.parentCanvasBlockId,
    this.beforeNoteId,
    required this.actionLabel,
    required this.destinationLabel,
  }) : invalidLabel = null;

  const _WorkspaceDropDestination.invalid({
    required this.key,
    required this.folderId,
    required String label,
  }) : parentNoteId = null,
       parentCanvasBlockId = null,
       beforeNoteId = null,
       actionLabel = label,
       destinationLabel = '',
       invalidLabel = label;
}

class _WorkspaceDropValidity {
  final bool valid;
  final String label;

  const _WorkspaceDropValidity.valid(this.label) : valid = true;
  const _WorkspaceDropValidity.invalid(this.label) : valid = false;
}

class _WorkspaceNotice {
  final String message;
  final bool isError;

  const _WorkspaceNotice(this.message, {required this.isError});
}

class _WorkspaceDragFeedback extends StatelessWidget {
  final String label;
  final NoteKind kind;
  final Color accent;

  const _WorkspaceDragFeedback({
    required this.label,
    required this.kind,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x00000000),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: accent,
          border: Border.all(color: yBorderStrong, width: yLineMid),
          boxShadow: const [
            BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_kindIcon(kind), size: 16, color: yCream),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ySans(size: 12, weight: FontWeight.w800, color: yCream),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(YuLiIcons.gripVertical, size: 15, color: yCream),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceNoticeBanner extends StatelessWidget {
  final _WorkspaceNotice notice;
  final Color accent;
  final VoidCallback onClose;

  const _WorkspaceNoticeBanner({
    super.key,
    required this.notice,
    required this.accent,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = notice.isError ? yFight : accent;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: yBorderStrong, width: yLineThin),
        boxShadow: const [
          BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              notice.isError ? YuLiIcons.triangleAlert : YuLiIcons.check,
              size: 17,
              color: yCream,
            ),
          ),
          Expanded(
            child: Text(
              notice.message,
              style: yBody(size: 11, weight: FontWeight.w700, color: yCream),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(YuLiIcons.close, size: 15, color: yCream),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceDeleteAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  const _WorkspaceDeleteAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow: const [
            BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: yCream),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: yMono(
                      size: 11,
                      weight: FontWeight.w800,
                      tracking: 0.8,
                      color: yCream,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: yBody(
                      size: 11,
                      color: yCream.withValues(alpha: 0.82),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(YuLiIcons.chevronRight, size: 16, color: yCream),
          ],
        ),
      ),
    );
  }
}

String _normalize(String value) => value.trim().toLowerCase();

String _kindFallback(NoteKind kind) => switch (kind) {
  NoteKind.block => 'Sin título',
  NoteKind.whiteboard => 'Pizarra',
  NoteKind.notebook => 'Cuaderno',
};

IconData _kindIcon(NoteKind kind) => switch (kind) {
  NoteKind.block => YuLiIcons.fileText,
  NoteKind.whiteboard => YuLiIcons.layoutGrid,
  NoteKind.notebook => YuLiIcons.notebook,
};
