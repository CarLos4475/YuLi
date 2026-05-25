import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/task.dart' as domain_task;
import '../../../domain/models/lab_space.dart';

// ─── FIGHT screen ─────────────────────────────────────────────────────────

class FightScreen extends ConsumerWidget {
  const FightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoy = ref.watch(pendingTasksProvider).valueOrNull ?? [];
    final ayer = ref.watch(yesterdayTasksProvider).valueOrNull ?? [];
    final vencidas = ref.watch(vencidasTasksProvider).valueOrNull ?? [];

    return Column(
      children: [
        ModeHeader(
          mode: 'FIGHT',
          subtitle: 'MODO CAPTURA · @ ETIQUETA CARPETA · MANTÉN-PRESIONADA → LAB',
          color: yFight,
          onBack: () =>
              ref.read(currentModeProvider.notifier).state = AppMode.home,
          headerRight: [
            YBadge(label: '${hoy.length} HOY', bg: yCream, fg: yInk),
            YBadge(label: '${ayer.length} AYER', bg: yAmber, fg: yCream),
            YBadge(label: '${vencidas.length} VENCIDAS', bg: yInk, fg: yCream),
          ],
        ),
        const _CapturaBar(),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, c) {
              final isWide = c.maxWidth >= 900;
              if (isWide) {
                return _ThreeBuckets(
                  hoy: hoy,
                  ayer: ayer,
                  vencidas: vencidas,
                );
              }
              return _StackedBuckets(
                hoy: hoy,
                ayer: ayer,
                vencidas: vencidas,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Captura bar ──────────────────────────────────────────────────────────

class _CapturaBar extends ConsumerStatefulWidget {
  const _CapturaBar();

  @override
  ConsumerState<_CapturaBar> createState() => _CapturaBarState();
}

class _CapturaBarState extends ConsumerState<_CapturaBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  List<Folder> _mentionFolders = [];
  int? _mentionStart;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (cursor < 0) return;
    final before = cursor > 0 ? text.substring(0, cursor) : '';
    final atIdx = before.lastIndexOf('@');
    final inMention = atIdx >= 0 &&
        !before.substring(atIdx).contains(' ') &&
        !before.substring(atIdx).contains('\n');
    if (inMention) {
      _showMention(before.substring(atIdx + 1).toLowerCase());
      _mentionStart = atIdx;
    } else {
      _removeOverlay();
      _mentionStart = null;
    }
    setState(() {});
  }

  void _showMention(String query) {
    final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
    final clean = _stripAccents(query.toLowerCase());
    final filtered = folders
        .where((f) => _stripAccents(f.name.toLowerCase()).contains(clean))
        .toList();
    if (filtered.isEmpty) {
      _removeOverlay();
      return;
    }
    setState(() => _mentionFolders = filtered);
    if (_overlay != null) {
      _overlay!.markNeedsBuild();
      return;
    }
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 260,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(40, 60),
          child: Material(
            color: Colors.transparent,
            child: _MentionPopup(
              folders: _mentionFolders,
              onSelect: _onMention,
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _onMention(Folder f) {
    _removeOverlay();
    if (_mentionStart == null) return;
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final replacement = '@${f.name}';
    final newText =
        text.substring(0, _mentionStart) + replacement + text.substring(cursor);
    _controller.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: _mentionStart! + replacement.length),
    );
    _mentionStart = null;
    _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
    int? folderId;
    final m = RegExp(r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)').firstMatch(raw);
    if (m != null) {
      final clean = _stripAccents(m.group(1)!.toLowerCase());
      final match =
          folders.where((f) => _stripAccents(f.name.toLowerCase()) == clean);
      if (match.isNotEmpty) folderId = match.first.id;
    }
    final now = DateTime.now();
    await ref.read(taskRepositoryProvider).save(
          domain_task.Task(
            id: 0,
            content: raw,
            status: domain_task.TaskStatus.pending,
            folderId: folderId,
            createdAt: now,
            expiresAt: DateTime(now.year, now.month, now.day, 23, 59, 59),
          ),
        );
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 22),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Container(
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yInk, width: yLineHeavy),
          ),
          height: 76,
          child: Row(
            children: [
              // FIGHT/ prefix
              Container(
                color: yInk,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                alignment: Alignment.center,
                child: Text(
                  'FIGHT/',
                  style: yMono(
                    size: 13,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yCream,
                  ),
                ),
              ),
              Container(width: yLineHeavy, color: yInk),
              // Input
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: ySans(
                      size: 22,
                      weight: FontWeight.w500,
                      letterSpacing: -0.4,
                      color: yInk,
                    ),
                    cursorColor: yInk,
                    cursorWidth: 2.5,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: 'Captura una tarea…',
                      hintStyle: ySans(
                        size: 22,
                        weight: FontWeight.w500,
                        letterSpacing: -0.4,
                        color: yMuted,
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              // Red + submit
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _submit,
                child: Container(
                  width: 76,
                  height: double.infinity,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: yFight,
                    border: Border(left: BorderSide(color: yInk, width: yLineHeavy)),
                  ),
                  child: Text(
                    '+',
                    style: ySans(
                      size: 30,
                      weight: FontWeight.w700,
                      color: yCream,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _stripAccents(String s) {
  const a = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑ';
  const b = 'aeiouAEIOUaeiouAEIOUnN';
  var r = s;
  for (int i = 0; i < a.length; i++) {
    r = r.replaceAll(a[i], b[i]);
  }
  return r;
}

// ─── Three buckets layout (tablet wide) ───────────────────────────────────

class _ThreeBuckets extends StatelessWidget {
  final List<domain_task.Task> hoy;
  final List<domain_task.Task> ayer;
  final List<domain_task.Task> vencidas;

  const _ThreeBuckets({
    required this.hoy,
    required this.ayer,
    required this.vencidas,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 23,
          child: _BucketColumn(
            title: 'HOY',
            subtitle: 'capturadas hoy',
            color: yFight,
            tasks: hoy,
            gesture: _BucketGesture.swipe,
            borderRight: true,
          ),
        ),
        Expanded(
          flex: 20,
          child: _BucketColumn(
            title: 'AYER',
            subtitle: 'sin terminar de ayer',
            color: yAmber2,
            tasks: ayer,
            gesture: _BucketGesture.swipe,
            borderRight: true,
          ),
        ),
        Expanded(
          flex: 19,
          child: _BucketColumn(
            title: 'VENCIDAS',
            subtitle: 'se borran pronto',
            color: yInk,
            tasks: vencidas,
            gesture: _BucketGesture.expiring,
          ),
        ),
      ],
    );
  }
}

// ─── Stacked buckets (narrow / phone) ─────────────────────────────────────

class _StackedBuckets extends StatelessWidget {
  final List<domain_task.Task> hoy;
  final List<domain_task.Task> ayer;
  final List<domain_task.Task> vencidas;

  const _StackedBuckets({
    required this.hoy,
    required this.ayer,
    required this.vencidas,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _InlineBucketHeader(
            title: 'HOY',
            subtitle: 'capturadas hoy',
            color: yFight,
            count: hoy.length),
        ...hoy.map((t) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _SwipeableTaskCard(
                  task: t, gesture: _BucketGesture.swipe),
            )),
        _InlineBucketHeader(
            title: 'AYER',
            subtitle: 'sin terminar',
            color: yAmber2,
            count: ayer.length),
        ...ayer.map((t) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _SwipeableTaskCard(
                  task: t, gesture: _BucketGesture.swipe),
            )),
        _InlineBucketHeader(
            title: 'VENCIDAS',
            subtitle: 'se borran pronto',
            color: yInk,
            count: vencidas.length),
        ...vencidas.map((t) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _SwipeableTaskCard(
                  task: t, gesture: _BucketGesture.expiring),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _InlineBucketHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final int count;

  const _InlineBucketHeader({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title,
              style: ySans(
                size: 28,
                weight: FontWeight.w700,
                letterSpacing: -1,
                color: yCream,
              )),
          const SizedBox(width: 10),
          Expanded(
            child: Text(subtitle,
                style: yMono(
                  size: 10,
                  color: yCream.withValues(alpha: 0.85),
                  tracking: 1.4,
                )),
          ),
          Text(
            count.toString().padLeft(2, '0'),
            style: yMono(
              size: 13,
              weight: FontWeight.w700,
              color: yCream,
              tracking: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bucket column ────────────────────────────────────────────────────────

enum _BucketGesture { swipe, expiring }

class _BucketColumn extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final List<domain_task.Task> tasks;
  final _BucketGesture gesture;
  final bool borderRight;

  const _BucketColumn({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tasks,
    required this.gesture,
    this.borderRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: borderRight
            ? const Border(right: BorderSide(color: yInk, width: yLineHeavy))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            color: color,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: color,
              border:
                  const Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: ySans(
                          size: 28,
                          weight: FontWeight.w700,
                          letterSpacing: -1,
                          color: yCream,
                          height: 1.0,
                        ),
                      ),
                    ),
                    Text(
                      tasks.length.toString().padLeft(2, '0'),
                      style: yMono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: yCream,
                        tracking: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: yMono(
                    size: 10,
                    color: yCream.withValues(alpha: 0.85),
                    tracking: 1.4,
                  ),
                ),
              ],
            ),
          ),
          // Gesture hint
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: yInk.withValues(alpha: 0.25), width: 1),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: gesture == _BucketGesture.swipe
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('← DESCARTAR',
                          style: yMono(size: 9, tracking: 1.4)),
                      Text('COMPLETAR →',
                          style: yMono(size: 9, tracking: 1.4)),
                    ],
                  )
                : Center(
                    child: Text('● AUTO-BORRADO PROGRAMADO',
                        style: yMono(size: 9, tracking: 1.4)),
                  ),
          ),
          // List
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      'NADA',
                      style: yMono(
                        size: 10,
                        color: yMuted.withValues(alpha: 0.6),
                        tracking: 1.4,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    itemBuilder: (_, i) => _SwipeableTaskCard(
                      task: tasks[i],
                      gesture: gesture,
                    ),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemCount: tasks.length,
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Swipeable task card ──────────────────────────────────────────────────

class _SwipeableTaskCard extends ConsumerStatefulWidget {
  final domain_task.Task task;
  final _BucketGesture gesture;

  const _SwipeableTaskCard({required this.task, required this.gesture});

  @override
  ConsumerState<_SwipeableTaskCard> createState() => _SwipeableTaskCardState();
}

class _SwipeableTaskCardState extends ConsumerState<_SwipeableTaskCard> {
  Future<void> _complete() async {
    await ref.read(taskRepositoryProvider).markDone(widget.task.id);
    await syncTaskCompletionToKanban(ref, widget.task.id);
  }

  Future<void> _discard() async {
    await ref.read(taskRepositoryProvider).moveToTrash(widget.task.id);
  }

  void _showSendToLab(BuildContext context) async {
    final spaces =
        ref.read(activeLabSpacesProvider).valueOrNull ?? <LabSpace>[];
    if (spaces.isEmpty) return;
    final space = await showDialog<LabSpace>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: yCream,
        shape:
            const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: yInk, width: yLineHeavy),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enviar a LAB',
                  style: ySans(
                      size: 22, weight: FontWeight.w700, color: yInk)),
              const SizedBox(height: 12),
              for (final s in spaces)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(ctx, s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          color: s.accentColor,
                        ),
                        const SizedBox(width: 10),
                        Text(s.name, style: ySans(size: 16, color: yInk)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (space != null) {
      // No-op for now — left as integration point for kanban link.
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _TaskCardBody(
      task: widget.task,
      expiring: widget.gesture == _BucketGesture.expiring,
    );

    if (widget.gesture == _BucketGesture.expiring) {
      return GestureDetector(
        onTap: () {},
        onLongPress: () => _showSendToLab(context),
        child: card,
      );
    }

    return Dismissible(
      key: ValueKey('fight_${widget.task.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _complete();
        } else {
          await _discard();
        }
        return false;
      },
      background: const _SwipeBg(
        color: yLab,
        align: Alignment.centerLeft,
        icon: Icons.check,
        label: 'HECHO',
      ),
      secondaryBackground: const _SwipeBg(
        color: yInk2,
        align: Alignment.centerRight,
        icon: Icons.close,
        label: 'DESC.',
      ),
      child: GestureDetector(
        onLongPress: () => _showSendToLab(context),
        child: card,
      ),
    );
  }
}

class _SwipeBg extends StatelessWidget {
  final Color color;
  final Alignment align;
  final IconData icon;
  final String label;

  const _SwipeBg({
    required this.color,
    required this.align,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: align == Alignment.centerRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Icon(icon, color: yCream, size: 20),
          const SizedBox(height: 2),
          Text(label,
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                color: yCream,
                tracking: 1.4,
              )),
        ],
      ),
    );
  }
}

class _TaskCardBody extends ConsumerWidget {
  final domain_task.Task task;
  final bool expiring;

