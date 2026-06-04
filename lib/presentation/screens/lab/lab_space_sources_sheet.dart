import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../widgets/yuli_design.dart';
import '../flight/context_assembler.dart' show kMaxFolderNotes;
import '../../../data/services/context_cache.dart';
import '../../../data/services/web_reader.dart' show WebReaderException;
import '../../../domain/models/canvas_context_source.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';

/// Unified "Fuentes" manager for a lab space: notes, folders and urls feed the
/// space AI chat as context (mirrors the canvas Fuentes sheet). A `folder`
/// source replaces the old "vincular carpeta".
Future<void> showSpaceSourcesSheet(BuildContext context, LabSpace space) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SpaceSourcesSheet(space: space),
  );
}

class _SpaceSourcesSheet extends ConsumerStatefulWidget {
  final LabSpace space;
  const _SpaceSourcesSheet({required this.space});

  @override
  ConsumerState<_SpaceSourcesSheet> createState() => _SpaceSourcesSheetState();
}

class _SpaceSourcesSheetState extends ConsumerState<_SpaceSourcesSheet> {
  bool _busy = false;

  int get _spaceId => widget.space.id;

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

  /// Subtitle under a source's name. Folders show their block-note count and a
  /// "top N al chat" note when the folder exceeds the cap, so the user knows the
  /// folder may not feed every note to the AI.
  String _subtitle(CanvasContextSource s, String kindLabel) {
    if (s.isUrl) return '$kindLabel · ${_ago(s.fetchedAt)}';
    if (s.isFolder) {
      final fid = s.folderId;
      final count = fid == null
          ? null
          : ref.watch(folderBlockNoteCountProvider(fid)).valueOrNull;
      if (count == null) return kindLabel;
      final notas = '$count ${count == 1 ? 'nota' : 'notas'}';
      return count > kMaxFolderNotes
          ? '$kindLabel · $notas · top $kMaxFolderNotes al chat'
          : '$kindLabel · $notas';
    }
    return kindLabel;
  }

  List<CanvasContextSource> get _sources =>
      ref.read(spaceContextSourcesProvider(_spaceId)).valueOrNull ?? const [];

  // Links a whole FOLDER to the space (kind='folder'). This draws the
  // structural sun→folder line in the graph and pulls in its notes (and its
  // @folder Fight tasks) by containment. Individual notes still go via "+ NOTA".
  Future<void> _addFolder() async {
    final folders =
        ref.read(activeFoldersProvider).valueOrNull ?? const <Folder>[];
    if (folders.isEmpty) {
      _snack('No hay carpetas.');
      return;
    }
    final linked = _sources.where((s) => s.isFolder).map((s) => s.ref).toSet();
    final candidates =
        folders.where((f) => !linked.contains(f.id.toString())).toList();
    if (candidates.isEmpty) {
      _snack('Ya vinculaste todas las carpetas.');
      return;
    }
    final folder = await _pickFolder('VINCULAR CARPETA', candidates);
    if (folder == null || !mounted) return;
    await ref.read(labSpaceRepositoryProvider).addContextSource(
          _spaceId,
          CanvasSourceKind.folder,
          folder.id.toString(),
          label: folder.name,
        );
  }

  Future<void> _addNote() async {
    final folders =
        ref.read(activeFoldersProvider).valueOrNull ?? const <Folder>[];
    if (folders.isEmpty) {
      _snack('No hay carpetas con notas.');
      return;
    }
    final folder = await _pickFolder('ELIGE CARPETA', folders);
    if (folder == null || !mounted) return;
    final notes = await ref.read(noteRepositoryProvider).getByFolder(folder.id);
    final existing = _sources.where((s) => s.isNote).map((s) => s.ref).toSet();
    final candidates =
        notes
            .where(
              (n) =>
                  n.isActive &&
                  n.kind == NoteKind.block &&
                  !existing.contains(n.id.toString()),
            )
            .toList();
    if (candidates.isEmpty) {
      _snack('No hay notas para agregar en esa carpeta.');
      return;
    }
    if (!mounted) return;
    final picked = await _pickNote(candidates);
    if (picked == null) return;
    await ref
        .read(labSpaceRepositoryProvider)
        .addContextSource(
          _spaceId,
          CanvasSourceKind.note,
          picked.id.toString(),
          label: picked.displayTitle,
        );
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
          .read(labSpaceRepositoryProvider)
          .addContextSource(
            _spaceId,
            CanvasSourceKind.url,
            clean,
            label: doc.title,
            fetchedAt: DateTime.now(),
          );
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
          .read(labSpaceRepositoryProvider)
          .updateContextSourceFetch(
            s.id,
            label: doc.title,
            fetchedAt: DateTime.now(),
          );
    } on WebReaderException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo actualizar la página.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(CanvasContextSource s) async {
    await ref.read(labSpaceRepositoryProvider).removeContextSource(s.id);
    if (s.isUrl) {
      await clearCompactCache('url:${contextStableHash(s.ref)}');
      await clearUrlContent(s.ref);
    } else if (s.isNote) {
      await clearCompactCache('note:${s.ref}');
    }
  }

