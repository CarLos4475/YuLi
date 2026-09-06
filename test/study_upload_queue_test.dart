import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/services/backup/study_upload_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  late SharedPreferences preferences;
  late StudyUploadQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    documents = await Directory.systemTemp.createTemp('study_queue_test_');
    queue = StudyUploadQueue(documents, preferences);
  });

  tearDown(() => documents.delete(recursive: true));

  Future<void> add(String hash, {String account = 'account'}) async {
    final rendered = File('${documents.path}/rendered.pdf');
    await rendered.writeAsString('%PDF-test');
    await queue.add(
      account: account,
      key: 'note:1',
      folderKey: 'folder:1',
      folderName: 'Carpeta',
      name: 'Nota.pdf',
      hash: hash,
      rendered: rendered,
    );
  }

  test('persists a prepared PDF until upload completes', () async {
    final hash = ''.padLeft(64, 'a');
    await add(hash);

    final restored = StudyUploadQueue(documents, preferences);
    final entries = await restored.pending(account: 'account');
    expect(entries, hasLength(1));
    expect(entries.single.hash, hash);
    expect(await entries.single.file.exists(), isTrue);

    await restored.complete(entries.single);
    expect(await restored.pending(account: 'account'), isEmpty);
    expect(await restored.knownVersions('account'), {'note:1\u0000$hash'});
  });

  test('new versions replace older pending PDFs for the same note', () async {
    await add(''.padLeft(64, 'a'));
    await add(''.padLeft(64, 'b'));

    final entries = await queue.pending(account: 'account');
    expect(entries, hasLength(1));
    expect(entries.single.hash, ''.padLeft(64, 'b'));
  });

  test('queues are isolated by Google account', () async {
    await add(''.padLeft(64, 'a'), account: 'first');
    await add(''.padLeft(64, 'b'), account: 'second');

    expect(await queue.pending(account: 'first'), hasLength(1));
    expect(await queue.pending(account: 'second'), hasLength(1));
    await queue.discardAccount('first');
    expect(await queue.pending(account: 'first'), isEmpty);
    expect(await queue.pending(account: 'second'), hasLength(1));
  });
}
