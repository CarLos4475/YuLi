import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/lab_tab_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/lab_space.dart';
import 'lab_space_detail_screen.dart';
import 'new_lab_space_dialog.dart';

// ─── Toolbar state ────────────────────────────────────────────────────────

enum LabTab { activos, pausados, completados, archivo }

final labFilterProvider =
    StateProvider<LabTab>((ref) => LabTab.activos);

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

    final activos = allSpaces.where((s) => s.status == LabSpaceStatus.active).toList();
    final pausados = allSpaces.where((s) => s.status == LabSpaceStatus.paused).toList();
    final completados = allSpaces.where((s) => s.status == LabSpaceStatus.completed).toList();
    final archivo = allSpaces.where((s) => s.status == LabSpaceStatus.archived).toList();

    final shown = switch (filter) {
      LabTab.activos => activos,
      LabTab.pausados => pausados,
      LabTab.completados => completados,
      LabTab.archivo => archivo,
    }
      ..sort((a, b) {
        final ad = a.dueDate;
        final bd = b.dueDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    return Column(
      children: [
        ModeHeader(
          mode: 'LAB',
          subtitle:
              'MODO PROYECTOS · ${activos.length} SPACES ACTIVOS',
          color: yLab,
          onBack: () =>
              ref.read(currentModeProvider.notifier).state = AppMode.home,
          headerRight: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showDialog(
                context: context,
                builder: (_) => const NewLabSpaceDialog(),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: yCream,
                  border: Border.all(color: yInk, width: yLineMid),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('+',
                        style: TextStyle(
                            fontSize: 18, color: yInk, height: 1.0)),
                    const SizedBox(width: 8),
                    Text('NUEVO SPACE',
                        style: yBody(
                          size: 13,
                          weight: FontWeight.w700,
                          color: yInk,
                        ).copyWith(letterSpacing: 1.2)),
                  ],
                ),
              ),
            ),
            IconSquareBtn(icon: Icons.help_outline),
          ],
        ),
        _LabToolbar(
          counts: {
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
        border: Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: Row(
        children: [
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
          Text('ORDEN:',
              style: yMono(
                size: 10,
                weight: FontWeight.w500,
                tracking: 1.4,
                color: yMuted,
              )),
          const SizedBox(width: 8),
          Text('POR DEADLINE ↑',
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yInk,
              )),
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
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 1100
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
    });
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

  int? _daysLeft(LabSpace s, DateTime now) {
    if (s.dueDate == null) return null;
    return s.dueDate!.difference(now).inDays;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Eliminar space',
            style: ySans(size: 18, weight: FontWeight.w700)),
        content: Text(
          '¿Eliminar "${space.name}"? Se moverá a la papelera.',
          style: yBody(size: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(labSpaceRepositoryProvider).softDelete(space.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = ref.watch(kanbanColumnsProvider(space.id)).valueOrNull ?? [];
    final cards = ref.watch(kanbanCardsBySpaceProvider(space.id)).valueOrNull ?? [];
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
    final terminalCols = columns
        .where((c) =>
            _terminalNames.contains(c.name) || _terminalNames.contains(c.name.toLowerCase()))
        .toList();
    final vencidoCol = columns.firstWhere(
      (c) => c.name == 'Vencido',
      orElse: () => KanbanColumn(
          id: -1, labSpaceId: space.id, name: '', position: 0, isDefault: false),
    );

    int hechas = 0;
    for (final c in terminalCols) {
      hechas += colCounts[c.id] ?? 0;
    }
    final vencidas = vencidoCol.id == -1 ? 0 : (colCounts[vencidoCol.id] ?? 0);
    final abiertas = (total - hechas - vencidas).clamp(0, total);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LabSpaceDetailScreen(space: space)),
      ),
      onLongPress: () => _confirmDelete(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineHeavy),
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
                    bottom: BorderSide(color: yInk, width: yLineHeavy)),
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
                            Text('SPACE',
                                style: yMono(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  tracking: 1.4,
                                  color: yMuted,
                                )),
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
                          bg: urgent ? yFight : yInk,
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
                      YBadge(label: stage, bg: yLab, fg: yCream, fontSize: 10),
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
            const Divider(height: 1, thickness: 2, color: yInk),
            // Distribution
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('// DISTRIBUCIÓN',
                          style: yMono(size: 10, color: yMuted, tracking: 1.4)),
                      Text('$total TAREAS',
                          style: yMono(
                            size: 11,
                            weight: FontWeight.w700,
                            tracking: 1,
                            color: yMuted,
                          )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _StackedBar(columns: columns, counts: colCounts, total: total),
                  const SizedBox(height: 8),
                  _ColumnLegend(columns: columns, counts: colCounts),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatPill(value: '$abiertas', label: 'abiertas', color: yInk),
                      const SizedBox(width: 14),
                      _StatPill(
                          value: '$vencidas',
                          label: 'vencidas',
                          color: vencidas > 0 ? yFight : yInk),
                      const SizedBox(width: 14),
                      _StatPill(value: '$hechas', label: 'hechas', color: yInk),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 2, color: yInk),
            // Capabilities
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('// VISTAS ACTIVAS',
                        style: yMono(size: 10, color: yMuted, tracking: 1.4)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final cap in const [
                          'Kanban',
                          'Horario',
                          'Timeline',
                          'Calendario'
                        ])
                          CapChip(
                            kind: cap,
                            active: tabs.contains(cap),
                            color: space.accentColor,
                            onTap: cap == 'Kanban'
                                ? null
                                : () {
                                    final notifier = ref.read(
                                        labTabsProvider(space.id).notifier);
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
                border: Border(top: BorderSide(color: yInk, width: yLineThin)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('ABRIR SPACE',
                      style: yMono(
                        size: 10,
                        weight: FontWeight.w700,
                        tracking: 1.4,
                        color: yInk,
                      )),
                  Text('→',
                      style: TextStyle(
                          fontSize: 16, color: yInk, height: 1.0)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _terminalNames = {
    'Entregado',
    'Hecho',
    'Listo',
    'Done',
    'entregado',
    'hecho',
    'listo',
    'done',
    'Notas',
    'notas',
  };
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
        Text(value,
            style: ySans(
                size: 18, weight: FontWeight.w700, color: color)),
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
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: CustomPaint(painter: _DiagonalHatch(color: const Color(0x1A0A0A0A))),
      );
    }
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yInk, width: yLineThin),
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
                        right: BorderSide(color: yInk, width: 1.5)),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Color _colorForColumn(KanbanColumn c) {
    if (c.name == 'Vencido') return yFight;
    if (c.name == 'Entregado' ||
        c.name == 'Hecho' ||
        c.name == 'Listo') {
      return yLab;
    }
    if (c.name == 'En Proceso' || c.name == 'En proceso') return yAmber;
    if (c.name == 'Backlog') return yMuted;
    return yInk;
  }
}

