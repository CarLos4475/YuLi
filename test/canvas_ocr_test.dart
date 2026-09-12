import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_canvas_ocr_repository.dart';
import 'package:yuli/data/repositories/local/local_drawing_stroke_repository.dart';
import 'package:yuli/data/repositories/local/local_note_block_repository.dart';
import 'package:yuli/domain/models/canvas_ocr.dart';
import 'package:yuli/domain/models/drawing_stroke_record.dart';
import 'package:yuli/domain/models/note_block.dart';
import 'package:yuli/domain/services/ink_recognizer.dart';
import 'package:yuli/presentation/providers/canvas_ocr_provider.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/providers/ink_recognizer_provider.dart';
import 'package:yuli/presentation/screens/flight/canvas_ocr_segmentation.dart';
import 'package:yuli/presentation/screens/flight/drawing_stroke_persistence.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';

class _Ink implements InkRecognizer {
  int calls = 0;
  final contexts = <String>[];
  Completer<List<InkCandidate>>? pending;
  final started = Completer<void>();
  @override
  Future<List<InkCandidate>> recognize(
    List<List<Offset>> strokes, {
    String langTag = 'es',
    InkRecognitionMode mode = InkRecognitionMode.text,
    Size? writingArea,
    String preContext = '',
  }) async {
    calls++;
    contexts.add(preContext);
    if (!started.isCompleted) started.complete();
    if (pending != null) return pending!.future;
    return const [
      InkCandidate('Canción', 0),
      InkCandidate('Canción', 1),
      InkCandidate('Cancion', 2),
    ];
  }

  @override
  Future<bool> isModelReady(String langTag) async => true;
  @override
  Future<bool> downloadModel(String langTag) async => true;
  @override
  Future<bool> deleteModel(String langTag) async => true;
}

class _Spelling implements SpellCheckService {
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async => [];
}

class _RecoveringSpelling implements SpellCheckService {
  int calls = 0;
  final bool alwaysFail;
  _RecoveringSpelling({this.alwaysFail = false});
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    calls++;
    return alwaysFail || calls == 1 ? null : [];
  }
}

