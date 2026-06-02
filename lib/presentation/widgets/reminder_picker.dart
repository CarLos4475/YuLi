import 'package:flutter/material.dart';

import '../../domain/models/reminder_preset.dart';
import '../theme/app_tokens.dart';
import 'yuli_design.dart' as y;

class ReminderSelection {
  final DateTime? remindAt;
  final ReminderPreset? preset;

  const ReminderSelection(this.remindAt, this.preset);
}

Future<ReminderSelection?> showReminderPicker(
  BuildContext context, {
  required Color accent,
  DateTime? dueDate,
  DateTime? currentRemindAt,
}) async {
  final action = await showDialog<String>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: y.yCream,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text(
            'Recordatorio',
            style: y.ySans(size: 18, weight: FontWeight.w700, color: y.yInk),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (currentRemindAt != null) ...[
                Text(
                  'Actual: ${formatReminderTime(currentRemindAt)}',
                  style: y.yBody(size: 13, color: y.yInk),
                ),
                const SizedBox(height: 10),
              ],
              if (dueDate != null) ...[
                _OptionButton(
                  label: 'A LA HORA',
                  accent: accent,
                  value: 'at_due',
                ),
                const SizedBox(height: 6),
                _OptionButton(
                  label: '30 MIN ANTES',
                  accent: accent,
                  value: '30m',
                ),
                const SizedBox(height: 6),
                _OptionButton(
                  label: '1 DIA ANTES',
                  accent: accent,
                  value: '1d',
                ),
                const SizedBox(height: 6),
              ],
              _OptionButton(
                label: 'ELEGIR FECHA/HORA',
                accent: accent,
                value: 'custom',
              ),
              if (currentRemindAt != null) ...[
                const SizedBox(height: 10),
                _OptionButton(
                  label: 'BORRAR',
                  accent: accentFight,
                  value: 'clear',
                  filled: false,
                ),
              ],
            ],
          ),
        ),
  );
  if (action == null || !context.mounted) return null;
  return switch (action) {
    'at_due' => ReminderSelection(dueDate, ReminderPreset.atDue),
    '30m' => ReminderSelection(
      dueDate?.subtract(const Duration(minutes: 30)),
      ReminderPreset.before30m,
    ),
    '1d' => ReminderSelection(
      dueDate?.subtract(const Duration(days: 1)),
      ReminderPreset.before1d,
    ),
    'clear' => const ReminderSelection(null, null),
    'custom' => _pickCustom(context, currentRemindAt ?? dueDate),
    _ => null,
  };
}

Future<ReminderSelection?> _pickCustom(
  BuildContext context,
  DateTime? initial,
) async {
  final now = DateTime.now();
  final base = initial != null && initial.isAfter(now) ? initial : now;
  final date = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365 * 5)),
    builder:
        (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            datePickerTheme: const DatePickerThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          ),
          child: child!,
        ),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
    builder:
        (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            timePickerTheme: const TimePickerThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          ),
          child: child!,
        ),
  );
  if (time == null) return null;
  return ReminderSelection(
    DateTime(date.year, date.month, date.day, time.hour, time.minute),
    ReminderPreset.custom,
  );
}

String formatReminderTime(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  final time =
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return 'HOY $time';
  if (diff == 1) return 'MANANA $time';
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')} $time';
}

/// Aviso cuando se fija un recordatorio pero las notificaciones del sistema
/// están apagadas (no se mostraría). Ofrece abrir los ajustes de notificación.
void showNotificationsDisabledSnack(
  BuildContext context, {
  required VoidCallback onOpenSettings,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: y.yInk,
      duration: const Duration(seconds: 6),
      content: Text(
        'Notificaciones desactivadas: el recordatorio no se mostrará.',
        style: y.yBody(size: 13, color: y.yCream),
      ),
      action: SnackBarAction(
        label: 'ACTIVAR',
        textColor: accentFight,
        onPressed: onOpenSettings,
      ),
    ),
  );
}

class _OptionButton extends StatelessWidget {
  final String label;
  final Color accent;
  final String value;
  final bool filled;

  const _OptionButton({
    required this.label,
    required this.accent,
    required this.value,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context, value),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? accent : y.yCream,
          border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
        ),
        child: Text(
          label,
          style: y.yMono(
            size: 10,
            weight: FontWeight.w700,
            tracking: 1.1,
            color: filled ? y.yCream : y.yInk,
          ),
        ),
      ),
    );
  }
}
