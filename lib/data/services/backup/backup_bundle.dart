import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class BackupFailure implements Exception {
  final String message;
  const BackupFailure(this.message);
  @override
  String toString() => message;
}

class BackupBundle {
  static const version = 1;
  static const maxBytes = 16 * 1024 * 1024 * 1024;
  static const maxManifestBytes = 8 * 1024 * 1024;
  static const roots = ['note_images', 'floating_pins', 'notebook_cameras'];
  static const magic = [89, 85, 76, 73, 66, 65, 75, 49];

  static bool validPath(String name) {
    if (name == 'yuli_db.sqlite' || name == 'preferences.json') return true;
    final parts = name.split('/');
    if (parts.length < 2 || !roots.contains(parts.first)) return false;
    if (parts.first == 'notebook_cameras') {
      if (parts.length != 2 || !RegExp(r'^\d+\.json$').hasMatch(parts.last)) {
        return false;
      }
    } else if (parts.length != 3 || !RegExp(r'^\d+$').hasMatch(parts[1])) {
      return false;
    }
    if (parts.last.endsWith('.') ||
        parts.last.endsWith(' ') ||
        RegExp(r'[<>"|?*\x00-\x1f]').hasMatch(name)) {
      return false;
    }
    if (name.contains('\\') || name.contains(':') || name.contains('\u0000')) {
      return false;
    }
    return parts.every(
      (part) => part.isNotEmpty && part != '.' && part != '..',
    );
  }

  static Future<String> digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<Map<String, dynamic>> create({
    required Directory source,
    required File destination,
    required int schema,
    required String deviceId,
    required String documentsPath,
    required Map<String, int> counts,
  }) async {
    final entries = <Map<String, dynamic>>[];
    var total = 0;
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) {
        throw const BackupFailure('No se permiten enlaces de archivos.');
      }
      if (entity is! File) continue;
      final name = p
          .relative(entity.path, from: source.path)
          .replaceAll('\\', '/');
      if (!validPath(name)) {
        throw const BackupFailure('Archivo fuera del respaldo.');
      }
      final size = await entity.length();
      total += size;
      if (total > maxBytes) {
        throw const BackupFailure('El respaldo supera 16 GB.');
      }
      entries.add({'path': name, 'size': size, 'sha256': await digest(entity)});
    }
    entries.sort(
      (a, b) => (a['path'] as String).compareTo(b['path'] as String),
    );
    final manifest = <String, dynamic>{
      'format': version,
      'schema': schema,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'deviceId': deviceId,
      'documentsPath': documentsPath,
      'counts': counts,
      'files': entries,
    };
    final header = utf8.encode(jsonEncode(manifest));
    if (header.length > maxManifestBytes) {
      throw const BackupFailure('Demasiados archivos.');
    }
    final partial = File('${destination.path}.partial');
    final sink = partial.openWrite();
    try {
      sink.add(magic);
      sink.add((ByteData(4)..setUint32(0, header.length)).buffer.asUint8List());
      sink.add(header);
      for (final entry in entries) {
        await sink.addStream(
          File(p.join(source.path, entry['path'] as String)).openRead(),
        );
      }
      await sink.flush();
      await sink.close();
      if (await destination.exists()) {
        throw const BackupFailure('El respaldo ya existe.');
      }
      await partial.rename(destination.path);
      return manifest;
    } catch (_) {
      await sink.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  static Future<Uint8List> _read(RandomAccessFile input, int length) async {
    final bytes = await input.read(length);
    if (bytes.length != length) {
      throw const BackupFailure('El respaldo está incompleto.');
    }
    return bytes;
  }

  static Future<Map<String, dynamic>> _header(RandomAccessFile input) async {
    if (base64Encode(await _read(input, 8)) != base64Encode(magic)) {
      throw const BackupFailure('No es un respaldo de YuLi.');
    }
    final length = ByteData.sublistView(await _read(input, 4)).getUint32(0);
    if (length == 0 || length > maxManifestBytes) {
      throw const BackupFailure('Cabecera de respaldo inválida.');
    }
    final value = jsonDecode(utf8.decode(await _read(input, length)));
    if (value is! Map<String, dynamic> ||
        value['format'] != version ||
        value['schema'] is! int ||
        value['files'] is! List ||
        value['documentsPath'] is! String ||
        (value['documentsPath'] as String).length > 4096 ||
        value['deviceId'] is! String ||
        (value['deviceId'] as String).length > 128 ||
        value['counts'] is! Map ||
        value['createdAt'] is! String ||
        DateTime.tryParse(value['createdAt'] as String) == null) {
      throw const BackupFailure('Formato de respaldo incompatible.');
    }
    final seen = <String>{};
    var total = 0;
    for (final entry in value['files'] as List) {
      if (entry is! Map ||
          entry['path'] is! String ||
          entry['size'] is! int ||
          entry['sha256'] is! String) {
        throw const BackupFailure('Inventario de respaldo inválido.');
      }
      final name = entry['path'] as String;
      final size = entry['size'] as int;
      if (name == 'preferences.json' && size > 32 * 1024 * 1024) {
        throw const BackupFailure(
          'Las preferencias del respaldo superan el límite de 32 MB.',
        );
      }
      if (!validPath(name) ||
          !seen.add(name.toLowerCase()) ||
          size < 0 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry['sha256'] as String)) {
        throw const BackupFailure('Inventario de respaldo inválido.');
      }
      total += size;
      if (total > maxBytes) {
        throw const BackupFailure('El respaldo supera 16 GB.');
      }
    }
    if (!seen.contains('yuli_db.sqlite') ||
        !seen.contains('preferences.json') ||
        await input.length() != await input.position() + total) {
      throw const BackupFailure(
        'El respaldo está incompleto o contiene datos extra.',
      );
    }
    return value;
  }

  static Future<Map<String, dynamic>> inspect(File file) async {
    final input = await file.open();
    try {
      return await _header(input);
    } finally {
      await input.close();
    }
  }

  static Future<Map<String, dynamic>> extract(
    File file,
    Directory target,
  ) async {
    if (await target.exists()) {
      throw const BackupFailure('El destino ya existe.');
    }
    final input = await file.open();
    var created = false;
    try {
      final manifest = await _header(input);
      await target.create(recursive: true);
      created = true;
      for (final entry in manifest['files'] as List) {
        final output = File(p.join(target.path, entry['path'] as String));
        if (!p.isWithin(target.absolute.path, output.absolute.path)) {
          throw const BackupFailure('Ruta de archivo inválida.');
        }
        await output.parent.create(recursive: true);
        final handle = await output.open(mode: FileMode.write);
        try {
          var remaining = entry['size'] as int;
          while (remaining > 0) {
            final length = remaining > 1024 * 1024 ? 1024 * 1024 : remaining;
            await handle.writeFrom(await _read(input, length));
            remaining -= length;
          }
          await handle.flush();
        } finally {
          await handle.close();
        }
        if (await digest(output) != entry['sha256']) {
          throw const BackupFailure(
            'El respaldo está dañado: falló la verificación.',
          );
        }
      }
      return manifest;
    } catch (_) {
      if (created) await target.delete(recursive: true);
      rethrow;
    } finally {
      await input.close();
    }
  }
}
