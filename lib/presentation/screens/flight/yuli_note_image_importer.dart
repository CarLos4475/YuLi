import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/repositories/note_repository.dart';

class YuliImportedNoteImage {
  final String filename;
  final String path;
  final int sizeBytes;

  const YuliImportedNoteImage({
    required this.filename,
    required this.path,
    required this.sizeBytes,
  });
}

Future<YuliImportedNoteImage> importYuliNoteImage({
  required int noteId,
  required String sourcePath,
  required NoteRepository noteRepository,
}) async {
  final appDir = await getApplicationDocumentsDirectory();
  final imagesDir = Directory(p.join(appDir.path, 'note_images', '$noteId'));
  await imagesDir.create(recursive: true);

  final compressedFilename = '${const Uuid().v4()}.jpg';
  final compressedPath = p.join(imagesDir.path, compressedFilename);
  final compressed = await FlutterImageCompress.compressAndGetFile(
    sourcePath,
    compressedPath,
    quality: 80,
    minWidth: 1920,
    minHeight: 1920,
  );

  final String filename;
  final String filePath;
  if (compressed != null) {
    filename = compressedFilename;
    filePath = compressed.path;
  } else {
    final ext =
        p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    filename = '${const Uuid().v4()}$ext';
    filePath = p.join(imagesDir.path, filename);
    await File(sourcePath).copy(filePath);
  }

  final sizeBytes = await File(filePath).length();
  await noteRepository.addImage(noteId, filename, filePath, sizeBytes);

  return YuliImportedNoteImage(
    filename: filename,
    path: filePath,
    sizeBytes: sizeBytes,
  );
}
