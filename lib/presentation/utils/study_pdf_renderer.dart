import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';

import '../../domain/models/drawing_stroke_record.dart';
import '../../domain/models/folder.dart';
import '../../domain/models/note.dart';
import '../../domain/models/note_block.dart';
import '../../domain/models/task.dart';
import '../../domain/repositories/drawing_stroke_repository.dart';
import '../../domain/repositories/folder_repository.dart';
import '../../domain/repositories/note_block_repository.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/repositories/task_repository.dart';
import '../screens/flight/background_paint.dart';
import '../screens/flight/canvas_text_block.dart';
import '../screens/flight/drawing_stroke_persistence.dart';
import '../screens/flight/note_cell_model.dart';
import '../screens/flight/note_export_view.dart';
import '../screens/flight/notebook_constants.dart';
import '../widgets/yuli_design.dart';
import 'canvas_block_raster.dart';
import 'canvas_export.dart';
import 'pdf_export.dart';

Future<Map<int, List<DrawingStroke>>> _decodeStudyInk(
  Map<int, List<DrawingStrokeRecord>> records,
) => Isolate.run(
  () => {
    for (final entry in records.entries)
      entry.key: entry.value.map(strokeFromRecord).toList(),
  },
);

Future<DrawingData> _decodeStudyDrawing(
  Map<String, dynamic> payload,
  List<DrawingStroke>? ink,
) => Isolate.run(() {
  final data = DrawingData.fromJson(payload);
  if (ink?.isNotEmpty == true) data.strokes = ink!;
  return data;
});

class _StudyCachedPage {
  final int blockId;
  final String hash;
  final double width;
  final double height;
  final File file;

  const _StudyCachedPage({
    required this.blockId,
    required this.hash,
    required this.width,
    required this.height,
    required this.file,
  });
}

class _StudyRenderedPage {
  final List<int> bytes;
  final double width;
  final double height;

  const _StudyRenderedPage(this.bytes, this.width, this.height);
}

Future<void> _assembleStudyPdf(
  List<({String path, double width, double height})> pages,
  String target,
) => Isolate.run(() async {
  final document = pw.Document();
  for (final page in pages) {
    final bytes = await File(page.path).readAsBytes();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          page.width.clamp(1, 14400),
          page.height.clamp(1, 14400),
        ),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
      ),
    );
  }
  if (pages.isEmpty) document.addPage(pw.Page(build: (_) => pw.SizedBox()));
  await File(target).writeAsBytes(await document.save(), flush: true);
});

Future<String> _studyImageFingerprint(String path) async {
  try {
    return (await sha256.bind(File(path).openRead()).first).toString();
  } on FileSystemException {
    return 'missing';
  }
}

Future<void> cleanupStudyPdfCache(
  Directory documents,
  Set<int> activeNoteIds,
) async {
  final root = Directory(p.join(documents.path, 'study_exports', 'cache'));
  if (!await root.exists()) return;
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final match = RegExp(r'^note_(\d+)$').firstMatch(p.basename(entity.path));
    if (match == null) continue;
    final noteId = int.tryParse(match.group(1)!);
    if (noteId == null || activeNoteIds.contains(noteId)) continue;
    try {
      await entity.delete(recursive: true);
    } on FileSystemException {
      continue;
    }
  }
}

class StudySnapshot {
  final Note note;
  final Folder folder;
  final List<NoteBlock> blocks;
  final Map<int, List<DrawingStrokeRecord>> strokes;
  final Map<int, Task> tasks;
  final List<String> images;
  final String documentsPath;
  Future<Map<int, String>>? _drawingHashes;
  StudySnapshot(
    this.note,
    this.folder,
    this.blocks,
    this.strokes,
    this.tasks,
    this.images, {
    this.documentsPath = '',
  });

