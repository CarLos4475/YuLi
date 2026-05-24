import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../widgets/coach_mark.dart';
import '../../widgets/edit_item_dialog.dart';
import 'lab_space_detail_screen.dart';
import 'new_lab_space_dialog.dart';
import '../../../domain/models/lab_space.dart';

class LabScreen extends ConsumerStatefulWidget {
  const LabScreen({super.key});

  @override
  ConsumerState<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends ConsumerState<LabScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingSpaceId = ref.read(pendingLabSpaceNavigationProvider);
      if (pendingSpaceId != null) {
        ref.read(pendingLabSpaceNavigationProvider.notifier).state = null;
        _navigateToPendingSpace(pendingSpaceId);
      }
    });
  }

  Future<void> _navigateToPendingSpace(int spaceId) async {
    final space = await ref.read(labSpaceRepositoryProvider).getById(spaceId);
    if (space == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LabSpaceDetailScreen(space: space),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(ctx),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        contentPadding: EdgeInsets.zero,
        content: Container(
          decoration: BoxDecoration(
            border: Border.all(color: inkBlack, width: borderWidth),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('LAB', style: displayM.copyWith(color: accentLab)),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: paperColor(ctx),
                        border: Border.all(color: inkBlack, width: borderWidth),
                        boxShadow: const [
                          BoxShadow(
                            color: inkBlack,
                            offset: shadowOffset,
                            blurRadius: shadowBlurRadius,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.close, size: 14, color: inkBlack),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _HelpSection(
                label: 'SPACES',
                body: 'Cada space es un proyecto. Toca un space para abrir su '
                    'tablero Kanban con columnas y tarjetas.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                label: 'COLUMNAS',
                body: 'Por defecto se crean: Backlog, En Proceso, Entregado y '
                    'Vencido. Puedes agregar, renombrar o eliminar columnas.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                label: 'FECHA LÍMITE',
                body: 'Asigna fecha a una tarjeta para que se mueva '
                    'automáticamente a la columna Vencido cuando expire.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                label: 'NOTAS FLIGHT',
                body: 'Las notas de Flight se vinculan a espacios desde el editor. '
                    'Las tareas de Fight se envían a columnas con long press.',
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LAB', style: displayXL.copyWith(color: inkLight)),
                    const SizedBox(height: 2),
                    Text('Modo de proyectos',
                        style: bodyS.copyWith(color: inkLight.withAlpha(180))),
                  ],
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showHelpDialog(context),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: paperColor(context),
                    border: Border.all(color: inkBlack, width: borderWidth),
                    boxShadow: const [
                      BoxShadow(
                        color: inkBlack,
                        offset: shadowOffset,
                        blurRadius: shadowBlurRadius,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.question_mark, size: 18, color: inkBlack),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String label;
  final String body;

  const _HelpSection({required this.label, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelBold.copyWith(color: accentLab)),
        const SizedBox(height: 2),
        Text(body, style: bodyM.copyWith(color: inkColor(context))),
      ],
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

  void _showOptions(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => EditItemDialog(
        title: 'Space',
        initialName: space.name,
        initialColor: space.accentColor,
        onSave: (name, color) async {
          await ref.read(labSpaceRepositoryProvider).update(space.copyWith(
                name: name,
                accentColor: color,
              ));
        },
        onDelete: () async {
          Navigator.pop(ctx);
          await _confirmDelete(context, ref);
        },
      ),
    );
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
      onLongPress: () => _showOptions(context, ref),
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
