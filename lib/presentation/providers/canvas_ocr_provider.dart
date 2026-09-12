import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/canvas_ocr.dart';
import '../../domain/repositories/canvas_ocr_repository.dart';
import '../../domain/repositories/drawing_stroke_repository.dart';
import '../../domain/services/ink_recognizer.dart';
import '../screens/flight/canvas_ocr_segmentation.dart';
import 'database_providers.dart';
import 'canvas_ocr_settings_provider.dart';
import 'ink_recognizer_provider.dart';

final canvasOcrVersionProvider = StateProvider<int>((ref) => 0);
final canvasOcrBlockVersionProvider = StateProvider.family<int, int>(
  (ref, id) => 0,
);
final canvasOcrStatusProvider = StateProvider<Map<int, String>>((ref) => {});
final canvasOcrPageProvider = FutureProvider.autoDispose
    .family<CanvasOcrPage?, int>((ref, id) {
      ref.watch(canvasOcrBlockVersionProvider(id));
      return ref.watch(canvasOcrRepositoryProvider).read(id);
    });

final Provider<CanvasOcrCoordinator> canvasOcrCoordinatorProvider =
    Provider<CanvasOcrCoordinator>((ref) {
      final service = CanvasOcrCoordinator(
        repository: ref.watch(canvasOcrRepositoryProvider),
        strokes: ref.watch(canvasOcrStrokeReaderProvider),
        recognizer: ref.watch(inkRecognizerProvider),
        automaticEnabled: false,
        spellingEnabled: false,
        onChanged: () => ref.read(canvasOcrVersionProvider.notifier).state++,
        onPageChanged:
            (id) =>
                ref.read(canvasOcrBlockVersionProvider(id).notifier).state++,
        onStatus: (id, status) {
          ref.read(canvasOcrStatusProvider.notifier).state = {
            ...ref.read(canvasOcrStatusProvider),
            id: status,
          };
        },
        supported:
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS),
      );
      ref.onDispose(service.dispose);
      ref.listen(canvasOcrSettingsProvider, (_, next) {
        service.configure(
          automatic: next.valueOrNull?.automatic ?? false,
          spelling: next.valueOrNull?.spelling ?? false,
        );
      }, fireImmediately: true);
      return service;
    });

class CanvasOcrCoordinator with WidgetsBindingObserver {
  final CanvasOcrRepository repository;
  final DrawingStrokeRepository strokes;
  final InkRecognizer recognizer;
  final VoidCallback onChanged;
  final void Function(int)? onPageChanged;
  final void Function(int, String)? onStatus;
  final bool supported;
  final SpellCheckService spellCheck;
  final Duration idleDelay;
  final Duration spellingRetryDelay;
  final Duration spellingCooldown;
  final _pending = <int>{};
  final _knownBlocks = <int>{};
  bool automaticEnabled;
  bool spellingEnabled;
  final _pointers = <int>{};
  final _retryTimers = <int, Timer>{};
  final _retryAttempts = <int, int>{};
  DateTime? _spellUnavailableUntil;
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;
  bool _foreground = true;
  int _generation = 0;
  DateTime _idleAfter = DateTime.now();

  CanvasOcrCoordinator({
    required this.repository,
    required this.strokes,
    required this.recognizer,
    required this.onChanged,
    this.onPageChanged,
    this.onStatus,
    this.supported = true,
    this.automaticEnabled = true,
    this.spellingEnabled = true,
    SpellCheckService? spellCheck,
    this.idleDelay = const Duration(seconds: 3),
    this.spellingRetryDelay = const Duration(seconds: 30),
    this.spellingCooldown = const Duration(seconds: 25),
  }) : spellCheck = spellCheck ?? DefaultSpellCheckService() {
    WidgetsBinding.instance.addObserver(this);
  }

  void configure({required bool automatic, required bool spelling}) {
    if (_disposed ||
        (automatic == automaticEnabled && spelling == spellingEnabled)) {
      return;
    }
    automaticEnabled = automatic;
    spellingEnabled = spelling;
    _generation++;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryAttempts.clear();
    _spellUnavailableUntil = null;
    _pending.addAll(_knownBlocks);
    _defer();
  }

