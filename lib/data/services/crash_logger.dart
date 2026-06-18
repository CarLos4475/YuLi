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

  /// Master switch for PERF instrumentation ([note]). OFF in production.
  ///
  /// When false, [note] is a complete no-op (no file write, no logcat) AND every
  /// caller MUST guard its prep with `if (CrashLogger.perfLogging)` so the
  /// expensive bits that exist ONLY to feed a note — `_pointCount` over every
  /// stroke, the per-frame timings callback, the per-save DB stats query — never
  /// run. That keeps the instrumentation in the tree (flip this to true to
  /// measure) while costing nothing on hot paths and never filling the in-app
  /// crash log. Real errors ([record]) persist regardless of this flag.
  static const bool perfLogging = false;

  /// Narrow probe switch for the cuaderno chunk-ring "missing tile-shaped chunk"
  /// bug. Separate from [perfLogging] so we can collect just this data without
  /// turning on the whole PERF firehose. [diag] only fires on the rare anomalous
  /// event (a blank tile over an inked/decoding page, or an inked page with no
  /// base image), so volume stays low. Set false once the bug is closed.
  static const bool chunkDiag = false;

  // When perf is being measured, also mirror [record] errors to logcat. Errors
  // always hit the durable file either way.
  static const bool _mirrorToLogcat = false;
  void _logcat(String message) {
    // Flutter routes stdout to logcat (tag 'flutter') even in release, unlike
    // dart:developer.log (service-protocol only → invisible in release).
    // ignore: avoid_print
    if (_mirrorToLogcat) print('YULILOG $message');
  }

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
    _logcat('ERROR${context.isEmpty ? '' : ' · $context'}: $error');
    _appendRaw(entry.toString());
  }

  /// Lightweight timestamped note (diagnostics / perf instrumentation). Like
  /// [record] but for plain messages, not errors. No-op unless [perfLogging] is
  /// on; when on it goes to BOTH the durable file and logcat. Fire-and-forget,
  /// never throws.
  void note(String message) {
    if (!perfLogging) return;
    // ignore: avoid_print
    print('YULILOG $message');
    _appendRaw('[${DateTime.now().toIso8601String()}] $message\n');
  }

  /// Like [note] but gated by [chunkDiag] instead of [perfLogging], and it always
  /// persists to the durable file (the probe must survive even with perf off).
  /// Fire-and-forget, never throws.
  void diag(String message) {
    if (!chunkDiag) return;
    // ignore: avoid_print
    print('YULILOG CHUNKDIAG $message');
    _appendRaw('[${DateTime.now().toIso8601String()}] CHUNKDIAG $message\n');
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
