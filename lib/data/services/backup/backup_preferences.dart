import 'package:shared_preferences/shared_preferences.dart';

bool isBackupPreference(String key) {
  const exact = {
    'theme_mode',
    'pinned_folder_ids',
    'pinned_note_ids',
    'flight_workspace_tabs_v1',
    'flight_workspace_expansion_v1',
    'ai_custom_modes_v1',
    'yuli_user_memory_v1',
    'ai_chat_settings_global_v1',
  };
  const prefixes = [
    'draw_',
    'lab_space_tabs_',
    'reminders_',
    'ai_ctx_v1_',
    'ai_related_ctx_v1_',
    'ai_chat_settings_v1_',
    'ai_mode_v1_',
    'ai_url_v1_',
  ];
  return exact.contains(key) || prefixes.any(key.startsWith);
}

Map<String, Object> exportBackupPreferences(SharedPreferences prefs) => {
  for (final key in prefs.getKeys())
    if (isBackupPreference(key) && prefs.get(key) != null) key: prefs.get(key)!,
};

Future<void> importBackupPreferences(
  SharedPreferences prefs,
  Map<String, dynamic> values,
) async {
  for (final key in prefs.getKeys().where(isBackupPreference).toList()) {
    if (!await prefs.remove(key)) {
      throw StateError('No se pudieron restaurar preferencias.');
    }
  }
  for (final entry in values.entries) {
    if (!isBackupPreference(entry.key)) continue;
    final bool success;
    final value = entry.value;
    if (value is bool) {
      success = await prefs.setBool(entry.key, value);
    } else if (value is int) {
      success = await prefs.setInt(entry.key, value);
    } else if (value is double) {
      success = await prefs.setDouble(entry.key, value);
    } else if (value is String) {
      success = await prefs.setString(entry.key, value);
    } else if (value is List && value.every((v) => v is String)) {
      success = await prefs.setStringList(entry.key, value.cast<String>());
    } else {
      throw StateError('Preferencia de respaldo inválida.');
    }
    if (!success) throw StateError('No se pudieron restaurar preferencias.');
  }
}