  void schedule(int blockId) {
    if (_disposed || !supported) return;
    _knownBlocks.add(blockId);
    _retryTimers.remove(blockId)?.cancel();
    _retryAttempts.remove(blockId);
    _pending.add(blockId);
    _defer();
  }

  void _retrySpelling(int id) {
    final attempt = _retryAttempts[id] ?? 0;
    if (_disposed ||
        !spellingEnabled ||
        attempt >= 2 ||
        _retryTimers.containsKey(id)) {
      return;
    }
    _retryAttempts[id] = attempt + 1;
    _retryTimers[id] = Timer(spellingRetryDelay * (attempt + 1), () {
      _retryTimers.remove(id);
      if (_disposed) return;
      _pending.add(id);
      _defer();
    });
  }

  Future<void> _savePage(
    CanvasOcrPage page,
    List<CanvasOcrSegment> result,
    int generation,
  ) async {
    if (!_canRun(generation)) {
      if (!_disposed) _pending.add(page.blockId);
      return;
    }
    if (await repository.save(page.blockId, page.revision, result) &&
        !_disposed) {
      onChanged();
      onPageChanged?.call(page.blockId);
      final unchecked = result.any((s) => !s.spellingChecked);
      final warnings = result.any((s) => s.spelling.isNotEmpty);
      onStatus?.call(
        page.blockId,
        !spellingEnabled
            ? 'Texto actualizado · Revisión ortográfica desactivada'
            : unchecked
            ? 'Texto disponible · No se pudo revisar la ortografía. Comprueba el corrector español del dispositivo.'
            : warnings
            ? 'Texto actualizado · Hay sugerencias ortográficas'
            : 'Texto actualizado · Sin errores detectados',
      );
      if (unchecked) _retrySpelling(page.blockId);
    }
  }

  void pointerDown(int pointer) {
    _pointers.add(pointer);
    _generation++;
    _timer?.cancel();
  }

  void pointerUp(int pointer) {
    _pointers.remove(pointer);
    _defer();
  }

  void releasePointers() {
    _pointers.clear();
    _defer();
  }

