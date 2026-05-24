import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/task_providers.dart';
import '../../widgets/app_section_divider.dart';
import '../../widgets/coach_mark.dart';
import '../../../domain/models/task.dart';
import 'fight_input.dart';
import 'task_card.dart';

class FightScreen extends ConsumerWidget {
  const FightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingTasksProvider);
    final yesterdayAsync = ref.watch(yesterdayTasksProvider);
    final doneTodayAsync = ref.watch(doneTodayTasksProvider);

    return Column(
      children: [
        _FightHeader(),
        Expanded(
          child: _TaskList(
            pendingAsync: pendingAsync,
            yesterdayAsync: yesterdayAsync,
            doneTodayAsync: doneTodayAsync,
          ),
        ),
      ],
    );
  }
}

class _FightHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: accentFight,
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
                    Text(
                      'FIGHT',
                      style: displayXL.copyWith(color: inkLight),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Modo de captura',
                      style: bodyS.copyWith(color: inkLight.withAlpha(180)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CoachMark(
            flagKey: 'fight_intro',
            message: 'Escribe aquí. 280 chars. Usa @ para asignar carpeta.',
            position: CoachMarkPosition.below,
            child: const FightInput(),
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  final AsyncValue<List<Task>> pendingAsync;
  final AsyncValue<List<Task>> yesterdayAsync;
  final AsyncValue<List<Task>> doneTodayAsync;

  const _TaskList({
    required this.pendingAsync,
    required this.yesterdayAsync,
    required this.doneTodayAsync,
  });

  @override
  Widget build(BuildContext context) {
    final pending = pendingAsync.valueOrNull ?? [];
    final yesterday = yesterdayAsync.valueOrNull ?? [];
    final doneToday = doneTodayAsync.valueOrNull ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ...pending.map((t) => TaskCard(task: t, isYesterday: false)),
        if (yesterday.isNotEmpty) ...[
          AppSectionDivider(label: 'DE AYER'),
          ...yesterday.map((t) => TaskCard(task: t, isYesterday: true)),
        ],
        if (doneToday.isNotEmpty) ...[
          AppSectionDivider(label: 'COMPLETADAS HOY'),
          ...doneToday.map((t) => TaskCard(task: t, isYesterday: false, isDone: true)),
        ],
      ],
    );
  }
}
