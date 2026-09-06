import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/services/backup/drive_backup_client.dart';
import 'package:yuli/data/services/backup/study_sync.dart';

class FakeStudyDrive extends DriveBackupClient {
  FakeStudyDrive()
    : super(MockClient((_) => throw UnimplementedError()), () async => {});
  final files = <String, Map<String, dynamic>>{};
  int reserved = 0, uploads = 0, creates = 0;
  bool failAfterUpload = false;
  @override
  Future<String> reserveId() async => 'id-${++reserved}';
  @override
  Future<List<Map<String, dynamic>>> studyFiles(String library) async =>
      files.values
          .where((f) => (f['appProperties'] as Map)['library'] == library)
          .toList();
  @override
  Future<Map<String, dynamic>?> studyFile(String id) async => files[id];
  @override
  Future<void> createStudyFolder(
    String id,
    String name,
    String library,
    String key,
    String? parent,
  ) async {
    creates++;
    files[id] = {
      'id': id,
      'name': name,
      'parents': [if (parent != null) parent],
      'appProperties': {'library': library, 'studyKey': key},
    };
  }

  @override
  Future<void> moveStudyFile(
    Map<String, dynamic> remote,
    String name,
    String? parent,
  ) async {
    remote['name'] = name;
    if (parent != null) remote['parents'] = [parent];
  }

  @override
  Future<DriveBackup> upload(
    File file,
    String deviceId, {
    void Function(double)? progress,
    bool study = false,
    String? targetId,
    String? parentId,
    String? name,
    bool update = false,
    Map<String, String>? studyProperties,
  }) async {
    uploads++;
    expect(update, files.containsKey(targetId));
    files[targetId!] = {
      'id': targetId,
      'name': name,
      'parents': [parentId],
      'appProperties': {
        ...?studyProperties,
        'state': failAfterUpload ? 'pending' : 'complete',
      },
    };
    if (failAfterUpload) {
      failAfterUpload = false;
      throw const SocketException('Interrupted');
    }
    return DriveBackup(
      targetId,
      name!,
      DateTime(2026),
      await file.length(),
      deviceId,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late SharedPreferences prefs;
  late FakeStudyDrive drive;
  late StudySync sync;
  var renders = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    temp = await Directory.systemTemp.createTemp('study_test_');
    drive = FakeStudyDrive();
    sync = StudySync(prefs, drive, 'account');
    renders = 0;
  });
  tearDown(() async {
    drive.client.close();
    await temp.delete(recursive: true);
  });
  StudyItem item({
    String hash = 'v1',
    String key = 'note:1',
    String folder = 'folder:1',
    String name = 'Nota.pdf',
  }) => StudyItem(
    key: key,
    folderKey: folder,
    folderName: 'Carpeta',
    name: name,
    hash: hash,
    render: () async {
      renders++;
      return File('${temp.path}/$renders.pdf').writeAsString('%PDF-test');
    },
  );
  Future<void> run(List<StudyItem> items) =>
      sync.run(Stream.fromIterable(items), () => true, (_) {});

  test(
    'initial library is grouped and unchanged PDFs are not rendered again',
    () async {
      await run([item(), item(key: 'note:2', folder: 'folder:2')]);
      expect(drive.creates, 3);
      expect(drive.uploads, 2);
      expect(
        drive.files.values.where((f) => f['name'] == 'Respaldo').length,
        1,
      );
      await run([item(), item(key: 'note:2', folder: 'folder:2')]);
      expect(renders, 2);
      expect(drive.uploads, 2);
    },
  );
  test('changed and moved note replaces the same remote ID', () async {
    await run([item()]);
    final id = drive.files.entries.last.key;
    await run([item(hash: 'v2', folder: 'folder:2', name: 'Renombrada.pdf')]);
    expect(drive.files[id]?['name'], 'Renombrada.pdf');
    expect(
      drive.files.values
          .where((f) => (f['appProperties'] as Map)['studyKey'] == 'note:1')
          .length,
      1,
    );
    expect(drive.uploads, 2);
  });
  test('interrupted upload resumes by ID without a duplicate', () async {
    drive.failAfterUpload = true;
    await expectLater(run([item()]), throwsA(isA<SocketException>()));
    final count = drive.files.length;
    sync = StudySync(prefs, drive, 'account');
    await run([item()]);
    expect(drive.files.length, count);
    expect(await temp.list().length, 0);
  });
  test('persistent prepared PDF survives a failed upload', () async {
    final prepared = File('${temp.path}/prepared.pdf')
      ..writeAsStringSync('%PDF-test');
    drive.failAfterUpload = true;
    await expectLater(
      run([
        StudyItem(
          key: 'note:1',
          folderKey: 'folder:1',
          folderName: 'Carpeta',
          name: 'Nota.pdf',
          hash: 'v1',
          render: () async => prepared,
          persistentFile: true,
        ),
      ]),
      throwsA(isA<SocketException>()),
    );
    expect(await prepared.exists(), isTrue);
  });
  test('disabling stops publication before any remote operation', () async {
    await expectLater(
      sync.run(Stream.value(item()), () => false, (_) {}),
      throwsA(isA<StudySyncInterrupted>()),
    );
    expect(drive.files, isEmpty);
  });
}