  const _TaskCardBody({required this.task, required this.expiring});

  String _captured(DateTime created) {
    return '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
  }

  String _deleteIn(DateTime base) {
    final deleteAt = base.add(const Duration(days: 2));
    final remaining = deleteAt.difference(DateTime.now());
    if (remaining.isNegative) return 'pronto';
    final h = remaining.inHours;
    if (h >= 24) return '${(remaining.inDays).clamp(1, 99)} d';
    if (h >= 1) return '$h h';
    return '${remaining.inMinutes} m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = task.folderId == null
        ? null
        : ref.watch(folderByIdProvider(task.folderId!)).valueOrNull;

    final bg = expiring ? yCream2 : yCream;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: yInk, width: yLineMid),
      ),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: expiring ? 0.65 : 1.0,
            child: Text(
              task.content,
              style: ySans(
                size: 15,
                weight: FontWeight.w600,
                letterSpacing: -0.2,
                color: yInk,
                height: 1.25,
              ).copyWith(
                decoration: expiring ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: folder == null
                    ? Text('sin etiqueta',
                        style: yMono(
                          size: 10,
                          tracking: 1.2,
                          color: yMuted,
                        ).copyWith(fontStyle: FontStyle.italic))
                    : _FolderMention(folder: folder),
              ),
              const SizedBox(width: 6),
              Text(
                expiring
                    ? 'BORRA EN ${_deleteIn(task.dueDate ?? task.createdAt).toUpperCase()}'
                    : _captured(task.createdAt),
                style: yMono(
                  size: 10,
                  tracking: 1.2,
                  color: expiring ? yFight : yMuted,
                  weight: expiring ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderMention extends StatelessWidget {
  final Folder folder;
  const _FolderMention({required this.folder});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 2, 7, 3),
      decoration: BoxDecoration(
        color: folder.color,
        border: Border.all(color: yInk, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('@',
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                color: yCream.withValues(alpha: 0.85),
                tracking: 0.3,
              )),
          const SizedBox(width: 2),
          Text(folder.name,
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                color: yCream,
                tracking: 0.5,
              )),
        ],
      ),
    );
  }
}

// ─── Mention popup ────────────────────────────────────────────────────────

class _MentionPopup extends StatelessWidget {
  final List<Folder> folders;
  final void Function(Folder) onSelect;

  const _MentionPopup({required this.folders, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: folders.map((f) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(f),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(width: 10, height: 10, color: f.color),
                  const SizedBox(width: 8),
                  Text(f.name,
                      style: yBody(
                        size: 14,
                        weight: FontWeight.w700,
                        color: yInk,
                      )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
