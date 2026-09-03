import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/folder.dart';
import '../../domain/models/note.dart';
import '../../domain/models/note_block.dart';
import '../providers/database_providers.dart';
import '../providers/flight_workspace_providers.dart';
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
  ValueChanged<String>? onInsertLink,
}) async {
  final action = await showGeneralDialog<_WorkspaceAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar explorador',
    barrierColor: yInk.withValues(alpha: 0.34),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder:
        (_, _, _) => Align(
          alignment: Alignment.centerLeft,
          child: _FlightWorkspacePanel(
            current: current,
            accent: accent,
            canInsertLink: onInsertLink != null,
          ),
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
  if (action == null || !context.mounted) return;
  if (action.insertLink) {
    onInsertLink?.call('[[${flightWikiLinkLabel(action.target)}]]');
    return;
  }
  ref.read(flightWorkspaceTabsProvider.notifier).open(action.target);
  onOpen(action.target);
}

class _WorkspaceAction {
  final FlightWorkspaceTarget target;
  final bool insertLink;

  const _WorkspaceAction.open(this.target) : insertLink = false;
  const _WorkspaceAction.insert(this.target) : insertLink = true;
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
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 1),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final selected = tab.key == current.key;
                return Semantics(
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
                          if (!selected) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap:
                                  () => ref
                                      .read(
                                        flightWorkspaceTabsProvider.notifier,
                                      )
                                      .close(tab),
                              child: const Icon(
                                YuLiIcons.close,
                                size: 13,
                                color: yMuted,
                              ),
                            ),
                          ],
                        ],
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
  final bool canInsertLink;

  const _FlightWorkspacePanel({
    required this.current,
    required this.accent,
    required this.canInsertLink,
  });

  @override
  ConsumerState<_FlightWorkspacePanel> createState() =>
      _FlightWorkspacePanelState();
}

class _FlightWorkspacePanelState extends ConsumerState<_FlightWorkspacePanel> {
  late Future<_WorkspaceSnapshot> _snapshot;
  final _queryController = TextEditingController();
  final Set<int> _expandedFolders = {};
  bool _connectionsOpen = false;

  @override
  void initState() {
    super.initState();
    _expandedFolders.add(widget.current.folderId);
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
    return _WorkspaceSnapshot.build(
      folders: folders,
      notes: notes,
      blocks: blocks,
      current: widget.current,
    );
  }

  void _open(FlightWorkspaceTarget target) {
    Navigator.pop(context, _WorkspaceAction.open(target));
  }

