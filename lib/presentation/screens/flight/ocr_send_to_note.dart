import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';

/// Send recognized [text] into a FLIGHT block-note: pick an existing note to
/// append a text cell, or create a new note in a chosen folder. If there are no
/// notes in the folder you can always create one.
Future<void> sendTextToNote(
  BuildContext context,
  WidgetRef ref,
  String text, {
  int? defaultFolderId,
  Color accent = yInk,
}) async {
  final trimmed = text.trim();
  final messenger = ScaffoldMessenger.of(context);
  if (trimmed.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Nada que enviar')));
    return;
  }
  final folders = await ref.read(folderRepositoryProvider).getActive();
  if (!context.mounted) return;
  if (folders.isEmpty) {
    messenger.showSnackBar(
        const SnackBar(content: Text('No hay carpetas donde guardar')));
    return;
  }

  final dest = await showModalBottomSheet<_Dest>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SendToNotePicker(
      folders: folders,
      defaultFolderId: defaultFolderId,
      accent: accent,
    ),
  );
  if (dest == null || !context.mounted) return;

  final noteRepo = ref.read(noteRepositoryProvider);
  final blockRepo = ref.read(noteBlockRepositoryProvider);

  int noteId;
  String label;
  if (dest.noteId == null) {
    final note = await noteRepo.create(
      dest.folderId,
      kind: NoteKind.block,
      title: _titleFrom(trimmed),
    );
    noteId = note.id;
    label = 'Nota creada';
  } else {
    noteId = dest.noteId!;
    label = 'Enviado a la nota';
  }
  await blockRepo
      .insertAtEnd(noteId, NoteBlockType.text, payload: {'md': trimmed});

  if (!context.mounted) return;
  messenger.showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(seconds: 2)));
}

String _titleFrom(String text) {
  final first = text.split('\n').first.trim();
  return first.length > 40 ? first.substring(0, 40) : first;
}

class _Dest {
  final int folderId;
  final int? noteId; // null = create a new note
  const _Dest(this.folderId, this.noteId);
}

class _SendToNotePicker extends ConsumerStatefulWidget {
  final List<Folder> folders;
  final int? defaultFolderId;
  final Color accent;

  const _SendToNotePicker({
    required this.folders,
    required this.defaultFolderId,
    required this.accent,
  });

  @override
  ConsumerState<_SendToNotePicker> createState() => _SendToNotePickerState();
}

class _SendToNotePickerState extends ConsumerState<_SendToNotePicker> {
  late int _folderId;

  @override
  void initState() {
    super.initState();
    final has = widget.folders.any((f) => f.id == widget.defaultFolderId);
    _folderId = has ? widget.defaultFolderId! : widget.folders.first.id;
  }

  Future<List<Note>> _loadNotes() async {
    final notes = await ref.read(noteRepositoryProvider).getByFolder(_folderId);
    return notes
        .where((n) => n.isActive && n.kind == NoteKind.block)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: yCream,
          border: Border(top: BorderSide(color: yBorderStrong, width: yLineHeavy)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('ENVIAR A NOTA',
                      style: yMono(
                          size: 11,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yInk)),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(YuLiIcons.close, size: 20, color: yInk),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('CARPETA',
                  style: yMono(size: 9, tracking: 1.2, color: yMuted)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in widget.folders) ...[
                      _FolderChip(
                        folder: f,
                        selected: f.id == _folderId,
                        onTap: () => setState(() => _folderId = f.id),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<List<Note>>(
                  future: _loadNotes(),
                  builder: (context, snap) {
                    final notes = snap.data ?? const <Note>[];
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        _DestRow(
                          icon: YuLiIcons.plus,
                          label: 'NUEVA NOTA AQUÍ',
                          accent: widget.accent,
                          highlight: true,
                          onTap: () =>
                              Navigator.of(context).pop(_Dest(_folderId, null)),
                        ),
                        if (snap.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))),
                          )
                        else
                          for (final n in notes)
                            _DestRow(
                              icon: YuLiIcons.fileText,
                              label: n.displayTitle.isEmpty
                                  ? 'Sin título'
                                  : n.displayTitle,
                              accent: widget.accent,
                              highlight: false,
                              onTap: () => Navigator.of(context)
                                  .pop(_Dest(_folderId, n.id)),
                            ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderChip extends StatelessWidget {
  final Folder folder;
  final bool selected;
  final VoidCallback onTap;
  const _FolderChip(
      {required this.folder, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? folder.color : yCream,
          border: Border.all(color: yBorderStrong, width: selected ? 2.5 : yLineThin),
        ),
        child: Text(
          folder.name,
          style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.0,
              color: selected ? yCream : yInk),
        ),
      ),
    );
  }
}

class _DestRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool highlight;
  final VoidCallback onTap;
  const _DestRow({
    required this.icon,
    required this.label,
    required this.accent,
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: highlight ? accent.withValues(alpha: 0.12) : yCream,
          border: Border.all(
              color: highlight ? accent : yBorderStrong,
              width: highlight ? 2 : yLineThin),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: yInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: yBody(size: 14, color: yInk)),
            ),
          ],
        ),
      ),
    );
  }
}
