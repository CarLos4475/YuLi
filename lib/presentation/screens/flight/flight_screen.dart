import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/folder_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/database_providers.dart';
import '../../widgets/coach_mark.dart';
import '../../../domain/models/folder.dart';
import 'folder_detail_screen.dart';
import 'new_folder_dialog.dart';

class FlightScreen extends ConsumerWidget {
  const FlightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(activeFoldersProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _FlightHeader()),
        foldersAsync.when(
          loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
          error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          data: (folders) => SliverToBoxAdapter(
            child: CoachMark(
              flagKey: 'flight_intro',
              message: 'Tus carpetas viven aquí. Toca para entrar.',
              child: _FolderGrid(folders: folders),
            ),
          ),
        ),
      ],
    );
  }
}

class _FlightHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: accentFlight,
        border: Border(
          bottom: BorderSide(color: inkColor(context), width: borderWidth),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FLIGHT', style: displayXL.copyWith(color: inkLight)),
          const SizedBox(height: 2),
          Text('Modo de notas', style: bodyS.copyWith(color: inkLight.withAlpha(180))),
        ],
      ),
    );
  }
}

class _FolderGrid extends ConsumerWidget {
  final List<Folder> folders;

  const _FolderGrid({required this.folders});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crossCount = _crossAxisCount(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
        ),
        itemCount: folders.length + 1,
        itemBuilder: (context, index) {
          if (index < folders.length) {
            return _FolderTile(folder: folders[index]);
          }
          return _NewFolderTile();
        },
      ),
    );
  }

  int _crossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }
}

class _FolderTile extends ConsumerWidget {
  final Folder folder;

  const _FolderTile({required this.folder});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: inkColor(context), width: borderWidth),
        ),
        title: Text('Eliminar carpeta',
            style: displayM.copyWith(color: inkColor(context))),
        content: Text('Se moverá la carpeta y todo su contenido (notas) a la papelera.',
            style: bodyM.copyWith(color: inkColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: labelBold.copyWith(color: inkGray)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: labelBold.copyWith(color: accentFight)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(folderRepositoryProvider).softDelete(folder.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Carpeta "${folder.name}" movida a la papelera'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingTasksForFolderProvider(folder.id));
    final pendingCount = pendingAsync.valueOrNull?.length ?? 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FolderDetailScreen(folder: folder)),
      ),
      onLongPress: () => _confirmDelete(context, ref),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: folder.color,
              border: Border.all(color: inkColor(context), width: borderWidthHeavy),
            ),
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                folder.name,
                style: displayL.copyWith(color: inkLight),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (pendingCount > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                color: inkBlack,
                child: Text(
                  '$pendingCount',
                  style: labelBold.copyWith(color: inkLight),
                ),
              ),
            ),
        ],
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
            color: inkGray,
            width: borderWidth,
            // dashed border is not natively supported; using solid inkGray
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            '+ Nueva carpeta',
            style: displayM.copyWith(color: inkGray),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