class _CaseOnlySpelling implements SpellCheckService {
  int calls = 0;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    calls++;
    return [
      const SuggestionSpan(TextRange(start: 0, end: 7), ['canción']),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late LocalCanvasOcrRepository ocr;
  late LocalDrawingStrokeRepository strokes;
  late LocalNoteBlockRepository blocks;
  late int noteId;
  late int blockId;
  late int folderId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ocr = LocalCanvasOcrRepository(db);
    strokes = LocalDrawingStrokeRepository(db);
    blocks = LocalNoteBlockRepository(db);
    folderId = await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(name: 'Estudio', color: '#FFFFFF'));
    noteId = await db
        .into(db.notes)
        .insert(NotesCompanion.insert(folderId: folderId));
    blockId = (await blocks.insertAtEnd(noteId, NoteBlockType.drawing)).id;
  });
  tearDown(() => db.close());

  DrawingStroke pen(double x, double y) => DrawingStroke(
    colorValue: 0xFF000000,
    strokeWidth: 2,
    points: StrokePoints.fromNested([
      [x, y],
      [x + 8, y + 12],
    ]),
  );

  test(
    'switches pause recognition and independently review cached text',
    () async {
      await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
      final engine = _Ink();
      final checker = _RecoveringSpelling();
      var completion = Completer<void>();
      final service = CanvasOcrCoordinator(
        repository: ocr,
        strokes: strokes,
        recognizer: engine,
        spellCheck: checker,
        automaticEnabled: false,
        spellingEnabled: false,
        idleDelay: const Duration(milliseconds: 10),
        spellingRetryDelay: const Duration(milliseconds: 20),
        spellingCooldown: const Duration(milliseconds: 5),
        onChanged: () {
          if (!completion.isCompleted) completion.complete();
        },
      );
      addTearDown(service.dispose);
      service.schedule(blockId);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(engine.calls, 0);
      expect(checker.calls, 0);
      service.configure(automatic: true, spelling: false);
      await completion.future.timeout(const Duration(seconds: 10));
      expect(engine.calls, 1);
      expect(checker.calls, 0);
      expect((await ocr.read(blockId))!.segments.single.spellingChecked, false);
      completion = Completer<void>();
      service.configure(automatic: false, spelling: true);
      await completion.future.timeout(const Duration(seconds: 10));
      expect(checker.calls, 1);
      service.configure(automatic: false, spelling: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(checker.calls, 1);
      expect(engine.calls, 1);
      expect((await ocr.search('cancion')), hasLength(1));
    },
  );

  test(
    'v27 upgrade preserves existing notes and starts with an empty OCR cache',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yuli_ocr_migration_',
      );
      final file = File('${directory.path}/test.sqlite');
      final before = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final fid = await before
            .into(before.folders)
            .insert(
              FoldersCompanion.insert(name: 'Conservar', color: '#FFFFFF'),
            );
        final nid = await before
            .into(before.notes)
            .insert(
              NotesCompanion.insert(
                folderId: fid,
                rawMarkdown: const Value('Mi nota'),
              ),
            );
        await before.customStatement('DROP TABLE canvas_ocr_pages');
        await before.customStatement('PRAGMA user_version = 27');
        await before.close();
        final after = AppDatabase.forTesting(NativeDatabase(file));
        try {
          final note =
              await (after.select(after.notes)
                ..where((n) => n.id.equals(nid))).getSingle();
          expect(note.rawMarkdown, 'Mi nota');
          expect(await after.select(after.canvasOcrPages).get(), isEmpty);
          final version =
              await after.customSelect('PRAGMA user_version').getSingle();
          expect(version.read<int>('user_version'), 28);
        } finally {
          await after.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('disabling during native recognition discards the result', () async {
    await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
    final engine = _Ink()..pending = Completer<List<InkCandidate>>();
    final checker = _RecoveringSpelling();
    var saves = 0;
    final service = CanvasOcrCoordinator(
      repository: ocr,
      strokes: strokes,
      recognizer: engine,
      spellCheck: checker,
      idleDelay: const Duration(milliseconds: 10),
      onChanged: () => saves++,
    );
    addTearDown(service.dispose);
    service.schedule(blockId);
    await engine.started.future.timeout(const Duration(seconds: 10));
    service.configure(automatic: false, spelling: false);
    engine.pending!.complete([const InkCandidate('Descartar', 0)]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(saves, 0);
    expect(checker.calls, 0);
    expect((await ocr.read(blockId))!.isCurrent, false);
  });

  test('case-only spell checker suggestions are not underlined', () async {
    await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
    final checker = _CaseOnlySpelling();
    final completed = Completer<void>();
    final service = CanvasOcrCoordinator(
      repository: ocr,
      strokes: strokes,
      recognizer: _Ink(),
      spellCheck: checker,
      idleDelay: const Duration(milliseconds: 10),
      onChanged: completed.complete,
    );
    addTearDown(service.dispose);
    service.schedule(blockId);
    await completed.future.timeout(const Duration(seconds: 10));
    final page = (await ocr.read(blockId))!;
    expect(checker.calls, 1);
    expect(page.segments.single.spelling, isEmpty);
    expect(page.segments.single.spellingChecked, true);
  });

  test(
    'Failed spelling retries a current transcription without recognizing ink again',
    () async {
      await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
      final engine = _Ink();
      final checker = _RecoveringSpelling();
      final completed = Completer<void>();
      final statuses = <String>[];
      var saves = 0;
      final service = CanvasOcrCoordinator(
        repository: ocr,
        strokes: strokes,
        recognizer: engine,
        spellCheck: checker,
        idleDelay: const Duration(milliseconds: 10),
        spellingRetryDelay: const Duration(milliseconds: 30),
        spellingCooldown: const Duration(milliseconds: 10),
        onChanged: () {
          if (++saves == 2) completed.complete();
        },
        onStatus: (_, status) => statuses.add(status),
      );
      addTearDown(service.dispose);
      service.schedule(blockId);
      await completed.future.timeout(const Duration(seconds: 10));
      expect(engine.calls, 1);
      expect(checker.calls, 2);
      expect(
        (await ocr.read(blockId))!.segments.single.spellingChecked,
        isTrue,
      );
      expect(statuses.any((s) => s.contains('No se pudo revisar')), isTrue);
      expect(statuses.last, contains('Sin errores detectados'));
    },
  );

  test(
    'Unavailable spelling stops after two automatic retries and remains unchecked',
    () async {
      await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
      final checker = _RecoveringSpelling(alwaysFail: true);
      final engine = _Ink();
      final completed = Completer<void>();
      var saves = 0;
      final service = CanvasOcrCoordinator(
        repository: ocr,
        strokes: strokes,
        recognizer: engine,
        spellCheck: checker,
        idleDelay: const Duration(milliseconds: 10),
        spellingRetryDelay: const Duration(milliseconds: 20),
        spellingCooldown: const Duration(milliseconds: 5),
        onChanged: () {
          if (++saves == 3) completed.complete();
        },
      );
      addTearDown(service.dispose);
      service.schedule(blockId);
      await completed.future.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(checker.calls, 3);
      expect(saves, 3);
      expect(engine.calls, 1);
      expect(
        (await ocr.read(blockId))!.segments.single.spellingChecked,
        isFalse,
      );
    },
  );

  test('production providers schedule OCR after committing ink', () async {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        inkRecognizerProvider.overrideWithValue(_Ink()),
      ],
    );
    addTearDown(container.dispose);
    final repository = container.read(drawingStrokeRepositoryProvider);
    await repository.insert(blockId, strokeWrite(0, pen(0, 0)));
    expect(container.read(canvasOcrVersionProvider), 1);
    expect((await ocr.read(blockId))!.isCurrent, isFalse);
    expect(await repository.getByBlock(blockId), hasLength(1));
  });

  CanvasOcrSegment segment(String text) => CanvasOcrSegment(
    hash: 'test',
    bounds: const Rect.fromLTWH(0, 0, 10, 20),
    text: text,
  );

  test(
    'search normalizes accents, rejects stale results and hides trash',
    () async {
      final id = await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
      final page = (await ocr.read(blockId))!;
      expect(
        await ocr.save(blockId, page.revision, [segment('Canción')]),
        isTrue,
      );
      expect((await ocr.search('cancion')).single.blockId, blockId);
      expect(await ocr.search("' OR 1=1 --"), isEmpty);
      await strokes.update(id, strokeWrite(0, pen(100, 100)));
      expect(await ocr.search('cancion'), isEmpty);
      expect(
        await ocr.save(blockId, page.revision, [segment('Viejo')]),
        isFalse,
      );
      final fresh = (await ocr.read(blockId))!;
      expect(
        await ocr.save(blockId, fresh.revision, [segment('Nuevo')]),
        isTrue,
      );
      await (db.update(db.notes)..where(
        (n) => n.id.equals(noteId),
      )).write(NotesCompanion(deletedAt: Value(DateTime.now())));
      expect(await ocr.search('nuevo'), isEmpty);
      expect(await ocr.contextForNote(noteId), isEmpty);
      expect(
        await ocr.save(blockId, fresh.revision, [segment('Nuevo')]),
        isFalse,
      );
    },
  );

  test('deleting strokes invalidates even when no ink remains', () async {
    final id = await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
    final page = (await ocr.read(blockId))!;
    await ocr.save(blockId, page.revision, [segment('Texto')]);
    await strokes.deleteByIds([id]);
    expect(await ocr.search('Texto'), isEmpty);
    expect((await ocr.read(blockId))!.isCurrent, isFalse);
  });

  test('block and note cascades remove OCR with foreign keys off', () async {
    await ocr.read(blockId);
    await blocks.delete(blockId);
    expect(await db.select(db.canvasOcrPages).get(), isEmpty);
    expect(await ocr.read(blockId), isNull);
    final second = (await blocks.insertAtEnd(noteId, NoteBlockType.drawing)).id;
    await ocr.read(second);
    await db.hardDeleteNoteCascade(noteId);
    expect(await db.select(db.canvasOcrPages).get(), isEmpty);
    expect(await ocr.read(second), isNull);
  });

  test(
    'folder cascade removes OCR and pending writes cannot resurrect it',
    () async {
      final page = (await ocr.read(blockId))!;
      await db.hardDeleteFolderCascade(folderId);
      expect(
        await ocr.save(blockId, page.revision, [segment('Fantasma')]),
        isFalse,
      );
      expect(await db.select(db.canvasOcrPages).get(), isEmpty);
    },
  );

  test('segments group handwriting lines and skip shapes/highlighter', () {
    final raw = [
      pen(0, 0),
      pen(15, 0),
      pen(0, 60),
      DrawingStroke(
        colorValue: 0,
        strokeWidth: 2,
        isShape: true,
        points: StrokePoints.fromNested([
          [0, 0],
          [100, 0],
        ]),
      ),
    ];
    final records = [
      for (var i = 0; i < raw.length; i++)
        DrawingStrokeRecord(id: i + 1, position: i, data: raw[i].toBytes()),
    ];
    final groups = segmentCanvasInk(records);
    expect(groups.length, 2);
    expect(groups.first.strokes.length, 2);
    expect(groups.first.strokes.first.first, Offset.zero);
    expect(segmentCanvasInk(records).first.hash, groups.first.hash);
  });

  test('a long handwritten line is not split at an arbitrary stroke count', () {
    final records = [
      for (var i = 0; i < 80; i++)
        DrawingStrokeRecord(
          id: i + 1,
          position: i,
          data: pen(i * 5, 0).toBytes(),
        ),
    ];
    expect(segmentCanvasInk(records), hasLength(1));
  });

  test('automatic recognition passes preceding text as context', () async {
    await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
    await strokes.insert(blockId, strokeWrite(1, pen(0, 60)));
    final engine = _Ink();
    final completed = Completer<void>();
    final service = CanvasOcrCoordinator(
      repository: ocr,
      strokes: strokes,
      recognizer: engine,
      spellCheck: _Spelling(),
      idleDelay: const Duration(milliseconds: 10),
      onChanged: completed.complete,
    );
    addTearDown(service.dispose);
    service.schedule(blockId);
    await completed.future.timeout(const Duration(seconds: 10));
    expect(engine.contexts, hasLength(2));
    expect(engine.contexts.first, isEmpty);
    expect(engine.contexts.last, isNotEmpty);
    expect(engine.contexts.last.length, lessThanOrEqualTo(20));
  });

  test(
    'automatic indexing pauses for pen and reuses unchanged recognition',
    () async {
      await strokes.insert(blockId, strokeWrite(0, pen(0, 0)));
      final engine = _Ink();
      var completed = Completer<void>();
      final service = CanvasOcrCoordinator(
        repository: ocr,
        strokes: strokes,
        recognizer: engine,
        spellCheck: _Spelling(),
        onChanged: () => completed.complete(),
      );
      addTearDown(service.dispose);
      service.pointerDown(1);
      service.schedule(blockId);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.calls, 0);
      service.pointerUp(1);
      await completed.future.timeout(const Duration(seconds: 15));
      expect(engine.calls, 1);
      expect(await ocr.search('cancion'), isNotEmpty);
      completed = Completer<void>();
      await LocalCanvasOcrRepository.invalidate(db, [blockId]);
      service.schedule(blockId);
      await completed.future.timeout(const Duration(seconds: 15));
      expect(engine.calls, 1);
    },
  );
}