  static Future<StudySnapshot?> read(
    int id,
    NoteRepository notes,
    FolderRepository folders,
    NoteBlockRepository blocks,
    DrawingStrokeRepository strokes,
    TaskRepository tasks,
    String documents,
  ) async {
    final note = await notes.getById(id);
    if (note == null || !note.isActive) return null;
    final folder = await folders.getById(note.folderId);
    if (folder == null || !folder.isActive) return null;
    final content = await blocks.getByNote(id);
    final ink = <int, List<DrawingStrokeRecord>>{};
    final taskIds = <int>{};
    final images = <String>{};
    for (final block in content) {
      if (block is TareasBlock) taskIds.addAll(block.taskIds);
      if (block is DrawingBlock) {
        ink[block.id] = await strokes.getByBlock(block.id);
        for (final taskBlock in jsonDecode(block.taskBlocksJson) as List) {
          taskIds.addAll(
            ((taskBlock as Map)['ids'] as List? ?? []).cast<int>(),
          );
        }
        for (final image in jsonDecode(block.imagesJson) as List) {
          final parsed = CanvasImage.fromJson(
            Map<String, dynamic>.from(image as Map),
          );
          if (p.basename(parsed.filename) != parsed.filename) {
            throw StateError('Imagen inválida.');
          }
          images.add(p.join(documents, 'note_images', '$id', parsed.filename));
        }
      }
    }
    for (final image in await notes.getImages(id)) {
      images.add(image.filePath);
    }
    final linkedTasks = <int, Task>{};
    for (final id in taskIds.toList()..sort()) {
      final task = await tasks.getById(id);
      if (task != null) linkedTasks[id] = task;
    }
    return StudySnapshot(
      note,
      folder,
      content,
      ink,
      linkedTasks,
      images.toList()..sort(),
      documentsPath: documents,
    );
  }

  Future<Map<int, String>> _drawingFingerprints() {
    final existing = _drawingHashes;
    if (existing != null) return existing;
    return _drawingHashes = _computeDrawingFingerprints();
  }

  Future<Map<int, String>> _computeDrawingFingerprints() async {
    final specs = <Map<String, Object>>[];
    for (final block in blocks.whereType<DrawingBlock>()) {
      final taskIds = <int>{};
      for (final taskBlock in jsonDecode(block.taskBlocksJson) as List) {
        taskIds.addAll(((taskBlock as Map)['ids'] as List? ?? []).cast<int>());
      }
      final paths = <String>[];
      for (final image in jsonDecode(block.imagesJson) as List) {
        final parsed = CanvasImage.fromJson(
          Map<String, dynamic>.from(image as Map),
        );
        if (p.basename(parsed.filename) != parsed.filename) {
          throw StateError('Imagen inválida.');
        }
        paths.add(
          p.join(documentsPath, 'note_images', '${note.id}', parsed.filename),
        );
      }
      specs.add({
        'id': block.id,
        'metadata': jsonEncode([
          'study-drawing-page-v2',
          note.kind.name,
          note.color?.toARGB32(),
          folder.color.toARGB32(),
          block.position,
          block.payloadJson(),
          for (final id in taskIds.toList()..sort())
            if (tasks[id] case final task?)
              [
                task.id,
                task.content,
                task.status.name,
                task.dueDate?.toIso8601String(),
              ],
        ]),
        'strokes': [
          for (final stroke in strokes[block.id] ?? const [])
            [stroke.id, stroke.position, stroke.data],
        ],
        'images': paths,
      });
    }
    return Isolate.run(() async {
      final result = <int, String>{};
      for (final spec in specs) {
        final parts = <List<int>>[utf8.encode(spec['metadata']! as String)];
        for (final stroke in spec['strokes']! as List) {
          final values = stroke as List;
          parts.add(utf8.encode('${values[0]}:${values[1]}:'));
          parts.add(values[2] as List<int>);
        }
        for (final path in spec['images']! as List) {
          parts.add(utf8.encode(await _studyImageFingerprint(path as String)));
        }
        result[spec['id']! as int] =
            (await sha256.bind(Stream.fromIterable(parts)).first).toString();
      }
      return result;
    });
  }

  Future<String> fingerprint() async {
    if (note.kind != NoteKind.block) {
      final pageHashes = await _drawingFingerprints();
      final payload = jsonEncode([
        'study-pdf-v2',
        note.title,
        folder.id,
        folder.name,
        for (final block in blocks.whereType<DrawingBlock>())
          [block.id, block.position, pageHashes[block.id]],
      ]);
      return sha256.convert(utf8.encode(payload)).toString();
    }
    return Isolate.run(() async {
      final parts = <List<int>>[
        utf8.encode(
          jsonEncode([
            'study-pdf-v1',
            note.title,
            note.rawMarkdown,
            note.kind.name,
            note.color?.toARGB32(),
            folder.id,
            folder.name,
            folder.color.toARGB32(),
            for (final b in blocks) [b.id, b.position, b.payloadJson()],
            for (final t in tasks.values)
              [t.id, t.content, t.status.name, t.dueDate?.toIso8601String()],
          ]),
        ),
      ];
      for (final entry in strokes.entries) {
        parts.add(utf8.encode('${entry.key}:'));
        for (final stroke in entry.value) {
          parts.add(utf8.encode('${stroke.id}:${stroke.position}:'));
          parts.add(stroke.data);
        }
      }
      final hashes = <String>[];
      for (final image in images) {
        hashes.add(await _studyImageFingerprint(image));
      }
      parts.add(utf8.encode(jsonEncode(hashes)));
      return (await sha256.bind(Stream.fromIterable(parts)).first).toString();
    });
  }

