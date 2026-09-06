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

class StudySnapshot {
  final Note note;
  final Folder folder;
  final List<NoteBlock> blocks;
  final Map<int, List<DrawingStrokeRecord>> strokes;
  final Map<int, Task> tasks;
  final List<String> images;
  StudySnapshot(
    this.note,
    this.folder,
    this.blocks,
    this.strokes,
    this.tasks,
    this.images,
  );

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
    );
  }

  Future<String> fingerprint() => Isolate.run(() async {
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
      hashes.add((await sha256.bind(File(image).openRead()).first).toString());
    }
    parts.add(utf8.encode(jsonEncode(hashes)));
    return (await sha256.bind(Stream.fromIterable(parts)).first).toString();
  });

  Future<File> render(
    BuildContext context,
    Directory documents,
    Future<void> Function() checkpoint,
  ) async {
    final root = Directory(p.join(documents.path, 'study_exports'));
    await root.create(recursive: true);
    final target = File(p.join(root.path, '${const Uuid().v4()}.pdf'));
    final ink = await _decodeStudyInk(strokes);
    await checkpoint();
    if (!context.mounted) throw StateError('Exportación interrumpida.');
    try {
      if (note.kind == NoteKind.block) {
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
        final doc = pw.Document();
        for (final block in blocks.whereType<DrawingBlock>()) {
          await checkpoint();
          final data = await _decodeStudyDrawing(
            block.payloadJson(),
            ink[block.id],
          );
          final rects = [
            for (final b in data.textBlocks) Rect.fromLTWH(b.x, b.y, b.w, b.h),
            for (final b in data.taskBlocks) Rect.fromLTWH(b.x, b.y, b.w, b.h),
          ];
          final region =
              note.kind == NoteKind.notebook
                  ? const Rect.fromLTWH(
                    0,
                    0,
                    kNotebookPageWidth,
                    kNotebookPageHeight,
                  )
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
              if (!context.mounted) {
                throw StateError('Exportación interrumpida.');
              }
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
            if (imageMap.length !=
                data.images.map((i) => i.filename).toSet().length) {
              throw StateError('Falta una imagen.');
            }
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
            final png = await imageToPngBytes(rendered);
            final memory = pw.MemoryImage(png);
            doc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat(
                  region.width.clamp(1, 14400),
                  region.height.clamp(1, 14400),
                ),
                margin: pw.EdgeInsets.zero,
                build: (_) => pw.Image(memory, fit: pw.BoxFit.contain),
              ),
            );
          } finally {
            rendered?.dispose();
            for (final block in rasterBlocks) {
              block.image.dispose();
            }
            disposeExportImages(imageMap);
          }
        }
        if (blocks.whereType<DrawingBlock>().isEmpty) {
          doc.addPage(pw.Page(build: (_) => pw.SizedBox()));
        }
        await checkpoint();
        await target.writeAsBytes(await doc.save(), flush: true);
      }
      return target;
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }
}
