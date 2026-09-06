import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/backup/backup_manager.dart';
import '../../data/services/backup/study_background_sync.dart';
import '../../data/services/backup/study_sync.dart';
import '../../data/services/backup/study_upload_queue.dart';
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
  bool _dirty = true;
  int _revision = 0;
  DateTime _lastInput = DateTime.now();
  DateTime _lastChange = DateTime.now();
  DateTime _retryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  String? _observedAccount;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_initialize());
  }

  bool get _canRender =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      DateTime.now().difference(_lastInput) >=
          const Duration(milliseconds: 600) &&
      DateTime.now().difference(_lastChange) >= const Duration(seconds: 2);

  Future<void> _initialize() async {
    final manager = await ref.read(backupManagerProvider.future);
    if (!mounted) return;
    _manager = manager;
    await _changes?.cancel();
    _changes = manager.local.studyChanges.listen((_) {
      _revision++;
      _dirty = true;
      _lastChange = DateTime.now();
    });
    _dirty = true;
  }

  void _input() {
    _lastInput = DateTime.now();
  }

  Future<void> _tick() async {
    if (!Platform.isAndroid ||
        _running ||
        !_canRender ||
        DateTime.now().isBefore(_retryAfter)) {
      return;
    }
    _running = true;
    OverlayEntry? entry;
    BackupManager? operationManager;
    var queued = false;
    try {
      final BackupManager manager;
      final initializedManager = _manager;
      if (initializedManager != null) {
        manager = initializedManager;
      } else {
        manager = await ref.read(backupManagerProvider.future);
      }
      operationManager = manager;
      await manager.local.preferences.reload();
      final account = manager.local.preferences.getString(
        'study_auto_account_v1',
      );
      if (account != _observedAccount) {
        _observedAccount = account;
        _dirty = account != null;
      }
      if (account == null || !_dirty) return;
      if (manager.busy || manager.restorePending || manager.studyRunning) {
        return;
      }
      final activeManager = manager;
      bool canContinue() =>
          _canRender &&
          !activeManager.busy &&
          !activeManager.restorePending &&
          activeManager.local.preferences.getString('study_auto_account_v1') ==
              account;
      if (!canContinue()) return;
      manager.studyRunning = true;
      await manager.local.cleanupStudyExports();
      if (StudyActivity.editors.isEmpty) await PendingSaves.flush();
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
      final queue = StudyUploadQueue(
        activeManager.local.documents,
        activeManager.local.preferences,
      );
      final known = await queue.knownVersions(account);
      queued = (await queue.pending(account: account)).isNotEmpty;
      var invalidSnapshots = false;
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
          final key = 'note:${note.id}';
          final version = '$key\u0000$hash';
          if (known.contains(version)) continue;
          activeManager.setStudyStatus(
            'Preparando ${snapshot.note.displayTitle}',
          );
          File? rendered;
          try {
            if (!renderContext.mounted) throw StudySyncInterrupted();
            rendered = await snapshot.render(
              renderContext,
              activeManager.local.documents,
              checkpoint,
            );
            await queue.add(
              account: account,
              key: key,
              folderKey: 'folder:${snapshot.folder.id}',
              folderName: snapshot.folder.name,
              name:
                  '${snapshot.note.displayTitle.replaceAll(RegExp(r'[\x00-\x1f/\\]'), ' ').trim()}.pdf',
              hash: hash,
              rendered: rendered,
            );
            rendered = null;
            known.add(version);
            queued = true;
          } on StudySyncInterrupted {
            rethrow;
          } catch (_) {
            invalidSnapshots = true;
          } finally {
            if (rendered != null && await rendered.exists()) {
              await rendered.delete();
            }
          }
        }
      }
      if (invalidSnapshots) throw StateError('Hay apuntes pendientes.');
      _dirty = _revision != revision;
      queued = (await queue.pending(account: account)).isNotEmpty;
      manager.setStudyStatus(
        queued ? 'PDF preparados para subir' : 'PDF actualizados en Drive',
      );
    } on StudySyncInterrupted {
      operationManager?.setStudyStatus(
        'PDF pendientes; se retomarán durante una pausa breve',
      );
    } catch (_) {
      _retryAfter = DateTime.now().add(const Duration(minutes: 2));
      operationManager?.setStudyStatus(
        'PDF pendientes. Se reintentará; revisa conexión, permisos y espacio libre',
      );
    } finally {
      if (queued && operationManager != null) {
        final account = operationManager.local.preferences.getString(
          'study_auto_account_v1',
        );
        if (account != null) {
          try {
            await operationManager.auth.reconnectSilently();
            await operationManager.auth.cacheBackgroundAuthorization(account);
            await StudyBackgroundSync.schedulePending();
          } catch (_) {
            _retryAfter = DateTime.now().add(const Duration(minutes: 2));
            _dirty = true;
            operationManager.setStudyStatus(
              'PDF preparados. Se reintentará la conexión con Google',
            );
          }
        }
      }
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
