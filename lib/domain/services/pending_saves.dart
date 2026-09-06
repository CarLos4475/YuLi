import 'dart:async';

class PendingSaves {
  static final _scheduled = <Object, Future<void> Function()>{};
  static final _running = <Future<void>>{};
  static final _failures = <Object, Object>{};

  static void schedule(Object owner, Future<void> Function() save) =>
      _scheduled[owner] = save;
  static void unschedule(Object owner) => _scheduled.remove(owner);

  static void failed(Object owner, Object error) => _failures[owner] = error;
  static void saved(Object owner) => _failures.remove(owner);

  static Future<void> track(Future<void> work, {Object? owner}) {
    _running.add(work);
    work.then(
      (_) {
        _running.remove(work);
        if (owner != null) saved(owner);
      },
      onError: (Object error, StackTrace stack) {
        _running.remove(work);
        failed(owner ?? work, error);
      },
    );
    return work;
  }

  static Future<void> flush() async {
    while (_scheduled.isNotEmpty || _running.isNotEmpty) {
      final saves = _scheduled.entries.toList();
      for (final entry in saves) {
        if (_scheduled[entry.key] != entry.value) continue;
        _scheduled.remove(entry.key);
        await entry.value();
      }
      if (_running.isNotEmpty) await Future.wait(_running.toList());
    }
    if (_failures.isNotEmpty) {
      throw StateError(
        'Un guardado falló. Revisa el apunte antes de respaldar.',
      );
    }
  }
}
