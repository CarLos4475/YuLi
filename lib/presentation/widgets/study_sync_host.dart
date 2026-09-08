import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/backup/backup_manager.dart';
import '../../data/services/backup/backup_preferences.dart';
import '../../data/services/backup/study_background_sync.dart';
import '../../data/services/backup/study_sync.dart';
import '../../data/services/backup/study_upload_queue.dart';
import '../../data/services/crash_logger.dart';
import '../../domain/models/note.dart';
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

class _StudySyncHostState extends ConsumerState<StudySyncHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<void>? _changes;
  StreamSubscription<int>? _opportunities;
  BackupManager? _manager;
  bool _running = false;
  bool _dirty = true;
  int _revision = 0;
  int _preparedRevision = -1;
  final Set<int> _priorityNotes = {};
  bool _catchUp = false;
  bool _pendingPersisted = false;
  DateTime _lastInput = DateTime.now();
  DateTime _lastChange = DateTime.now();
  DateTime _retryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  String? _observedAccount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _opportunities = StudyActivity.opportunities.listen((noteId) {
      _priorityNotes.add(noteId);
      unawaited(_tick());
    });
    unawaited(_initialize());
  }

  bool get _canWork =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      DateTime.now().difference(_lastInput) >=
          const Duration(milliseconds: 600);

  bool get _canPrepare =>
      _canWork &&
      DateTime.now().difference(_lastChange) >= const Duration(seconds: 5);

  bool get _longIdle =>
      _canWork &&
      DateTime.now().difference(_lastChange) >= const Duration(seconds: 90);

  Future<void> _initialize() async {
    final manager = await ref.read(backupManagerProvider.future);
    if (!mounted) return;
    _manager = manager;
    await manager.local.preferences.reload();
    _observedAccount = manager.local.preferences.getString(
      'study_auto_account_v1',
    );
    _pendingPersisted =
        manager.local.preferences.getBool(studyPendingChangesPreference) ??
        false;
    _catchUp = _pendingPersisted;
    await _changes?.cancel();
    _changes = manager.local.studyChanges.listen((_) {
      _revision++;
      _dirty = true;
      _lastChange = DateTime.now();
      if (!_pendingPersisted) {
        _pendingPersisted = true;
        unawaited(_persistPending(manager));
      }
    });
    _dirty = _pendingPersisted;
  }

  Future<void> _persistPending(BackupManager manager) async {
    try {
      if (!await manager.local.preferences.setBool(
        studyPendingChangesPreference,
        true,
      )) {
        _pendingPersisted = false;
      }
    } catch (_) {
      _pendingPersisted = false;
    }
  }

  void _input() {
    _lastInput = DateTime.now();
  }

  Future<void> _tick() async {
    if (!Platform.isAndroid ||
        _running ||
        !_canPrepare ||
        DateTime.now().isBefore(_retryAfter)) {
      return;
    }
    final priority = Set<int>.from(_priorityNotes);
    final publishAll = _longIdle || _catchUp;
    final publishPriority = !publishAll && priority.isNotEmpty;
    final prepareOnly = !publishAll && !publishPriority;
    if (prepareOnly && _preparedRevision == _revision) return;
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
        _catchUp = account != null;
      }
      if (account == null || !_dirty) return;
      if (manager.busy || manager.restorePending || manager.studyRunning) {
        return;
      }
      final activeManager = manager;
      bool canContinue() =>
          _canWork &&
          !activeManager.busy &&
          !activeManager.restorePending &&
          activeManager.local.preferences.getString('study_auto_account_v1') ==
              account;
      if (!canContinue()) return;
      manager.studyRunning = true;
      await manager.local.cleanupStudyExports();
      if (!prepareOnly || StudyActivity.editors.isEmpty) {
        await PendingSaves.flush();
      }
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
      var failedNotes = 0;
      final activeNoteIds = <int>{};
      for (final folder in await folders.getActive()) {
        for (final note in await notes.getByFolder(folder.id)) {
          activeNoteIds.add(note.id);
          if (publishPriority && !priority.contains(note.id)) continue;
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
          } catch (error, stack) {
            failedNotes++;
            _recordStudyFailure(note.id, 'snapshot', error, stack);
            continue;
          }
          final key = 'note:${note.id}';
          final version = '$key\u0000$hash';
          if (known.contains(version)) continue;
          if (prepareOnly) {
            if (snapshot.note.kind != NoteKind.block) {
              try {
                activeManager.setStudyStatus(
                  'Preparando ${snapshot.note.displayTitle}',
                );
                if (!renderContext.mounted) throw StudySyncInterrupted();
                await snapshot.prepareDrawingCache(
                  renderContext,
                  activeManager.local.documents,
                  checkpoint,
                );
              } on StudySyncInterrupted {
                rethrow;
              } catch (error, stack) {
                failedNotes++;
                _recordStudyFailure(note.id, 'cache', error, stack);
              }
            }
            continue;
          }
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
          } catch (error, stack) {
            failedNotes++;
            _recordStudyFailure(note.id, 'render', error, stack);
          } finally {
            if (rendered != null && await rendered.exists()) {
              await rendered.delete();
            }
          }
        }
      }
      await cleanupStudyPdfCache(activeManager.local.documents, activeNoteIds);
      if (failedNotes > 0) {
        _dirty = true;
        _retryAfter = DateTime.now().add(const Duration(minutes: 2));
        manager.setStudyStatus(
          failedNotes == 1
              ? '1 PDF pendiente; los demás continuarán sincronizándose'
              : '$failedNotes PDF pendientes; los demás continuarán sincronizándose',
        );
        return;
      }
      if (prepareOnly) {
        if (_revision == revision) _preparedRevision = revision;
        manager.setStudyStatus('Cambios preparados; PDF pendientes');
        return;
      }
      if (publishPriority) {
        _priorityNotes.removeAll(priority);
        _dirty = true;
      } else {
        _priorityNotes.clear();
        _dirty = _revision != revision;
        if (!_dirty) {
          _catchUp = false;
          _pendingPersisted = false;
          await manager.local.preferences.remove(studyPendingChangesPreference);
        }
      }
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

  void _recordStudyFailure(
    int noteId,
    String phase,
    Object error,
    StackTrace stack,
  ) {
    CrashLogger.instance.record(
      StateError('StudyPdfFailure(${error.runtimeType})'),
      stack,
      context: 'Study PDF $phase note=$noteId',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingPersisted) {
      _catchUp = true;
      unawaited(_tick());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _changes?.cancel();
    _opportunities?.cancel();
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
