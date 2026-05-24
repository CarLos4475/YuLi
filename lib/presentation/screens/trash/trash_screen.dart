import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/task.dart';

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(deletedFoldersProvider).valueOrNull ?? [];
    final notes = ref.watch(deletedNotesProvider).valueOrNull ?? [];
    final spaces = ref.watch(deletedLabSpacesProvider).valueOrNull ?? [];
    final tasks = ref.watch(trashedTasksProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: Column(
          children: [
            _TrashHeader(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _TrashColumn(
                      accent: accentFlight,
                      title: 'FLIGHT',
                      onEmpty: 'Sin elementos',
                      children: [
                        ...folders.map((f) => _TrashFolderItem(folder: f)),
                        ...notes.map((n) => _TrashNoteItem(note: n)),
                      ],
                    ),
                  ),
                  _VerticalDivider(),
                  Expanded(
                    child: _TrashColumn(
                      accent: accentLab,
                      title: 'LAB',
                      onEmpty: 'Sin elementos',
                      children: [
                        ...spaces.map((s) => _TrashSpaceItem(space: s)),
                      ],
                    ),
                  ),
                  _VerticalDivider(),
                  Expanded(
                    child: _TrashColumn(
                      accent: accentFight,
                      title: 'FIGHT',
                      onEmpty: 'Sin elementos',
                      children: [
                        ...tasks.map((t) => _TrashTaskItem(task: t)),
                      ],
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

class _TrashHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: inkColor(context), width: borderWidth),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Papelera',
              style: displayL.copyWith(color: inkColor(context)),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Cerrar',
                style: labelBold.copyWith(color: inkGray),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: borderWidth,
      color: inkColor(context),
    );
  }
}

class _TrashColumn extends StatelessWidget {
  final Color accent;
  final String title;
  final String onEmpty;
  final List<Widget> children;

  const _TrashColumn({
    required this.accent,
    required this.title,
    required this.onEmpty,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: inkColor(context), width: borderWidth),
            ),
          ),
          child: Text(
            title,
            style: labelBold.copyWith(color: accent),
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? Center(
                  child: Text(
                    onEmpty,
                    style: bodyS.copyWith(color: inkGray),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: children,
                ),
        ),
      ],
    );
  }
}

class _TrashFolderItem extends ConsumerWidget {
  final Folder folder;

  const _TrashFolderItem({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: inkColor(context), width: borderWidth),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              color: folder.color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                folder.name,
                style: bodyM.copyWith(color: inkColor(context)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ref.read(folderRepositoryProvider).restore(folder.id);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'Restaurar',
                  style: labelBold.copyWith(color: inkGray),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ref.read(folderRepositoryProvider).hardDelete(folder.id);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'Eliminar',
                  style: labelBold.copyWith(color: accentFight),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashNoteItem extends ConsumerWidget {
  final Note note;

  const _TrashNoteItem({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: inkColor(context), width: borderWidth),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                note.displayTitle,
                style: bodyS.copyWith(color: inkColor(context)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ref.read(noteRepositoryProvider).restore(note.id);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'Restaurar',
                  style: labelBold.copyWith(color: inkGray),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ref.read(noteRepositoryProvider).hardDelete(note.id);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'Eliminar',
                  style: labelBold.copyWith(color: accentFight),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashSpaceItem extends ConsumerWidget {
  final LabSpace space;

  const _TrashSpaceItem({required this.space});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: inkColor(context), width: borderWidth),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              color: space.accentColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                space.name,
                style: bodyM.copyWith(color: inkColor(context)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ref.read(labSpaceRepositoryProvider).restore(space.id);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'Restaurar',
                  style: labelBold.copyWith(color: inkGray),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ref.read(labSpaceRepositoryProvider).hardDelete(space.id);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'Eliminar',
                  style: labelBold.copyWith(color: accentFight),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashTaskItem extends ConsumerWidget {
  final Task task;

  const _TrashTaskItem({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: inkColor(context), width: borderWidth),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                task.content,
                style: bodyS.copyWith(color: inkColor(context)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await ref.read(taskRepositoryProvider).deleteFromTrash(task.id);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  'Eliminar',
                  style: labelBold.copyWith(color: accentFight),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