class _DiagonalHatch extends CustomPainter {
  final Color color;
  _DiagonalHatch({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 6.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        p,
      );
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
                  border: Border.all(color: yInk, width: 1.5),
                ),
              ),
              const SizedBox(width: 5),
              Text(c.name.toUpperCase(),
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 0.7,
                    color: yInk,
                  )),
              const SizedBox(width: 3),
              Text((counts[c.id] ?? 0).toString().padLeft(2, '0'),
                  style: yMono(
                    size: 9,
                    tracking: 0.7,
                    color: yMuted,
                  )),
            ],
          ),
      ],
    );
  }

  Color _colorFor(KanbanColumn c) {
    if (c.name == 'Vencido') return yFight;
    if (c.name == 'Entregado' || c.name == 'Hecho' || c.name == 'Listo') return yLab;
    if (c.name == 'En Proceso' || c.name == 'En proceso') return yAmber;
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
      onTap: () => showDialog(
        context: context,
        builder: (_) => const NewLabSpaceDialog(),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: yInk, width: yLineHeavy),
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
                border: Border.all(color: yInk, width: yLineHeavy),
              ),
              child: const Text('+',
                  style: TextStyle(
                      fontSize: 36, color: yInk, height: 1.0)),
            ),
            const SizedBox(height: 12),
            Text('Nuevo space',
                style: ySans(
                  size: 18,
                  weight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: yInk,
                )),
            const SizedBox(height: 6),
            Text('SCOPE + DEADLINE + VISTAS',
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