  void _insert(FlightWorkspaceTarget target) {
    if (!widget.canInsertLink) return;
    Navigator.pop(context, _WorkspaceAction.insert(target));
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(460.0, MediaQuery.sizeOf(context).width * 0.92);
    return Material(
      color: Colors.transparent,
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
        _tabsSection(),
        if (data.outgoing.isNotEmpty || data.backlinks.isNotEmpty)
          _connectionsSection(data),
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
          ),
      ],
    );
  }

  Widget _connectionsSection(_WorkspaceSnapshot data) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _connectionsOpen = !_connectionsOpen),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Color.lerp(yCream, widget.accent, 0.08),
              border: Border.all(color: widget.accent, width: yLineThin),
            ),
            child: Row(
              children: [
                Icon(YuLiIcons.link, color: widget.accent, size: 16),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'CONEXIONES · ${data.outgoing.length + data.backlinks.length}',
                    style: ySans(
                      size: 12,
                      weight: FontWeight.w800,
                      color: yInk,
                    ),
                  ),
                ),
                Icon(
                  _connectionsOpen
                      ? YuLiIcons.chevronDown
                      : YuLiIcons.chevronRight,
                  color: yInk,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (_connectionsOpen) ...[
          if (data.outgoing.isNotEmpty)
            _connectionGroup('MENCIONA', data.outgoing),
          if (data.backlinks.isNotEmpty)
            _connectionGroup('MENCIONADA EN', data.backlinks),
        ],
      ],
    );
  }

  Widget _connectionGroup(String label, List<FlightWorkspaceTarget> targets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 16, 4),
          child: Text(
            label,
            style: yMono(
              size: 9,
              weight: FontWeight.w700,
              tracking: 1.1,
              color: yMuted,
            ),
          ),
        ),
        for (final target in targets) _targetRow(target, showFolder: true),
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
    final expanded = query.isNotEmpty || _expandedFolders.contains(folder.id);
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap:
              () => setState(() {
                if (expanded && query.isEmpty) {
                  _expandedFolders.remove(folder.id);
                } else {
                  _expandedFolders.add(folder.id);
                }
              }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: yBorderSoft, width: 1)),
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
                Text('${targets.length}', style: yMono(size: 9, color: yMuted)),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final target in visibleTargets)
            _targetRow(
              target,
              selected: target.key == widget.current.key,
              indent: 18,
              allowInsert: target.key != widget.current.key,
            ),
      ],
    );
  }

  Widget _targetRow(
    FlightWorkspaceTarget target, {
    bool selected = false,
    bool showFolder = false,
    bool allowInsert = false,
    double indent = 0,
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
                            target.label,
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
          if (allowInsert && widget.canInsertLink)
            Semantics(
              button: true,
              label: 'Insertar enlace',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _insert(target),
                child: SizedBox(
                  width: 44,
                  height: 42,
                  child: Icon(YuLiIcons.link, size: 15, color: widget.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceSnapshot {
  final List<Folder> folders;
  final Map<int, List<FlightWorkspaceTarget>> targetsByFolder;
  final List<FlightWorkspaceTarget> outgoing;
  final List<FlightWorkspaceTarget> backlinks;

  const _WorkspaceSnapshot({
    required this.folders,
    required this.targetsByFolder,
    required this.outgoing,
    required this.backlinks,
  });

  factory _WorkspaceSnapshot.build({
    required List<Folder> folders,
    required List<Note> notes,
    required List<NoteBlock> blocks,
    required FlightWorkspaceTarget current,
  }) {
    final folderById = {for (final folder in folders) folder.id: folder};
    final blocksByNote = <int, List<NoteBlock>>{};
    for (final block in blocks) {
      blocksByNote.putIfAbsent(block.noteId, () => []).add(block);
    }
    final targets = <FlightWorkspaceTarget>[];
    final sourceText = <String, String>{};
    for (final note in notes) {
      final folder = folderById[note.folderId];
      if (folder == null) continue;
      final noteBlocks = blocksByNote[note.id] ?? const [];
      if (note.kind == NoteKind.whiteboard) {
        final canvases =
            noteBlocks.whereType<DrawingBlock>().toList()
              ..sort((a, b) => a.position.compareTo(b.position));
        if (canvases.isEmpty) {
          final target = flightWorkspaceTarget(note: note, folder: folder);
          targets.add(target);
          sourceText[target.key] = _noteLinkText(note, noteBlocks);
        } else {
          for (var index = 0; index < canvases.length; index++) {
            final target = flightWorkspaceTarget(
              note: note,
              folder: folder,
              canvas: canvases[index],
              canvasOrdinal: index + 1,
            );
            targets.add(target);
            sourceText[target.key] = _blockLinkText(canvases[index]);
          }
        }
      } else {
        final target = flightWorkspaceTarget(note: note, folder: folder);
        targets.add(target);
        sourceText[target.key] = _noteLinkText(note, noteBlocks);
      }
    }
    final aliases = <String, FlightWorkspaceTarget>{};
    for (final target in targets) {
      aliases.putIfAbsent(
        _normalize(flightWikiLinkLabel(target)),
        () => target,
      );
      aliases.putIfAbsent(_normalize(target.label), () => target);
    }
    final outgoing = <String, FlightWorkspaceTarget>{};
    for (final label in _wikiLabels(sourceText[current.key] ?? '')) {
      final target = aliases[_normalize(label)];
      if (target != null && target.key != current.key) {
        outgoing[target.key] = target;
      }
    }
    final currentAliases = {
      _normalize(flightWikiLinkLabel(current)),
      _normalize(current.label),
    };
    final backlinks = <String, FlightWorkspaceTarget>{};
    for (final entry in sourceText.entries) {
      if (entry.key == current.key) continue;
      final links = _wikiLabels(entry.value).map(_normalize).toSet();
      if (links.any(currentAliases.contains)) {
        final source =
            targets.where((target) => target.key == entry.key).firstOrNull;
        if (source != null) backlinks[source.key] = source;
      }
    }
    final targetsByFolder = <int, List<FlightWorkspaceTarget>>{};
    for (final target in targets) {
      targetsByFolder.putIfAbsent(target.folderId, () => []).add(target);
    }
    for (final folderTargets in targetsByFolder.values) {
      folderTargets.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    }
    return _WorkspaceSnapshot(
      folders: folders,
      targetsByFolder: targetsByFolder,
      outgoing: outgoing.values.toList(),
      backlinks: backlinks.values.toList(),
    );
  }
}

String _noteLinkText(Note note, List<NoteBlock> blocks) => [
  note.rawMarkdown,
  for (final block in blocks) _blockLinkText(block),
].join('\n');

String _blockLinkText(NoteBlock block) => switch (block) {
  TextBlock text => text.markdown,
  BulletsBlock bullets => bullets.items.join('\n'),
  DrawingBlock drawing => _canvasText(drawing.textBlocksJson),
  _ => '',
};

String _canvasText(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return '';
    return decoded
        .whereType<Map>()
        .map((item) => item['md']?.toString() ?? '')
        .join('\n');
  } catch (_) {
    return '';
  }
}

Iterable<String> _wikiLabels(String text) sync* {
  final pattern = RegExp(r'\[\[([^\]\n]{1,120})\]\]');
  for (final match in pattern.allMatches(text)) {
    final label = match.group(1)?.trim();
    if (label != null && label.isNotEmpty) yield label;
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