  Future<Folder?> _pickFolder(String title, List<Folder> folders) {
    return showModalBottomSheet<Folder>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => _PickerSheet(
            title: title,
            count: folders.length,
            itemBuilder:
                (i) => _PickerRow(
                  swatch: folders[i].color,
                  label: folders[i].name,
                  onTap: () => Navigator.of(ctx).pop(folders[i]),
                ),
          ),
    );
  }

  Future<Note?> _pickNote(List<Note> notes) {
    return showModalBottomSheet<Note>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => _PickerSheet(
            title: 'AGREGAR NOTA',
            count: notes.length,
            itemBuilder:
                (i) => _PickerRow(
                  label:
                      notes[i].displayTitle.isEmpty
                          ? 'Sin título'
                          : notes[i].displayTitle,
                  onTap: () => Navigator.of(ctx).pop(notes[i]),
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources =
        ref.watch(spaceContextSourcesProvider(_spaceId)).valueOrNull ??
        const [];
    final accent = widget.space.accentColor;
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
              'Notas y enlaces alimentan el chat del proyecto como contexto. '
              'Una carpeta la vincula al proyecto y aparece en el grafo con sus '
              'notas y tareas. Los enlaces se leen una vez (↻ para actualizar).',
              style: yBody(size: 12, color: yMuted),
            ),
            const SizedBox(height: 12),
            if (sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Sin fuentes. Agrega una carpeta, nota o enlace.',
                  style: yMono(size: 11, color: yMuted, tracking: 0.6),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sources.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _sourceRow(sources[i], accent),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _addBtn(
                    '+ CARPETA',
                    accent,
                    _busy ? null : _addFolder,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _addBtn('+ NOTA', accent, _busy ? null : _addNote),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _addBtn('+ ENLACE', accent, _busy ? null : _addUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceRow(CanvasContextSource s, Color accent) {
    final (icon, kindLabel) = switch (s.kind) {
      CanvasSourceKind.folder => (Icons.folder_outlined, 'CARPETA'),
      CanvasSourceKind.url => (Icons.link, 'ENLACE'),
      CanvasSourceKind.note => (Icons.description_outlined, 'NOTA'),
    };
    final label = (s.label?.trim().isEmpty ?? true) ? s.ref : s.label!.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                () => ref
                    .read(labSpaceRepositoryProvider)
                    .setContextSourceEnabled(s.id, !s.enabled),
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                s.enabled ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: s.enabled ? accent : yMuted,
              ),
            ),
          ),
          Icon(icon, size: 16, color: s.enabled ? accent : yMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: yBody(
                    size: 13,
                    weight: FontWeight.w700,
                    color: s.enabled ? yInk : yMuted,
                  ),
                ),
                Text(
                  _subtitle(s, kindLabel),
                  style: yMono(size: 8, color: yMuted, tracking: 1),
                ),
              ],
            ),
          ),
          if (s.isUrl)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : () => _refetch(s),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.refresh, size: 18, color: yInk),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _remove(s),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.close, size: 16, color: yMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addBtn(String label, Color accent, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? yCream2 : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Text(
          label,
          style: yMono(
            size: 10,
            weight: FontWeight.w700,
            tracking: 0.8,
            color: onTap == null ? yMuted : yInk,
          ),
        ),
      ),
    );
  }
}

class _PickerSheet extends StatelessWidget {
  final String title;
  final int count;
  final Widget Function(int) itemBuilder;
  const _PickerSheet({
    required this.title,
    required this.count,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
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
            Text(
              title,
              style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yInk,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: count,
                itemBuilder: (_, i) => itemBuilder(i),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final Color? swatch;
  final String label;
  final VoidCallback onTap;
  const _PickerRow({this.swatch, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: yBorderStrong, width: yLineThin),
          ),
        ),
        child: Row(
          children: [
            if (swatch != null) ...[
              Container(width: 12, height: 12, color: swatch),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ySans(size: 14, weight: FontWeight.w700, color: yInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

