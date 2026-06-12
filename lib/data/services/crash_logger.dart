import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists uncaught Dart errors to a file so crashes can be inspected/shared
/// later (the app folder is private storage on Android — not browsable). Wire
/// it from main(): FlutterError.onError + PlatformDispatcher.onError + the
/// guarded zone all funnel into [record].
///
/// Caveat: captures Dart-level errors only (the red-screen / silent-failure
/// kind). Native plugin crashes need platform tooling.
class CrashLogger {
  CrashLogger._();
  static final CrashLogger instance = CrashLogger._();

  File? _file;
  Future<void> _writeTail = Future.value();
  static const _maxBytes = 256 * 1024; // ~256 KB, then trimmed to half

  Future<void> init() async {
    try {
      final dir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'diagnostics'),
      );
      await dir.create(recursive: true);
      _file = File(p.join(dir.path, 'crash.log'));
      await _appendRaw(
        '\n===== Sesión iniciada ${DateTime.now().toIso8601String()} '
        '(${Platform.operatingSystem}) =====\n',
      );
    } catch (_) {
      // Logging must never take down the app.
    }
  }

  /// Fire-and-forget. Safe to call from error handlers; never throws.
  void record(Object error, StackTrace? stack, {String context = ''}) {
    final ts = DateTime.now().toIso8601String();
    final entry =
        StringBuffer()
          ..writeln('──────────────────────────────────────')
          ..writeln('[$ts]${context.isEmpty ? '' : ' · $context'}')
          ..writeln(error.toString())
          ..writeln(stack?.toString() ?? '(sin stack trace)')
          ..writeln();
    _appendRaw(entry.toString());
  }

  /// Lightweight timestamped note (diagnostics / perf instrumentation). Like
  /// [record] but for plain messages, not errors. Fire-and-forget, never throws.
  void note(String message) {
    _appendRaw('[${DateTime.now().toIso8601String()}] $message\n');
  }

  Future<void> _appendRaw(String text) {
    final write = _writeTail.then(
      (_) => _appendRawNow(text),
      onError: (_) => _appendRawNow(text),
    );
    _writeTail = write.catchError((_) {});
    return write;
  }

  Future<void> _appendRawNow(String text) async {
    try {
      final f = _file;
      if (f == null) return;
      await f.writeAsString(text, mode: FileMode.append, flush: true);
      if (await f.length() > _maxBytes) {
        final content = await f.readAsString();
        // Keep the most recent half so the file stays bounded.
        await f.writeAsString(
          content.substring(content.length - _maxBytes ~/ 2),
        );
      }
    } catch (_) {}
  }

  Future<String> read() async {
    try {
      await _writeTail;
      final f = _file;
      if (f != null && await f.exists()) return await f.readAsString();
    } catch (_) {}
    return '';
  }

  Future<void> clear() async {
    try {
      await _writeTail;
      await _file?.writeAsString('');
    } catch (_) {}
  }

  String? get path => _file?.path;
}