  void _defer() {
    _idleAfter = DateTime.now().add(idleDelay);
    _timer?.cancel();
    if (!_disposed &&
        supported &&
        (automaticEnabled || spellingEnabled) &&
        _foreground &&
        _pointers.isEmpty &&
        _pending.isNotEmpty) {
      _timer = Timer(idleDelay, _drain);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _generation++;
    if (_foreground) {
      releasePointers();
    } else {
      _timer?.cancel();
    }
  }

  bool _canRun(int generation) =>
      !_disposed &&
      supported &&
      (automaticEnabled || spellingEnabled) &&
      _foreground &&
      _pointers.isEmpty &&
      generation == _generation &&
      !DateTime.now().isBefore(_idleAfter);

  Future<void> _drain() async {
    if (_running || !_canRun(_generation) || _pending.isEmpty) return;
    _running = true;
    final id = _pending.first;
    _pending.remove(id);
    final generation = _generation;
    try {
      final page = await repository.read(id);
      if (!_canRun(generation)) {
        if (!_disposed) _pending.add(id);
        return;
      }
      if (page == null) return;
      if (page.isCurrent &&
          page.segments.every((s) => s.alignmentVersion == 2)) {
        if (!spellingEnabled || page.segments.every((s) => s.spellingChecked)) {
          return;
        }
        final reviewed = <CanvasOcrSegment>[];
        for (final segment in page.segments) {
          if (!_canRun(generation)) break;
          reviewed.add(
            segment.spellingChecked
                ? segment
                : segment.reviewed(
                  await _spelling(
                    segment.effectiveText,
                    spellableWords: segment.spellableWords,
                  ),
                ),
          );
        }
        await _savePage(page, reviewed, generation);
        return;
      }
      if (!automaticEnabled) return;
      final ready = await recognizer.isModelReady('es');
      if (!_canRun(generation)) {
        if (!_disposed) _pending.add(id);
        return;
      }
      if (!ready) {
        if (!_disposed) {
          onStatus?.call(
            id,
            'Descarga español para activar el reconocimiento.',
          );
        }
        return;
      }
      if (!_disposed) onStatus?.call(id, 'Reconociendo escritura…');
      final cached = {for (final s in page.segments) s.hash: s};
      final result = <CanvasOcrSegment>[];
      var preContext = '';
      var position = -1;
      while (_canRun(generation)) {
        final records = await strokes.getByBlockAfterPosition(
          id,
          afterPosition: position,
          limit: 128,
        );
        if (!_canRun(generation)) break;
        if (records.isEmpty) {
          await _savePage(page, result, generation);
          return;
        }
        position = records.last.position;
        final groups = await compute(segmentCanvasInk, records);
        for (final group in groups) {
          if (!_canRun(generation)) break;
          final old = cached[group.hash];
          if (old != null && old.alignmentVersion == 2) {
            final reused =
                old.spellingChecked
                    ? old
                    : old.reviewed(
                      await _spelling(
                        old.effectiveText,
                        spellableWords: old.spellableWords,
                      ),
                    );
            result.add(reused);
            preContext = _appendOcrContext(preContext, reused.effectiveText);
            continue;
          }
          final candidates = await recognizer.recognize(
            group.strokes,
            langTag: 'es',
            writingArea: Size(
              math.max(1, group.bounds.width),
              math.max(12, group.bounds.height),
            ),
            preContext: preContext,
          );
          if (!_canRun(generation)) break;
          final raw =
              candidates.isEmpty
                  ? old?.text ?? ''
                  : candidates.first.text.trim();
          final text = raw.length > 8000 ? raw.substring(0, 8000) : raw;
          final effective = old?.effectiveText ?? text;
          final words =
              old?.correctedText != null
                  ? const <CanvasOcrWord>[]
                  : alignCanvasWords(group, text);
          final spellableWords = stableCanvasOcrWords(
            words,
            text,
            candidates.map((candidate) => candidate.text.trim()).toList(),
          );
          final spelling = await _spelling(
            effective,
            spellableWords: spellableWords,
          );
          final segment = CanvasOcrSegment(
            hash: group.hash,
            bounds: group.bounds,
            text: text,
            correctedText: old?.correctedText,
            words: words,
            spellableWords: spellableWords,
            alignmentVersion: 2,
            spellingChecked: spelling != null,
            spelling: spelling ?? const [],
          );
          result.add(segment);
          preContext = _appendOcrContext(preContext, segment.effectiveText);
        }
        if (result.length > 10000) {
          if (!_disposed) {
            onStatus?.call(
              id,
              'Demasiada escritura para indexar este lienzo. Usa el OCR del lazo.',
            );
          }
          return;
        }
      }
      if (!_disposed) _pending.add(id);
    } catch (_) {
      if (!_disposed) {
        onStatus?.call(
          id,
          'No se pudo reconocer. Se reintentará al editar o abrir la nota.',
        );
      }
    } finally {
      _running = false;
      if (!_disposed) _defer();
    }
  }

  Future<List<OcrSpellingSuggestion>?> _spelling(
    String text, {
    List<CanvasOcrWord>? spellableWords,
  }) async {
    if (!spellingEnabled) return null;
    if (text.isEmpty) return [];
    if (spellableWords?.isEmpty == true) return [];
    if (_spellUnavailableUntil != null &&
        DateTime.now().isBefore(_spellUnavailableUntil!)) {
      return null;
    }
    try {
      final spans = await spellCheck
          .fetchSpellCheckSuggestions(const Locale('es'), text)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (spans == null) {
        _spellUnavailableUntil = DateTime.now().add(spellingCooldown);
        return null;
      }
      return [
        for (final s in spans)
          if (s.range.start >= 0 &&
              s.range.end <= text.length &&
              s.range.end > s.range.start &&
              (spellableWords == null ||
                  spellableWords.any(
                    (word) =>
                        word.start == s.range.start && word.end == s.range.end,
                  )) &&
              !s.suggestions.any(
                (value) =>
                    value.toLowerCase() ==
                    text.substring(s.range.start, s.range.end).toLowerCase(),
              ))
            OcrSpellingSuggestion(
              s.range.start,
              s.range.end,
              s.suggestions
                  .where((v) => v.isNotEmpty && v.length <= 128)
                  .take(4)
                  .toList(),
            ),
      ];
    } catch (_) {
      _spellUnavailableUntil = DateTime.now().add(spellingCooldown);
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
  }
}

String _appendOcrContext(String previous, String current) {
  final combined = '$previous ${current.trim()}'.trim();
  return combined.length <= 20
      ? combined
      : combined.substring(combined.length - 20);
}
