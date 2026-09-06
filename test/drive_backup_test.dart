import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuli/data/services/backup/backup_bundle.dart';
import 'package:yuli/data/services/backup/drive_backup_client.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('yuli_drive_test_'),
  );
  tearDown(() async => root.delete(recursive: true));
  Future<Map<String, String>> headers() async => {
    'Authorization': 'Bearer test-token',
  };

  test('study PDF updates use PATCH and retain the assigned ID', () async {
    final file = File('${root.path}/note.pdf')..writeAsBytesSync([1, 2, 3]);
    var committed = false;
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/upload/drive/v3/files') &&
          request.method == 'PATCH') {
        expect(request.url.path, '/upload/drive/v3/files/stable-id');
        final body = jsonDecode(request.body) as Map;
        expect(body.containsKey('parents'), isFalse);
        expect(body['name'], 'Nota.pdf');
        return http.Response(
          '',
          200,
          headers: {
            'location':
                'https://www.googleapis.com/upload/drive/v3/files?upload_id=study',
          },
        );
      }
      if (request.method == 'PUT') {
        return http.Response(
          jsonEncode({
            'id': 'stable-id',
            'size': '3',
            'md5Checksum': md5.convert([1, 2, 3]).toString(),
          }),
          200,
        );
      }
      expect(request.method, 'PATCH');
      expect(request.url.path, '/drive/v3/files/stable-id');
      expect((jsonDecode(request.body) as Map)['appProperties']['hash'], 'v2');
      committed = true;
      return http.Response(
        jsonEncode({
          'id': 'stable-id',
          'name': 'Nota.pdf',
          'size': '3',
          'createdTime': '2026-09-06T00:00:00Z',
        }),
        200,
      );
    });
    await DriveBackupClient(client, headers).upload(
      file,
      'library',
      study: true,
      targetId: 'stable-id',
      parentId: 'folder',
      name: 'Nota.pdf',
      update: true,
      studyProperties: {'hash': 'v2'},
    );
    expect(committed, isTrue);
    client.close();
  });

  test(
    'uploads a new object and commits only after checksum confirmation',
    () async {
      final file = File('${root.path}/backup.yuli');
      await file.writeAsBytes([1, 2, 3, 4]);
      var committed = false;
      var uploaded = false;
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.url.toString(), isNot(contains('test-token')));
        if (request.method == 'GET') {
          return http.Response('{"files":[{"id":"folder"}]}', 200);
        }
        if (request.method == 'POST') {
          final metadata = jsonDecode(request.body) as Map;
          expect(metadata['appProperties']['state'], 'pending');
          return http.Response(
            '',
            200,
            headers: {
              'location':
                  'https://www.googleapis.com/upload/drive/v3/files?upload_id=test',
            },
          );
        }
        if (request.method == 'PUT') {
          expect(request.headers['Content-Range'], 'bytes 0-3/4');
          expect(request.bodyBytes, [1, 2, 3, 4]);
          uploaded = true;
          return http.Response(
            jsonEncode({
              'id': 'new-backup',
              'size': '4',
              'md5Checksum': md5.convert([1, 2, 3, 4]).toString(),
            }),
            200,
          );
        }
        expect(uploaded, isTrue);
        expect(request.method, 'PATCH');
        expect(request.url.path, '/drive/v3/files/new-backup');
        expect(
          (jsonDecode(request.body) as Map)['appProperties']['state'],
          'complete',
        );
        committed = true;
        return http.Response(
          jsonEncode({
            'id': 'new-backup',
            'name': 'backup.yuli',
            'createdTime': '2026-09-05T00:00:00Z',
            'size': '4',
            'appProperties': {'device': 'tablet-1'},
          }),
          200,
        );
      });
      final backup = await DriveBackupClient(
        client,
        headers,
      ).upload(file, 'tablet-1');
      expect(backup.id, 'new-backup');
      expect(committed, isTrue);
      client.close();
    },
  );

  test('never sends account credentials to an arbitrary upload URL', () async {
    final file = File('${root.path}/backup.yuli')..writeAsBytesSync([1]);
    final client = MockClient((request) async {
      expect(request.url.host, 'www.googleapis.com');
      if (request.method == 'GET') {
        return http.Response('{"files":[{"id":"folder"}]}', 200);
      }
      return http.Response(
        '',
        200,
        headers: {'location': 'https://example.org/upload'},
      );
    });
    await expectLater(
      DriveBackupClient(client, headers).upload(file, 'tablet'),
      throwsA(isA<BackupFailure>()),
    );
    client.close();
  });

  test('incomplete downloads are deleted', () async {
    final target = File('${root.path}/incomplete.yuli');
    final client = MockClient((_) async => http.Response.bytes([1, 2], 200));
    final backup = DriveBackup('id', 'backup', DateTime(2026), 3, 'tablet');
    await expectLater(
      DriveBackupClient(client, headers).download(backup, target),
      throwsA(isA<BackupFailure>()),
    );
    expect(await target.exists(), isFalse);
    client.close();
  });

  test('lists only completed YuLi copies and follows pagination', () async {
    var pages = 0;
    final client = MockClient((request) async {
      expect(request.url.queryParameters['q'], contains("value='complete'"));
      expect(
        request.url.queryParameters['q'],
        contains("value='yuli-backup-v1'"),
      );
      pages++;
      return http.Response(
        jsonEncode({'files': [], if (pages == 1) 'nextPageToken': 'next'}),
        200,
      );
    });
    expect(await DriveBackupClient(client, headers).list(), isEmpty);
    expect(pages, 2);
    client.close();
  });
}
