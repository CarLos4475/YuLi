import 'package:shared_preferences/shared_preferences.dart';

class WhiteboardPrefs {
  static const _lastCanvasPrefix = 'whiteboard_last_canvas_v1_';

  static Future<int?> loadLastCanvas(int noteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('$_lastCanvasPrefix$noteId');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveLastCanvas(int noteId, int blockId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.setInt('$_lastCanvasPrefix$noteId', blockId);
    } catch (_) {
      return false;
    }
  }
}
