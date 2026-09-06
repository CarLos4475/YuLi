import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'backup_bundle.dart';

class DriveBackup {
  final String id;
  final String name;
  final DateTime createdAt;
  final int size;
  final String deviceId;
  const DriveBackup(
    this.id,
    this.name,
    this.createdAt,
    this.size,
    this.deviceId,
  );

  factory DriveBackup.fromJson(Map<String, dynamic> json) => DriveBackup(
    json['id'] as String,
    json['name'] as String,
    DateTime.parse(json['createdTime'] as String),
    int.parse(json['size'] as String? ?? '0'),
    (json['appProperties'] as Map?)?['device'] as String? ?? '',
  );
}

class DriveBackupClient {
  final http.Client client;
  final Future<Map<String, String>> Function() authorization;
  DriveBackupClient(this.client, this.authorization);
  static const _kind = 'yuli-backup-v1';
  static const _fields = 'id,name,createdTime,size,md5Checksum,appProperties';

  Future<http.Response> _json(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, uri);
    request.followRedirects = false;
    request.headers.addAll(await authorization());
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 60)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _fail(response.statusCode);
    }
    return response;
  }

  static Never _fail(int status) {
    if (status == 401) {
      throw const BackupFailure('Vuelve a conectar tu cuenta de Google.');
    }
    if (status == 403) {
      throw const BackupFailure(
        'Drive rechazó la operación. Revisa permisos y espacio disponible.',
      );
    }
    if (status == 429) {
      throw const BackupFailure(
        'Drive está ocupado. Intenta de nuevo más tarde.',
      );
    }
    throw const BackupFailure('No se pudo completar la operación en Drive.');
  }

  Future<List<DriveBackup>> list() async {
    final result = <DriveBackup>[];
    String? token;
    do {
      final response = await _json(
        'GET',
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q':
              "trashed = false and appProperties has { key='kind' and value='$_kind' } and appProperties has { key='state' and value='complete' }",
          'fields': 'nextPageToken,files($_fields)',
          'pageSize': '100',
          'orderBy': 'createdTime desc',
          if (token != null) 'pageToken': token,
        }),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      result.addAll(
        (data['files'] as List).map(
          (v) => DriveBackup.fromJson(v as Map<String, dynamic>),
        ),
      );
      token = data['nextPageToken'] as String?;
    } while (token != null);
    return result;
  }

  Future<String> _folder({bool study = false}) async {
    final kind = study ? 'yuli-study-folder-v1' : 'yuli-backup-folder-v1';
    final response = await _json(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "trashed = false and mimeType = 'application/vnd.google-apps.folder' and appProperties has { key='kind' and value='$kind' }",
        'fields': 'files(id)',
        'pageSize': '100',
      }),
    );
    final files = (jsonDecode(response.body) as Map)['files'] as List;
    if (files.isNotEmpty) return files.first['id'] as String;
    final created = await _json(
      'POST',
      Uri.https('www.googleapis.com', '/drive/v3/files'),
      body: {
        'name': study ? 'YuLi — Apuntes' : 'YuLi — Respaldos',
        'mimeType': 'application/vnd.google-apps.folder',
        'appProperties': {'kind': kind},
      },
    );
    return (jsonDecode(created.body) as Map)['id'] as String;
  }

  Future<DriveBackup> upload(
    File file,
    String deviceId, {
    void Function(double)? progress,
    bool study = false,
  }) async {
    final kind = study ? 'yuli-study-v1' : _kind;
    final extension = file.path.toLowerCase();
    if (study && !extension.endsWith('.pdf') && !extension.endsWith('.png')) {
      throw const BackupFailure('Solo se pueden publicar apuntes PDF o PNG.');
    }
    final mime =
        study
            ? (extension.endsWith('.pdf') ? 'application/pdf' : 'image/png')
            : 'application/octet-stream';
    final size = await file.length();
    if (size > BackupBundle.maxBytes + BackupBundle.maxManifestBytes + 12) {
      throw const BackupFailure('El respaldo es demasiado grande.');
    }
    final checksum = (await md5.bind(file.openRead()).first).toString();
    final folder = await _folder(study: study);
    final init = http.Request(
      'POST',
      Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
        'uploadType': 'resumable',
        'fields': _fields,
      }),
    );
    init.followRedirects = false;
    init.headers.addAll(await authorization());
    init.headers.addAll({
      'Content-Type': 'application/json',
      'X-Upload-Content-Type': mime,
      'X-Upload-Content-Length': '$size',
    });
    init.body = jsonEncode({
      'name': file.uri.pathSegments.last,
      'parents': [folder],
      'mimeType': mime,
      'appProperties': {'kind': kind, 'device': deviceId, 'state': 'pending'},
    });
    final start = await http.Response.fromStream(
      await client.send(init).timeout(const Duration(seconds: 60)),
    );
    if (start.statusCode != 200) _fail(start.statusCode);
    final location = Uri.tryParse(start.headers['location'] ?? '');
    if (location == null ||
        location.scheme != 'https' ||
        location.host != 'www.googleapis.com' ||
        location.userInfo.isNotEmpty ||
        location.port != 443 ||
        !location.path.startsWith('/upload/drive/')) {
      throw const BackupFailure(
        'Drive devolvió una dirección de subida inválida.',
      );
    }
    var offset = 0;
    var failures = 0;
    Map<String, dynamic>? completed;
    while (completed == null) {
      final end = (offset + 8 * 1024 * 1024).clamp(0, size);
      try {
        final request = http.StreamedRequest('PUT', location);
        request.followRedirects = false;
        request.headers.addAll(await authorization());
        request.headers['Content-Range'] =
            offset == size ? 'bytes */$size' : 'bytes $offset-${end - 1}/$size';
        request.contentLength = end - offset;
        final responseFuture = client.send(request);
        await request.sink.addStream(file.openRead(offset, end));
        await request.sink.close();
        final response = await http.Response.fromStream(
          await responseFuture,
        ).timeout(const Duration(minutes: 2));
        if (response.statusCode == 200 || response.statusCode == 201) {
          completed = jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 308) {
          offset = _offset(response, size);
          if (offset != end) {
            throw const BackupFailure('Drive no confirmó el bloque enviado.');
          }
        } else if (response.statusCode >= 500 || response.statusCode == 429) {
          throw const SocketException('Retry');
        } else {
          _fail(response.statusCode);
        }
        failures = 0;
        progress?.call(end / size);
      } catch (error) {
        if (error is BackupFailure || ++failures > 4) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << failures));
        final query = http.Request('PUT', location);
        query.followRedirects = false;
        query.headers.addAll(await authorization());
        query.headers['Content-Range'] = 'bytes */$size';
        query.headers['Content-Length'] = '0';
        final response = await http.Response.fromStream(
          await client.send(query),
        ).timeout(const Duration(seconds: 60));
        if (response.statusCode == 200 || response.statusCode == 201) {
          completed = jsonDecode(response.body) as Map<String, dynamic>;
        } else if (response.statusCode == 308) {
          offset = _offset(response, size);
        } else {
          _fail(response.statusCode);
        }
      }
    }
    if (completed['md5Checksum'] != checksum ||
        int.tryParse('${completed['size']}') != size) {
      throw const BackupFailure('Drive no pudo verificar el respaldo subido.');
    }
    final id = completed['id'] as String;
    final committed = await _json(
      'PATCH',
      Uri.https('www.googleapis.com', '/drive/v3/files/$id', {
        'fields': _fields,
      }),
      body: {
        'appProperties': {
          'kind': kind,
          'device': deviceId,
          'state': 'complete',
        },
      },
    );
    return DriveBackup.fromJson(
      jsonDecode(committed.body) as Map<String, dynamic>,
    );
  }

  static int _offset(http.Response response, int size) {
    final range = response.headers['range'];
    if (range == null) return 0;
    final match = RegExp(r'^bytes=0-(\d+)$').firstMatch(range);
    final end = match == null ? -1 : int.parse(match.group(1)!) + 1;
    if (end < 0 || end > size) {
      throw const BackupFailure('Respuesta de subida inválida.');
    }
    return end;
  }

  Future<void> download(DriveBackup backup, File target) async {
    if (await target.exists()) {
      throw const BackupFailure('El destino ya existe.');
    }
    final request = http.Request(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files/${backup.id}', {
        'alt': 'media',
      }),
    );
    request.headers.addAll(await authorization());
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      _fail(response.statusCode);
    }
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        received += chunk.length;
        if (received >
                BackupBundle.maxBytes + BackupBundle.maxManifestBytes + 12 ||
            received > backup.size) {
          throw const BackupFailure('Tamaño de respaldo inválido.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      if (received != backup.size) {
        throw const BackupFailure('La descarga quedó incompleta.');
      }
    } catch (_) {
      await sink.close();
      await target.delete();
      rethrow;
    }
  }
}
