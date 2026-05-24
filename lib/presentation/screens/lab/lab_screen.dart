import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/database_providers.dart';
import '../../widgets/coach_mark.dart';
import 'lab_space_detail_screen.dart';
import 'new_lab_space_dialog.dart';
import '../../../domain/models/lab_space.dart';

class LabScreen extends ConsumerWidget {
  const LabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(activeLabSpacesProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _LabHeader()),
        spacesAsync.when(
          loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
          error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          data: (spaces) => SliverToBoxAdapter(
            child: CoachMark(
              flagKey: 'lab_intro',
              message: 'Cada space es un proyecto. Toca para abrir el tablero kanban.',
              child: _SpaceGrid(spaces: spaces),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: accentLab,
        border: Border(
          bottom: BorderSide(color: inkColor(context), width: borderWidth),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LAB', style: displayXL.copyWith(color: inkLight)),
          const SizedBox(height: 2),
          Text('Modo de proyectos', style: bodyS.copyWith(color: inkLight.withAlpha(180))),
        ],
      ),
    );
  }
}

class _SpaceGrid extends StatelessWidget {
  final List<LabSpace> spaces;

  const _SpaceGrid({required this.spaces});

  @override
  Widget build(BuildContext context) {
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
          childAspectRatio: 1.1,
        ),
        itemCount: spaces.length + 1,
        itemBuilder: (context, index) {
          if (index < spaces.length) {
            return _SpaceTile(space: spaces[index]);
          }
          return _NewSpaceTile();
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

class _SpaceTile extends ConsumerWidget {
  final LabSpace space;

  const _SpaceTile({required this.space});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: inkColor(context), width: borderWidth),
        ),
        title: Text('Eliminar space',
            style: displayM.copyWith(color: inkColor(context))),
        content: Text('Se moverá el space y todas sus columnas y tarjetas a la papelera.',
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
      await ref.read(labSpaceRepositoryProvider).softDelete(space.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Space "${space.name}" movido a la papelera'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => LabSpaceDetailScreen(space: space)),
      ),
      onLongPress: () => _confirmDelete(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: space.accentColor,
          border: Border.all(
              color: inkColor(context), width: borderWidthHeavy),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                space.name,
                style: displayL.copyWith(color: inkLight),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusLabel(space.status),
              style: bodyS.copyWith(
                color: inkLight,
                decoration: space.status == LabSpaceStatus.completed
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            if (space.dueDate != null)
              Text(
                _formatDate(space.dueDate!),
                style: bodyS.copyWith(
                  color: inkLight.withAlpha(180),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(LabSpaceStatus s) => switch (s) {
        LabSpaceStatus.active => 'En proceso',
        LabSpaceStatus.completed => 'Entregado',
        LabSpaceStatus.archived => 'Archivado',
      };

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _NewSpaceTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDialog(
        context: context,
        builder: (_) => const NewLabSpaceDialog(),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: inkGray, width: borderWidth),
        ),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            '+ Nuevo space',
            style: displayM.copyWith(color: inkGray),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
