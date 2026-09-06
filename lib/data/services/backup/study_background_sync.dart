import 'dart:io';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'drive_backup_client.dart';
import 'google_backup_auth.dart';
import 'study_sync.dart';
import 'study_upload_queue.dart';

const _studyUploadTask = 'yuli.study.upload';
const _studyUploadWork = 'yuli-study-upload';
const _studyCatchUpWork = 'yuli-study-catch-up';

@pragma('vm:entry-point')
void studyBackgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _studyUploadTask) return true;
    DartPluginRegistrant.ensureInitialized();
    return runStudyUploadWorker();
  });
}

Future<bool> runStudyUploadWorker() async {
  final client = http.Client();
  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final account = preferences.getString('study_auto_account_v1');
    if (account == null) return true;
    final documents = await getApplicationDocumentsDirectory();
    final queue = StudyUploadQueue(documents, preferences);
    final entries = await queue.pending(account: account);
    if (entries.isEmpty) return true;
    final headers = await GoogleBackupAuth.backgroundHeaders(account);
    if (headers == null) return false;
    final drive = DriveBackupClient(client, () async => headers);
    bool enabled() => preferences.getString('study_auto_account_v1') == account;
    final items = entries.map(
      (entry) => StudyItem(
        key: entry.key,
        folderKey: entry.folderKey,
        folderName: entry.folderName,
        name: entry.name,
        hash: entry.hash,
        render: () async => entry.file,
        persistentFile: true,
        onComplete: () => queue.complete(entry),
      ),
    );
    await StudySync(
      preferences,
      drive,
      account,
    ).run(Stream.fromIterable(items), enabled, (_) {});
    return true;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

class StudyBackgroundSync {
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(studyBackgroundDispatcher);
  }

  static Future<void> schedulePending() {
    if (!Platform.isAndroid) return Future.value();
    return Workmanager().registerOneOffTask(
      _studyUploadWork,
      _studyUploadTask,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresStorageNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
  }

  static Future<void> ensureCatchUp(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (!enabled) {
      await Workmanager().cancelByUniqueName(_studyCatchUpWork);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _studyCatchUpWork,
      _studyUploadTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresStorageNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );
  }

  static Future<void> cancelPending() async {
    if (!Platform.isAndroid) return;
    await Workmanager().cancelByUniqueName(_studyUploadWork);
    await Workmanager().cancelByUniqueName(_studyCatchUpWork);
  }
}
