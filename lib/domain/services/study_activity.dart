import 'dart:async';

class StudyActivity {
  static final editors = <Object>{};

  static final _opportunities = StreamController<int>.broadcast(sync: true);

  static Stream<int> get opportunities => _opportunities.stream;

  static void enter(Object editor) {
    editors.add(editor);
  }

  static void leave(Object editor, int noteId) {
    if (editors.remove(editor)) _opportunities.add(noteId);
  }

  static void leaveUnit(int noteId) {
    _opportunities.add(noteId);
  }
}
