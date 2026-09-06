import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/backup/backup_manager.dart';
import '../../data/services/backup/drive_backup_client.dart';
import '../../data/services/backup/study_sync.dart';
import '../../domain/services/pending_saves.dart';
import '../../domain/services/study_activity.dart';
import '../providers/database_providers.dart';
import '../utils/study_pdf_renderer.dart';

final studyNavigatorKey = GlobalKey<NavigatorState>();

class StudySyncHost extends ConsumerStatefulWidget {
  final Widget child;
  const StudySyncHost({super.key, required this.child});
  @override
  ConsumerState<StudySyncHost> createState() => _StudySyncHostState();
}

class _StudySyncHostState extends ConsumerState<StudySyncHost> {
  Timer? _timer;
  StreamSubscription<void>? _changes;
  BackupManager? _manager;
  bool _running = false;
  int _revision = 0;
  int _finishedRevision = -1;
  DateTime _lastInput = DateTime.now();
  DateTime _retryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  String? _finishedAccount;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  bool get _idle =>
      mounted &&
      StudyActivity.editors.isEmpty &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      DateTime.now().difference(_lastInput) >= const Duration(seconds: 10);

  void _input() {
    _lastInput = DateTime.now();
  }

  Future<void> _tick() async {
    if (!Platform.isAndroid ||
        _running ||
        !_idle ||
        DateTime.now().isBefore(_retryAfter)) {
      return;
    }
    _running = true;
    OverlayEntry? entry;
    BackupManager? operationManager;
    try {
      final manager = await ref.read(backupManagerProvider.future);
      operationManager = manager;
      if (!identical(_manager, manager)) {
        await _changes?.cancel();
        _manager = manager;
        _changes = manager.local.studyChanges.listen((_) {
          _revision++;
        });
      }
      final account = manager.local.preferences.getString(
        'study_auto_account_v1',
      );
      if (account == null) {
        _finishedAccount = null;
        return;
      }
      if (manager.busy || manager.restorePending || manager.studyRunning) {
        return;
      }
      if (account == _finishedAccount && _revision == _finishedRevision) return;
      await manager.auth.reconnectSilently();
      if (manager.auth.account?.id != account) return;
      final activeManager = manager;
      bool canContinue() =>
          _idle &&
          !activeManager.busy &&
          !activeManager.restorePending &&
          activeManager.auth.account?.id == account &&
          activeManager.local.preferences.getString('study_auto_account_v1') ==
              account;
      if (!canContinue()) return;
      manager.studyRunning = true;
      await manager.local.cleanupStudyExports();
      await PendingSaves.flush();
      final revision = _revision;
      final overlay = studyNavigatorKey.currentState?.overlay;
      if (overlay == null) return;
      final ready = Completer<BuildContext>();
      entry = OverlayEntry(
        builder: (context) {
          if (!ready.isCompleted) ready.complete(context);
          return const SizedBox.shrink();
        },
      );
      overlay.insert(entry);
      final renderContext = await ready.future;
      Future<void> checkpoint() async {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!canContinue()) throw StudySyncInterrupted();
      }

      final notes = ref.read(noteRepositoryProvider);
      final folders = ref.read(folderRepositoryProvider);
      final blocks = ref.read(noteBlockRepositoryProvider);
      final strokes = ref.read(drawingStrokeRepositoryProvider);
      final tasks = ref.read(taskRepositoryProvider);
      var invalidSnapshots = false;
      Stream<StudyItem> items() async* {
        for (final folder in await folders.getActive()) {
          for (final note in await notes.getByFolder(folder.id)) {
            await checkpoint();
            StudySnapshot? snapshot;
            String hash;
            try {
              snapshot = await activeManager.local.readConsistent(
                () => StudySnapshot.read(
                  note.id,
                  notes,
                  folders,
                  blocks,
                  strokes,
                  tasks,
                  activeManager.local.documents.path,
                ),
              );
              if (snapshot == null) continue;
              hash = await snapshot.fingerprint();
            } catch (_) {
              invalidSnapshots = true;
              continue;
            }
            final saved = snapshot;
            yield StudyItem(
              key: 'note:${note.id}',
              folderKey: 'folder:${snapshot.folder.id}',
              folderName: snapshot.folder.name,
              name:
                  '${snapshot.note.displayTitle.replaceAll(RegExp(r'[\x00-\x1f/\\]'), ' ').trim()}.pdf',
              hash: hash,
              render:
                  () => saved.render(
                    renderContext,
                    activeManager.local.documents,
                    checkpoint,
                  ),
            );
          }
        }
      }

      final drive = DriveBackupClient(manager.drive.client, () {
        if (!canContinue()) throw StudySyncInterrupted();
        return activeManager.auth.headers();
      });
      await StudySync(
        manager.local.preferences,
        drive,
        account,
      ).run(items(), canContinue, manager.setStudyStatus);
      if (invalidSnapshots) throw StateError('Hay apuntes pendientes.');
      _finishedRevision = revision;
      _finishedAccount = account;
    } on StudySyncInterrupted {
      operationManager?.setStudyStatus(
        'PDF pendientes; se retomarán al terminar de editar',
      );
    } catch (_) {
      _retryAfter = DateTime.now().add(const Duration(minutes: 2));
      operationManager?.setStudyStatus(
        'PDF pendientes. Se reintentará; revisa conexión, permisos y espacio libre',
      );
    } finally {
      entry?.remove();
      entry?.dispose();
      if (operationManager != null) operationManager.studyRunning = false;
      _running = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _input(),
    onPointerMove: (_) => _input(),
    onPointerSignal: (_) => _input(),
    child: widget.child,
  );
}
