import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/ai_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/lab_tab_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../widgets/yuli_ai_fab.dart';
import '../../widgets/edit_item_dialog.dart';
import '../../widgets/yuli_action_sheet.dart';
import '../yuli_ai/yuli_ai_chat_sheet.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/lab_space.dart';
import 'lab_space_detail_screen.dart';
import 'new_lab_space_dialog.dart';

// ─── Toolbar state ────────────────────────────────────────────────────────

enum LabTab { todos, activos, pausados, completados, archivo }

final labFilterProvider = StateProvider<LabTab>((ref) => LabTab.todos);

String _filterLabel(LabTab tab) => switch (tab) {
  LabTab.todos => 'Todos',
  LabTab.activos => 'En proceso',
  LabTab.pausados => 'Pausados',
  LabTab.completados => 'Completados',
  LabTab.archivo => 'Archivo',
};

// ─── Screen ───────────────────────────────────────────────────────────────

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
      MaterialPageRoute(builder: (_) => LabSpaceDetailScreen(space: space)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSpaces = ref.watch(activeLabSpacesProvider).valueOrNull ?? [];
    final filter = ref.watch(labFilterProvider);

    final activos =
        allSpaces.where((s) => s.status == LabSpaceStatus.active).toList();
    final pausados =
        allSpaces.where((s) => s.status == LabSpaceStatus.paused).toList();
    final completados =
        allSpaces.where((s) => s.status == LabSpaceStatus.completed).toList();
    final archivo =
        allSpaces.where((s) => s.status == LabSpaceStatus.archived).toList();

    final shown = switch (filter) {
      LabTab.todos => allSpaces,
      LabTab.activos => activos,
      LabTab.pausados => pausados,
      LabTab.completados => completados,
      LabTab.archivo => archivo,
    }..sort((a, b) {
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

    return Stack(
      children: [
        Column(
          children: [
            ModeHeader(
              mode: 'LAB',
              subtitle: 'MODO PROYECTOS · ${activos.length} SPACES ACTIVOS',
              color: yLab,
              onBack:
                  () =>
                      ref.read(currentModeProvider.notifier).state =
                          AppMode.home,
              headerRight: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      () => showDialog(
                        context: context,
                        builder: (_) => const NewLabSpaceDialog(),
                      ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: yCream,
                      border: Border.all(color: yBorderStrong, width: yLineMid),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '+',
                          style: TextStyle(
                            fontSize: 18,
                            color: yInk,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'NUEVO SPACE',
                          style: yBody(
                            size: 13,
                            weight: FontWeight.w700,
                            color: yInk,
                          ).copyWith(letterSpacing: 1.2),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      () => showModeHelp(
                        context,
                        mode: 'LAB',
                        accent: yLab,
                        description:
                            'Gestiona proyectos con tableros kanban, calendario, '
                            'horario, timeline y grafo de relaciones. Organiza espacios '
                            'de trabajo con tarjetas, fechas y seguimiento visual.',
                        tips: [
                          'Toca un space para abrir su tablero kanban',
                          'Programa fechas en el calendario y horario',
                          'Usa el grafo para ver conexiones entre notas y tareas',
                          'Mantén presionado un space para opciones',
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
            _LabToolbar(
              counts: {
                LabTab.todos: allSpaces.length,
                LabTab.activos: activos.length,
                LabTab.pausados: pausados.length,
                LabTab.completados: completados.length,
                LabTab.archivo: archivo.length,
              },
            ),
            Expanded(
              child: Container(
                color: yCream,
                child: _SpacesGrid(spaces: shown),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: YuliAiFab(
            accent: yLab,
            onTap:
                () => showYuliAiChat(
                  context,
                  ref,
                  accent: yLab,
                  surfaceContext: YuliAiSurfaceContext(
                    mode: 'Lab',
                    view: _filterLabel(filter),
                    details: 'Vista general de proyectos Lab.',
                  ),
                ),
          ),
        ),
      ],
    );
  }
}

// ─── Toolbar (status tabs + sort label) ───────────────────────────────────

class _LabToolbar extends ConsumerWidget {
  final Map<LabTab, int> counts;
  const _LabToolbar({required this.counts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(labFilterProvider);
    final notifier = ref.read(labFilterProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: Row(
        children: [
          PillTab(
            label: 'TODOS · ${counts[LabTab.todos] ?? 0}',
            active: filter == LabTab.todos,
            onTap: () => notifier.state = LabTab.todos,
          ),
          const SizedBox(width: 6),
          PillTab(
            label: 'EN PROCESO · ${counts[LabTab.activos] ?? 0}',
            active: filter == LabTab.activos,
            onTap: () => notifier.state = LabTab.activos,
          ),
          const SizedBox(width: 6),
          PillTab(
            label: 'PAUSADOS · ${counts[LabTab.pausados] ?? 0}',
            active: filter == LabTab.pausados,
            onTap: () => notifier.state = LabTab.pausados,
          ),
          const SizedBox(width: 6),
          PillTab(
            label: 'COMPLETADOS · ${counts[LabTab.completados] ?? 0}',
            active: filter == LabTab.completados,
            onTap: () => notifier.state = LabTab.completados,
          ),
          const SizedBox(width: 6),
          PillTab(
            label: 'ARCHIVO · ${counts[LabTab.archivo] ?? 0}',
            active: filter == LabTab.archivo,
            onTap: () => notifier.state = LabTab.archivo,
          ),
          const Spacer(),
          Text(
            'ORDEN:',
            style: yMono(
              size: 10,
              weight: FontWeight.w500,
              tracking: 1.4,
              color: yMuted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'POR DEADLINE ↑',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yInk,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Spaces grid ──────────────────────────────────────────────────────────

class _SpacesGrid extends ConsumerWidget {
  final List<LabSpace> spaces;

  const _SpacesGrid({required this.spaces});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final cols =
            c.maxWidth >= 1100
                ? 3
                : c.maxWidth >= 700
                ? 2
                : 1;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            mainAxisExtent: 394,
          ),
          itemCount: spaces.length + 1,
          itemBuilder: (_, i) {
            if (i >= spaces.length) return const _NewSpaceCard();
            return _SpaceCard(space: spaces[i]);
          },
        );
      },
    );
  }
}

// ─── Space card (dossier) ─────────────────────────────────────────────────

class _SpaceCard extends ConsumerWidget {
  final LabSpace space;
  const _SpaceCard({required this.space});

  String _stageLabel(LabSpace s, DateTime now) {
    if (s.status == LabSpaceStatus.paused) return 'Pausado';
    if (s.status == LabSpaceStatus.completed) return 'Completado';
    if (s.status == LabSpaceStatus.archived) return 'Archivado';
    if (s.dueDate != null && now.isAfter(s.dueDate!)) return 'Vencido';
    if (s.startDate != null && now.isBefore(s.startDate!)) return 'Por iniciar';
    if (s.startDate == null && s.dueDate == null) return 'Sin fechas';
    return 'En proceso';
  }

  Color _stageColor(String stage) {
    switch (stage) {
      case 'En proceso':
        return yLab;
      case 'Pausado':
        return yAmber;
      case 'Completado':
        return const Color(0xFF2D6E6E);
      case 'Archivado':
        return yMuted;
      case 'Vencido':
        return yFight;
      case 'Por iniciar':
        return yFlight;
      case 'Sin fechas':
        return yMuted;
      default:
        return yLab;
    }
  }

  int? _daysLeft(LabSpace s, DateTime now) {
    if (s.dueDate == null) return null;
    return s.dueDate!.difference(now).inDays;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _showRename(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (_) => EditItemDialog(
            title: 'Renombrar space',
            initialName: space.name,
            initialColor: space.accentColor,
            onSave: (name, color) async {
              await ref
                  .read(labSpaceRepositoryProvider)
                  .update(space.copyWith(name: name, accentColor: color));
            },
            onDelete: () async {
              await ref.read(labSpaceRepositoryProvider).softDelete(space.id);
            },
          ),
    );
  }

  Future<void> _showColorPicker(BuildContext context, WidgetRef ref) async {
    final selected = await showLabSpaceColorDialog(
      context,
      title: 'Color del space',
      spaceName: space.name,
      initialColor: space.accentColor,
    );
    if (selected == null) return;
    await ref
        .read(labSpaceRepositoryProvider)
        .update(space.copyWith(accentColor: selected));
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    final repo = ref.read(labSpaceRepositoryProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        final options = <Widget>[];

        options.add(
          YuLiActionTile(
            icon: YuLiIcons.pen,
            label: 'Cambiar nombre',
            accent: space.accentColor,
            useAccentFill: false,
            onTap: () {
              Navigator.pop(ctx);
              _showRename(context, ref);
            },
          ),
        );

        options.add(
          YuLiActionTile(
            icon: YuLiIcons.palette,
            label: 'Cambiar color',
            accent: space.accentColor,
            useAccentFill: false,
            onTap: () {
              Navigator.pop(ctx);
              _showColorPicker(context, ref);
            },
          ),
        );

        if (space.status == LabSpaceStatus.paused) {
          options.add(
            YuLiActionTile(
              icon: YuLiIcons.play,
              label: 'Reanudar',
              accent: space.accentColor,
              useAccentFill: false,
              onTap: () async {
                Navigator.pop(ctx);
                await repo.update(
                  space.copyWith(status: LabSpaceStatus.active),
                );
              },
            ),
          );
        } else if (space.status == LabSpaceStatus.active) {
          options.add(
            YuLiActionTile(
              icon: YuLiIcons.pause,
              label: 'Pausar',
              accent: space.accentColor,
              useAccentFill: false,
              onTap: () async {
                Navigator.pop(ctx);
                await repo.update(
                  space.copyWith(status: LabSpaceStatus.paused),
                );
              },
            ),
          );
        }

        if (space.status != LabSpaceStatus.completed) {
          options.add(
            YuLiActionTile(
              icon: YuLiIcons.circleCheck,
              label: 'Completar',
              accent: space.accentColor,
              useAccentFill: false,
              onTap: () async {
                Navigator.pop(ctx);
                await repo.update(
                  space.copyWith(status: LabSpaceStatus.completed),
                );
              },
            ),
          );
        }

        if (space.status != LabSpaceStatus.archived) {
          options.add(
            YuLiActionTile(
              icon: YuLiIcons.archive,
              label: 'Archivar',
              accent: space.accentColor,
              useAccentFill: false,
              onTap: () async {
                Navigator.pop(ctx);
                await repo.update(
                  space.copyWith(status: LabSpaceStatus.archived),
                );
              },
            ),
          );
        }

        if (space.status != LabSpaceStatus.active &&
            space.status != LabSpaceStatus.paused) {
          options.add(
            YuLiActionTile(
              icon: YuLiIcons.refresh,
              label: 'Reactivar',
              accent: space.accentColor,
              useAccentFill: false,
              onTap: () async {
                Navigator.pop(ctx);
                await repo.update(
                  space.copyWith(status: LabSpaceStatus.active),
                );
              },
            ),
          );
        }

        options.add(
          YuLiActionTile(
            icon: YuLiIcons.trash,
            label: 'Eliminar',
            accent: space.accentColor,
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
                        'Eliminar space',
                        style: ySans(size: 18, weight: FontWeight.w700),
                      ),
                      content: Text(
                        '¿Eliminar "${space.name}"? Se moverá a la papelera.',
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
              if (ok == true) await repo.softDelete(space.id);
            },
          ),
        );

        return YuLiActionSheet(
          title: space.name,
          badge: 'SPACE',
          badgeIcon: YuLiIcons.square,
          accent: space.accentColor,
          children: options,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns =
        ref.watch(kanbanColumnsProvider(space.id)).valueOrNull ?? [];
    final cards =
        ref.watch(kanbanCardsBySpaceProvider(space.id)).valueOrNull ?? [];
    final tabs = ref.watch(labTabsProvider(space.id));

    final now = DateTime.now();
    final stage = _stageLabel(space, now);
    final daysLeft = _daysLeft(space, now);
    final urgent = daysLeft != null && daysLeft <= 7;

    // Per-column counts
    final colCounts = <int, int>{};
    for (final c in cards) {
      colCounts[c.columnId] = (colCounts[c.columnId] ?? 0) + 1;
    }
    final total = cards.length;
    final terminalCols = columns.where((c) => c.isTerminal).toList();
    final vencidoCol = columns.firstWhere(
      (c) => c.isExpired,
      orElse:
          () => KanbanColumn(
            id: -1,
            labSpaceId: space.id,
            name: '',
            position: 0,
            isDefault: false,
          ),
    );

    int hechas = 0;
    for (final c in terminalCols) {
      hechas += colCounts[c.id] ?? 0;
    }
    final vencidas = vencidoCol.id == -1 ? 0 : (colCounts[vencidoCol.id] ?? 0);
    final abiertas = (total - hechas - vencidas).clamp(0, total);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LabSpaceDetailScreen(space: space),
            ),
          ),
      onLongPress: () => _showOptions(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top stripe (space accent)
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: space.accentColor,
                border: const Border(
                  bottom: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
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
                            Text(
                              'SPACE',
                              style: yMono(
                                size: 10,
                                weight: FontWeight.w700,
                                tracking: 1.4,
                                color: yMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              space.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ySans(
                                size: 30,
                                weight: FontWeight.w700,
                                letterSpacing: -1,
                                color: yInk,
                                height: 0.95,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (daysLeft != null)
                        YBadge(
                          label: urgent ? '▲ ${daysLeft}d' : '${daysLeft}d',
                          bg: urgent ? yFight : yLab,
                          fg: yCream,
                          fontSize: 10,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      YBadge(
                        label: stage,
                        bg: _stageColor(stage),
                        fg: yCream,
                        fontSize: 10,
                      ),
                      if (space.dueDate != null)
                        YBadge(
                          label: _fmtDate(space.dueDate!),
                          bg: yFlight,
                          fg: yCream,
                          fontSize: 10,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 2, color: yBorderStrong),
            // Distribution
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '> DISTRIBUCIÓN',
                        style: yMono(size: 10, color: yMuted, tracking: 1.4),
                      ),
                      Text(
                        '$total TAREAS',
                        style: yMono(
                          size: 11,
                          weight: FontWeight.w700,
                          tracking: 1,
                          color: yMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _StackedBar(
                    columns: columns,
                    counts: colCounts,
                    total: total,
                  ),
                  const SizedBox(height: 8),
                  _ColumnLegend(columns: columns, counts: colCounts),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatPill(
                        value: '$abiertas',
                        label: 'abiertas',
                        color: yInk,
                      ),
                      const SizedBox(width: 14),
                      _StatPill(
                        value: '$vencidas',
                        label: 'vencidas',
                        color: vencidas > 0 ? yFight : yInk,
                      ),
                      const SizedBox(width: 14),
                      _StatPill(value: '$hechas', label: 'hechas', color: yInk),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 2, color: yBorderStrong),
            // Capabilities
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '> VISTAS ACTIVAS',
                      style: yMono(size: 10, color: yMuted, tracking: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final cap in const [
                          'Kanban',
                          'Horario',
                          'Timeline',
                          'Calendario',
                          'Grafo',
                        ])
                          CapChip(
                            kind: cap,
                            active: tabs.contains(cap),
                            color: space.accentColor,
                            onTap:
                                cap == 'Kanban'
                                    ? null
                                    : () {
                                      final notifier = ref.read(
                                        labTabsProvider(space.id).notifier,
                                      );
                                      if (tabs.contains(cap)) {
                                        notifier.removeTab(cap);
                                      } else {
                                        notifier.addTab(cap);
                                      }
                                    },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              decoration: const BoxDecoration(
                color: yCream2,
                border: Border(
                  top: BorderSide(color: yBorderStrong, width: yLineThin),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ABRIR SPACE',
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    ),
                  ),
                  Text(
                    '→',
                    style: TextStyle(fontSize: 16, color: yInk, height: 1.0),
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

class _StatPill extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatPill({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: ySans(size: 18, weight: FontWeight.w700, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: yMono(size: 11, color: yMuted, tracking: 0.5)),
      ],
    );
  }
}

class _StackedBar extends StatelessWidget {
  final List<KanbanColumn> columns;
  final Map<int, int> counts;
  final int total;

  const _StackedBar({
    required this.columns,
    required this.counts,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return Container(
        height: 22,
        decoration: BoxDecoration(
          color: yCream2,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: CustomPaint(
          painter: _DiagonalHatch(color: const Color(0x1A0A0A0A)),
        ),
      );
    }
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        children: [
          for (final c in columns)
            if ((counts[c.id] ?? 0) > 0)
              Expanded(
                flex: counts[c.id]!,
                child: Container(
                  decoration: BoxDecoration(
                    color: _colorForColumn(c),
                    border: Border(
                      right: BorderSide(color: yBorderStrong, width: 1.5),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Color _colorForColumn(KanbanColumn c) {
    if (c.isExpired) return yFight;
    if (c.isTerminal) return yLab;
    if (c.isInProgress) return yAmber;
    if (c.name == 'Backlog') return yMuted;
    return yInk;
  }
}

class _DiagonalHatch extends CustomPainter {
  final Color color;
  _DiagonalHatch({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p =
        Paint()
          ..color = color
          ..strokeWidth = 1;
    const step = 6.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalHatch old) => old.color != color;
}

class _ColumnLegend extends StatelessWidget {
  final List<KanbanColumn> columns;
  final Map<int, int> counts;

  const _ColumnLegend({required this.columns, required this.counts});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final c in columns)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _colorFor(c),
                  border: Border.all(color: yBorderStrong, width: 1.5),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                c.name.toUpperCase(),
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 0.7,
                  color: yInk,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                (counts[c.id] ?? 0).toString().padLeft(2, '0'),
                style: yMono(size: 9, tracking: 0.7, color: yMuted),
              ),
            ],
          ),
      ],
    );
  }

  Color _colorFor(KanbanColumn c) {
    if (c.isExpired) return yFight;
    if (c.isTerminal) return yLab;
    if (c.isInProgress) return yAmber;
    if (c.name == 'Backlog') return yMuted;
    return yInk;
  }
}

class _NewSpaceCard extends StatelessWidget {
  const _NewSpaceCard();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          () => showDialog(
            context: context,
            builder: (_) => const NewLabSpaceDialog(),
          ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Text(
                '+',
                style: TextStyle(fontSize: 36, color: yInk, height: 1.0),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Nuevo space',
              style: ySans(
                size: 18,
                weight: FontWeight.w700,
                letterSpacing: -0.4,
                color: yInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'SCOPE + DEADLINE + VISTAS',
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
