import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/services/ai_assistant.dart';

Future<Directory> _chatImageDirectory() async {
  final cache = await getTemporaryDirectory();
  return Directory(p.join(cache.path, 'yuli_ai_chat_images'));
}

Future<AiImageInput> prepareAiChatImage(String sourcePath) async {
  final directory = await _chatImageDirectory();
  await directory.create(recursive: true);
  await _cleanupOldChatImages(directory);

  return _compressAiChatImage(directory, sourcePath);
}

Future<AiImageInput> prepareAiChatImageBytes(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const FileSystemException('La imagen es demasiado grande.');
  }
  final directory = await _chatImageDirectory();
  await directory.create(recursive: true);
  await _cleanupOldChatImages(directory);

  final source = File(p.join(directory.path, '${const Uuid().v4()}.png'));
  await source.writeAsBytes(bytes, flush: true);
  try {
    return await _compressAiChatImage(directory, source.path);
  } finally {
    try {
      if (await source.exists()) await source.delete();
    } catch (_) {}
  }
}

Future<AiImageInput> _compressAiChatImage(
  Directory directory,
  String sourcePath,
) async {
  final destination = p.join(directory.path, '${const Uuid().v4()}.jpg');
  final compressed = await FlutterImageCompress.compressAndGetFile(
    sourcePath,
    destination,
    quality: 80,
    minWidth: 1920,
    minHeight: 1920,
  );
  if (compressed == null) {
    throw const FileSystemException('No se pudo preparar la imagen.');
  }
  final file = File(compressed.path);
  if (await file.length() > 20 * 1024 * 1024) {
    await file.delete();
    throw const FileSystemException('La imagen es demasiado grande.');
  }
  return AiImageInput(path: file.path, mediaType: 'image/jpeg');
}

Future<void> deleteAiChatImage(AiImageInput image) async {
  final directory = await _chatImageDirectory();
  final root = p.normalize(p.absolute(directory.path));
  final target = p.normalize(p.absolute(image.path));
  if (!p.isWithin(root, target)) return;
  try {
    final file = File(target);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

Future<void> _cleanupOldChatImages(Directory directory) async {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  await for (final entity in directory.list()) {
    if (entity is! File) continue;
    try {
      if ((await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
      }
    } catch (_) {}
  }
}