  Directory _cacheRoot(Directory documents) => Directory(
    p.join(documents.path, 'study_exports', 'cache', 'note_${note.id}'),
  );

  Future<Map<int, _StudyCachedPage>> _readCache(Directory root) async {
    final result = <int, _StudyCachedPage>{};
    final manifest = File(p.join(root.path, 'manifest.json'));
    if (!await manifest.exists()) return result;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return result;
      }
      final pages = decoded['pages'];
      if (pages is! Map) return result;
      for (final raw in pages.values) {
        if (raw is! Map) continue;
        final blockId = raw['blockId'];
        final hash = raw['hash'];
        final width = raw['width'];
        final height = raw['height'];
        if (blockId is! int ||
            hash is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
            width is! num ||
            height is! num ||
            !width.isFinite ||
            !height.isFinite ||
            width <= 0 ||
            height <= 0 ||
            width > 14400 ||
            height > 14400) {
          continue;
        }
        final file = File(p.join(root.path, '${blockId}_$hash.png'));
        if (!await file.exists() || await file.length() == 0) continue;
        result[blockId] = _StudyCachedPage(
          blockId: blockId,
          hash: hash,
          width: width.toDouble(),
          height: height.toDouble(),
          file: file,
        );
      }
    } catch (_) {
      return {};
    }
    return result;
  }

  Future<void> _writeCache(
    Directory root,
    Map<int, _StudyCachedPage> pages,
  ) async {
    final manifest = File(p.join(root.path, 'manifest.json'));
    final temporary = File(p.join(root.path, 'manifest.json.partial'));
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'pages': {
          for (final page in pages.values)
            '${page.blockId}': {
              'blockId': page.blockId,
              'hash': page.hash,
              'width': page.width,
              'height': page.height,
            },
        },
      }),
      flush: true,
    );
    if (await manifest.exists()) await manifest.delete();
    await temporary.rename(manifest.path);
  }

  Future<_StudyRenderedPage> _renderDrawingPage(
    BuildContext context,
    Directory documents,
    DrawingBlock block,
    List<DrawingStroke>? ink,
    Future<void> Function() checkpoint,
  ) async {
    final data = await _decodeStudyDrawing(block.payloadJson(), ink);
    final rects = [
      for (final b in data.textBlocks) Rect.fromLTWH(b.x, b.y, b.w, b.h),
      for (final b in data.taskBlocks) Rect.fromLTWH(b.x, b.y, b.w, b.h),
    ];
    final region =
        note.kind == NoteKind.notebook
            ? const Rect.fromLTWH(0, 0, kNotebookPageWidth, kNotebookPageHeight)
            : (contentBounds(data, blockRects: rects) ??
                    const Rect.fromLTWH(0, 0, 595, 842))
                .inflate(24);
    final ratio = exportPixelRatio(region, desired: 2);
    final rasterBlocks = <ExportBlockImage>[];
    final imageMap = <String, ui.Image>{};
    ui.Image? rendered;
    try {
      final specs = <BlockRasterSpec>[
        for (final b in data.textBlocks)
          BlockRasterSpec(
            worldPos: Offset(b.x, b.y),
            rotation: b.rotation,
            child: CanvasTextBlockOverlay(
              block: b.clone()..rotation = 0,
              accent: note.color ?? folder.color,
              interactive: false,
              onPersist: () async {},
              onChanged: () {},
              onHeightMeasured: (_) {},
            ),
          ),
        for (final b in data.taskBlocks)
          BlockRasterSpec(
            worldPos: Offset(b.x, b.y),
            rotation: b.rotation,
            child: SizedBox(
              width: b.w,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: buildNoteExportItems(
                  blocks: [
                    TareasBlock(
                      id: 0,
                      noteId: note.id,
                      position: 0,
                      taskIds: b.taskIds,
                    ),
                  ],
                  accent: note.color ?? folder.color,
                  tasksById: tasks,
                ),
              ),
            ),
          ),
      ];
      for (final spec in specs) {
        await checkpoint();
        if (!context.mounted) throw StateError('Exportación interrumpida.');
        final images = await rasterizeCanvasBlocks(
          context: context,
          specs: [spec],
          pixelRatio: ratio,
        );
        if (images.length != 1) {
          throw StateError('No se pudo renderizar un bloque.');
        }
        rasterBlocks.addAll(images);
      }
      await checkpoint();
      imageMap.addAll(
        await loadExportImages(
          p.join(documents.path, 'note_images', '${note.id}'),
          data.images,
        ),
      );
      rendered = await renderCanvasRegion(
        data: data,
        region: region,
        pixelRatio: ratio,
        checkpoint: checkpoint,
        paper: bgPaper(data.bgColorValue, yCream),
        images: imageMap,
        blocks: rasterBlocks,
      );
      await checkpoint();
      return _StudyRenderedPage(
        await imageToPngBytes(rendered),
        region.width,
        region.height,
      );
    } finally {
      rendered?.dispose();
      for (final block in rasterBlocks) {
        block.image.dispose();
      }
      disposeExportImages(imageMap);
    }
  }

  Future<void> prepareDrawingCache(
    BuildContext context,
    Directory documents,
    Future<void> Function() checkpoint,
  ) async {
    await _prepareDrawingCache(context, documents, checkpoint);
  }

  Future<void> clearDrawingCache(Directory documents) async {
    final root = _cacheRoot(documents);
    if (await root.exists()) await root.delete(recursive: true);
    _drawingHashes = null;
  }

  Future<List<_StudyCachedPage>> _prepareDrawingCache(
    BuildContext context,
    Directory documents,
    Future<void> Function() checkpoint,
  ) async {
    if (note.kind == NoteKind.block) return const [];
    final root = _cacheRoot(documents);
    await root.create(recursive: true);
    final cached = await _readCache(root);
    final hashes = await _drawingFingerprints();
    final ordered = <_StudyCachedPage>[];
    for (final block in blocks.whereType<DrawingBlock>()) {
      await checkpoint();
      final hash = hashes[block.id]!;
      var page = cached[block.id];
      if (page == null || page.hash != hash) {
        if (!context.mounted) throw StateError('Exportación interrumpida.');
        final ink = await _decodeStudyInk({
          block.id: strokes[block.id] ?? const [],
        });
        if (!context.mounted) throw StateError('Exportación interrumpida.');
        final rendered = await _renderDrawingPage(
          context,
          documents,
          block,
          ink[block.id],
          checkpoint,
        );
        final file = File(p.join(root.path, '${block.id}_$hash.png'));
        final temporary = File('${file.path}.partial');
        await temporary.writeAsBytes(rendered.bytes, flush: true);
        if (await file.exists()) await file.delete();
        await temporary.rename(file.path);
        page = _StudyCachedPage(
          blockId: block.id,
          hash: hash,
          width: rendered.width,
          height: rendered.height,
          file: file,
        );
        cached[block.id] = page;
        await _writeCache(root, cached);
      }
      ordered.add(page);
    }
    final current = {for (final page in ordered) page.blockId: page};
    await _writeCache(root, current);
    final keep =
        ordered.map((page) => p.basename(page.file.path)).toSet()
          ..add('manifest.json');
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && !keep.contains(p.basename(entity.path))) {
        try {
          await entity.delete();
        } on FileSystemException {
          continue;
        }
      }
    }
    return ordered;
  }

  Future<File> render(
    BuildContext context,
    Directory documents,
    Future<void> Function() checkpoint,
  ) async {
    final root = Directory(p.join(documents.path, 'study_exports'));
    await root.create(recursive: true);
    final target = File(p.join(root.path, '${const Uuid().v4()}.pdf'));
    await checkpoint();
    if (!context.mounted) throw StateError('Exportación interrumpida.');
    try {
      if (note.kind == NoteKind.block) {
        final ink = await _decodeStudyInk(strokes);
        if (!context.mounted) throw StateError('Exportación interrumpida.');
        await exportNoteToPdf(
          context: context,
          title: note.displayTitle,
          blocks: blocks,
          accent: note.color ?? folder.color,
          tasksById: tasks,
          drawingStrokesByBlock: ink,
          checkpoint: checkpoint,
          onBytes: (bytes) async {
            await target.writeAsBytes(bytes, flush: true);
          },
        );
      } else {
        Future<void> assemble(List<_StudyCachedPage> pages) =>
            _assembleStudyPdf([
              for (final page in pages)
                (path: page.file.path, width: page.width, height: page.height),
            ], target.path);

        var pages = await _prepareDrawingCache(context, documents, checkpoint);
        await checkpoint();
        try {
          await _assembleStudyPdf([
            for (final page in pages)
              (path: page.file.path, width: page.width, height: page.height),
          ], target.path);
        } catch (_) {
          if (await target.exists()) await target.delete();
          await clearDrawingCache(documents);
          await checkpoint();
          if (!context.mounted) throw StateError('Exportación interrumpida.');
          pages = await _prepareDrawingCache(context, documents, checkpoint);
          await checkpoint();
          await assemble(pages);
        }
      }
      return target;
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }
}
