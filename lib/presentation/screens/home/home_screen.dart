import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../../domain/models/task.dart' as domain_task;
import '../../../domain/models/folder.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_section_divider.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _taskController = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Folder> _mentionFolders = [];
  int? _mentionStart;

  @override
  void initState() {
    super.initState();
    _taskController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    _taskController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addQuickTask() {
    final raw = _taskController.text.trim();
    if (raw.isEmpty) return;
    final now = DateTime.now();
    final expires = DateTime(now.year, now.month, now.day, 23, 59, 59);

    int? folderId;
    final mentionMatch = RegExp(r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)').firstMatch(raw);
    if (mentionMatch != null) {
      final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
      final name = mentionMatch.group(1)!;
      final cleanName = removeAccents(name.toLowerCase());
      final match = folders.where(
        (f) => removeAccents(f.name.toLowerCase()) == cleanName,
      );
      if (match.isNotEmpty) folderId = match.first.id;
    }

    ref.read(taskRepositoryProvider).save(
          domain_task.Task(
            id: 0,
            content: raw,
            status: domain_task.TaskStatus.pending,
            folderId: folderId,
            createdAt: now,
            expiresAt: expires,
          ),
        );
    _taskController.clear();
    _removeOverlay();
    _focusNode.requestFocus();
  }

  void _onTextChanged() {
    final text = _taskController.text;
    final cursor = _taskController.selection.baseOffset;
    if (cursor < 0) return;

    final before = cursor > 0 ? text.substring(0, cursor) : '';
    final atIndex = before.lastIndexOf('@');
    final hasSpaceAfterAt = atIndex >= 0 &&
        !before.substring(atIndex).contains(' ') &&
        !before.substring(atIndex).contains('\n');

    if (atIndex >= 0 && hasSpaceAfterAt) {
      final query = before.substring(atIndex + 1).toLowerCase();
      _showMentionPopup(query);
      _mentionStart = atIndex;
    } else {
      _removeOverlay();
      _mentionStart = null;
    }
  }

  void _showMentionPopup(String query) {
    final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
    final cleanQuery = removeAccents(query.toLowerCase());
    final filtered = folders
        .where((f) => removeAccents(f.name.toLowerCase()).contains(cleanQuery))
        .toList();

    if (filtered.isEmpty) {
      _removeOverlay();
      return;
    }

    setState(() => _mentionFolders = filtered);

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        width: 240,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 56),
          child: Material(
            color: Colors.transparent,
            child: _MentionPopup(
              folders: _mentionFolders,
              onSelect: _onMentionSelect,
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onMentionSelect(Folder folder) {
    _removeOverlay();
    if (_mentionStart == null) return;

    final text = _taskController.text;
    final cursor = _taskController.selection.baseOffset;
    final replacement = '@${folder.name}';
    final newText =
        text.substring(0, _mentionStart) + replacement + text.substring(cursor);
    _taskController.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: _mentionStart! + replacement.length),
    );
    _mentionStart = null;
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = _greeting(now.hour);
    final dateStr = _formatDate(now);
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final pendingAsync = ref.watch(pendingTasksProvider);
    final foldersAsync = ref.watch(activeFoldersProvider);
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final doneAsync = ref.watch(doneTodayTasksProvider);

    final pendingTasks = pendingAsync.valueOrNull ?? [];
    final folders = foldersAsync.valueOrNull ?? [];
    final spaces = spacesAsync.valueOrNull ?? [];
    final doneCount = doneAsync.valueOrNull?.length ?? 0;

    final nextTask = pendingTasks.isNotEmpty ? pendingTasks.first : null;
    final latestFolder = folders.isNotEmpty ? folders.first : null;

    Folder? nextTaskFolder;
    if (nextTask?.folderId != null) {
      for (final f in folders) {
        if ((f as dynamic).id == nextTask!.folderId) {
          nextTaskFolder = f;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── HEADER MONOLITO ──
            Container(
              width: double.infinity,
              color: inkColor(context),
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            greeting.toUpperCase(),
                            style: labelBold.copyWith(
                              color: paperColor(context),
                              letterSpacing: 2,
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            ),
                            child: Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.settings,
                                size: 20,
                                color: paperColor(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 48,
                        height: borderWidthHeavy,
                        color: paperColor(context).withAlpha(80),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timeStr,
                        style: displayXL.copyWith(color: paperColor(context)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr.toUpperCase(),
                        style: bodyS.copyWith(color: inkGray),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 32,
                    bottom: -20,
                    child: Text(
                      'YuLi',
                      textAlign: TextAlign.right,
                      style: displayL.copyWith(
                        color: paperColor(context).withAlpha(20),
                        fontSize: 144,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: borderWidthHeavy,
              color: inkColor(context),
            ),

            // ── STATS BLOQUES ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatBlock(
                    label: 'PENDIENTES',
                    value: '${pendingTasks.length}',
                    color: accentFight,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                  ),
                  _StatBlock(
                    label: 'NOTAS',
                    value: '${folders.length}',
                    color: accentFlight,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.flight,
                  ),
                  _StatBlock(
                    label: 'LABS',
                    value: '${spaces.length}',
                    color: accentLab,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.lab,
                  ),
                  _StatBlock(
                    label: 'HECHAS',
                    value: '$doneCount',
                    color: accentJournal,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'CAPTURAR'),
            ),
            const SizedBox(height: 12),

            // ── INPUT RÁPIDO ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CompositedTransformTarget(
                link: _layerLink,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _taskController,
                        focusNode: _focusNode,
                        style: bodyM.copyWith(color: inkColor(context)),
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: 'Escribe una tarea...',
                          hintStyle: bodyM.copyWith(color: inkGray),
                          filled: true,
                          fillColor: cardBackground(context),
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: inkBlack, width: borderWidthHeavy),
                          ),
                          enabledBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: inkBlack, width: borderWidthHeavy),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: inkBlack, width: borderWidthHeavy),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addQuickTask(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _addQuickTask,
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accentFight,
                          border: Border.all(color: inkBlack, width: borderWidth),
                          boxShadow: const [
                            BoxShadow(
                              color: inkBlack,
                              offset: shadowOffset,
                              blurRadius: shadowBlurRadius,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 24,
                          color: paperLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'PENDIENTES'),
            ),
            const SizedBox(height: 12),

            // ── LISTA PENDIENTES ──
            if (pendingTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: AppCard(
                  borderColor: inkGray.withAlpha(80),
                  backgroundColor: paperColor(context),
                  child: Center(
                    child: Text(
                      'NADA PENDIENTE',
                      style: labelBold.copyWith(color: inkGray.withAlpha(120)),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: pendingTasks.take(5).map((task) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TaskBlock(
                        task: task,
                        onToggle: () => ref.read(taskRepositoryProvider).markDone(task.id),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'NOTAS'),
            ),
            const SizedBox(height: 12),

            // ── LISTA CARPETAS ──
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: AppCard(
                  borderColor: inkGray.withAlpha(80),
                  backgroundColor: paperColor(context),
                  child: Center(
                    child: Text(
                      'SIN CARPETAS',
                      style: labelBold.copyWith(color: inkGray.withAlpha(120)),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: folders.take(4).map((folder) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FolderBlock(
                        folder: folder,
                        onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.flight,
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 24),

            // ── DOS CARDS DESTACADAS ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _HighlightCard(
                      label: 'PRÓXIMA TAREA',
                      value: nextTask?.content ?? 'NADA',
                      color: accentFight,
                      onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                      folder: nextTaskFolder,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HighlightCard(
                      label: 'CARPETA',
                      value: latestFolder?.name ?? 'SIN CARPETAS',
                      color: accentFlight,
                      onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.flight,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── BOTÓN IR AL TABLERO ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: accentFight,
                    border: Border.all(color: inkBlack, width: borderWidth),
                    boxShadow: const [
                      BoxShadow(
                        color: inkBlack,
                        offset: shadowOffset,
                        blurRadius: shadowBlurRadius,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'IR AL TABLERO',
                        style: labelBold.copyWith(
                          color: paperLight,
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: paperLight.withAlpha(220),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _greeting(int hour) {
    if (hour < 6) return 'Buenas noches';
    if (hour < 12) return 'Buenos días';
    if (hour < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String _formatDate(DateTime d) {
    const months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    return '${d.day} de ${months[d.month - 1]} de ${d.year}';
  }
}

// ── WIDGETS PRIVADOS ──

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _StatBlock({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 40) / 2,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: inkBlack, width: borderWidth),
          boxShadow: const [
            BoxShadow(
              color: inkBlack,
              offset: shadowOffset,
              blurRadius: shadowBlurRadius,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: displayL.copyWith(color: paperLight, height: 1.0),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: labelBold.copyWith(
                color: paperLight.withAlpha(220),
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskBlock extends ConsumerWidget {
  final domain_task.Task task;
  final VoidCallback onToggle;

  const _TaskBlock({required this.task, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = task.folderId != null
        ? ref.watch(folderByIdProvider(task.folderId!)).valueOrNull
        : null;

    final defaultStyle = bodyM.copyWith(color: inkColor(context));

    InlineSpan contentSpan;

    if (folder != null) {
      final text = task.content;
      final regex = RegExp(r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)');
      final matches = regex.allMatches(text).toList();
      final targetClean = removeAccents(folder.name.toLowerCase());

      final validMatches = matches.where((m) {
        final matchedName = m.group(1)!;
        return removeAccents(matchedName.toLowerCase()) == targetClean;
      }).toList();

      if (validMatches.isEmpty) {
        contentSpan = TextSpan(text: text, style: defaultStyle);
      } else {
        final spans = <InlineSpan>[];
        int lastIndex = 0;

        final mentionStyle = defaultStyle.copyWith(
          color: folder.color,
          fontWeight: FontWeight.bold,
        );

        for (final match in validMatches) {
          if (match.start > lastIndex) {
            spans.add(TextSpan(
              text: text.substring(lastIndex, match.start),
              style: defaultStyle,
            ));
          }
          final matchedText = match.group(0)!;
          final folderPart = matchedText.substring(1);
          spans.add(TextSpan(
            text: folderPart,
            style: mentionStyle,
          ));
          lastIndex = match.end;
        }

        if (lastIndex < text.length) {
          spans.add(TextSpan(
            text: text.substring(lastIndex),
            style: defaultStyle,
          ));
        }

        contentSpan = TextSpan(children: spans);
      }
    } else {
      contentSpan = TextSpan(text: task.content, style: defaultStyle);
    }

    return AppCard(
      onTap: onToggle,
      borderColor: inkColor(context),
      backgroundColor: cardBackground(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              border: Border.all(color: accentFight, width: borderWidth),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              contentSpan,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderBlock extends StatelessWidget {
  final dynamic folder;
  final VoidCallback onTap;

  const _FolderBlock({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderColor: inkColor(context),
      backgroundColor: cardBackground(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            color: folder.color as Color? ?? inkGray,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              folder.name as String? ?? '',
              style: bodyM.copyWith(color: inkColor(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_forward, size: 16, color: inkGray),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
  final Folder? folder;

  const _HighlightCard({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
    this.folder,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = bodyM.copyWith(
      color: paperLight,
      fontWeight: FontWeight.w700,
    );

    InlineSpan valueSpan;

    if (folder != null) {
      final text = value;
      final regex = RegExp(r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)');
      final matches = regex.allMatches(text).toList();
      final targetClean = removeAccents(folder!.name.toLowerCase());

      final validMatches = matches.where((m) {
        final matchedName = m.group(1)!;
        return removeAccents(matchedName.toLowerCase()) == targetClean;
      }).toList();

      if (validMatches.isEmpty) {
        valueSpan = TextSpan(text: text, style: defaultStyle);
      } else {
        final spans = <InlineSpan>[];
        int lastIndex = 0;

        final mentionColor = folder!.color == color ? paperLight : folder!.color;
        final mentionStyle = defaultStyle.copyWith(
          color: mentionColor,
          fontWeight: FontWeight.bold,
        );

        for (final match in validMatches) {
          if (match.start > lastIndex) {
            spans.add(TextSpan(
              text: text.substring(lastIndex, match.start),
              style: defaultStyle,
            ));
          }
          final matchedText = match.group(0)!;
          final folderPart = matchedText.substring(1);
          spans.add(TextSpan(
            text: folderPart,
            style: mentionStyle,
          ));
          lastIndex = match.end;
        }

        if (lastIndex < text.length) {
          spans.add(TextSpan(
            text: text.substring(lastIndex),
            style: defaultStyle,
          ));
        }

        valueSpan = TextSpan(children: spans);
      }
    } else {
      valueSpan = TextSpan(text: value, style: defaultStyle);
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: inkBlack, width: borderWidth),
          boxShadow: const [
            BoxShadow(
              color: inkBlack,
              offset: shadowOffset,
              blurRadius: shadowBlurRadius,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: labelBold.copyWith(
                color: paperLight.withAlpha(220),
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text.rich(
              valueSpan,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MentionPopup extends StatelessWidget {
  final List<Folder> folders;
  final void Function(Folder) onSelect;

  const _MentionPopup({required this.folders, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: inkColor(context), width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: inkColor(context),
            offset: shadowOffset,
            blurRadius: shadowBlurRadius,
          ),
        ],
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
                  Container(
                    width: 10,
                    height: 10,
                    color: f.color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    f.name,
                    style: labelBold.copyWith(color: inkColor(context)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
