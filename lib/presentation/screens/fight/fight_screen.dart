import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../providers/task_providers.dart';
import '../../widgets/app_section_divider.dart';
import '../../widgets/coach_mark.dart';
import '../../../domain/models/task.dart';
import '../../../domain/models/notification_item.dart';
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

class _FightHeader extends ConsumerWidget {
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
                  Text('FIGHT', style: displayM.copyWith(color: accentFight)),
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
                label: 'CAPTURA',
                body: 'Escribe tareas con hasta 280 caracteres. '
                    'Usa @NombreDeCarpeta para asignarla a una carpeta. '
                    'El @ no cuenta para el límite.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                label: 'ESTADOS',
                body: 'Las tareas nuevas aparecen en Pendientes. '
                    'Al día siguiente pasan a De Ayer. '
                    'Un día después se archivan y van a la papelera. '
                    'Se borran definitivamente a los 7 días.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                label: 'FECHA LÍMITE',
                body: 'Toca el reloj en una tarea para asignarle fecha y hora. '
                    'Si tiene fecha límite, su ciclo de vida depende de esa fecha '
                    'en vez de la fecha de creación: pasará a De Ayer cuando '
                    'venza, y se archivará un día después.',
              ),
              const SizedBox(height: 12),
              _HelpSection(
                label: 'ACCIONES',
                body: 'Swipe derecha = completar. '
                    'Swipe izquierda = papelera. '
                    'Long press = enviar a Lab como tarjeta Kanban '
                    '(con su fecha límite incluida).',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationsDialog(BuildContext context, WidgetRef ref) {
    final notifications = ref.read(notificationsProvider).valueOrNull ?? [];

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
                  Text('Notificaciones',
                      style: displayM.copyWith(color: accentFight)),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: paperColor(ctx),
                        border:
                            Border.all(color: inkBlack, width: borderWidth),
                        boxShadow: const [
                          BoxShadow(
                            color: inkBlack,
                            offset: shadowOffset,
                            blurRadius: shadowBlurRadius,
                          ),
                        ],
                      ),
                      child:
                          const Icon(Icons.close, size: 14, color: inkBlack),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (notifications.isEmpty)
                Text('Sin notificaciones.',
                    style: bodyM.copyWith(color: inkGray))
              else
                ...notifications.map((n) => _NotificationTile(notification: n)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider).valueOrNull ?? [];
    final hasNotifications = notifications.isNotEmpty;

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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        _showNotificationsDialog(context, ref),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accentFlight,
                        border:
                            Border.all(color: inkBlack, width: borderWidth),
                        boxShadow: const [
                          BoxShadow(
                            color: inkBlack,
                            offset: shadowOffset,
                            blurRadius: shadowBlurRadius,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.notifications_none,
                          size: 18, color: paperLight),
                    ),
                  ),
                  if (hasNotifications)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: paperLight,
                          border: Border.all(
                              color: inkBlack, width: borderWidth),
                        ),
                        child: Center(
                          child: Text(
                            '${notifications.length}',
                            style: labelBold.copyWith(
                                color: inkBlack, fontSize: 8),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
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

class _NotificationTile extends ConsumerWidget {
  final NotificationItem notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(notification.message,
                style: bodyM.copyWith(color: inkColor(context))),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              ref
                  .read(notificationRepositoryProvider)
                  .delete(notification.id);
            },
            child: Container(
              width: 20,
              height: 20,
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
              child:
                  const Icon(Icons.close, size: 12, color: inkBlack),
            ),
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
        Text(label, style: labelBold.copyWith(color: accentFight)),
        const SizedBox(height: 2),
        Text(body, style: bodyM.copyWith(color: inkColor(context))),
      ],
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
