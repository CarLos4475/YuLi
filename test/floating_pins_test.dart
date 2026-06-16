import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_floating_pin_repository.dart';
import 'package:yuli/domain/models/floating_pin_record.dart';
import 'package:yuli/presentation/screens/flight/pinned_snapshots.dart';
import 'package:yuli/presentation/theme/lab_icons.dart';

Future<ui.Image> _testImage({int width = 200, int height = 100}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF123456),
  );
  return recorder.endRecording().toImage(width, height);
}

/// Records seam calls so controller behaviour can be asserted without Drift.
class _FakePersistence implements FloatingPinPersistence {
  int _nextId = 100;
  final List<int> inserted = [];
  final List<FloatingPin> saved = [];
  final List<FloatingPin> removed = [];
  final List<List<int>> reorders = [];

  @override
  Future<int> insert(FloatingPin pin) async {
    final id = _nextId++;
    inserted.add(id);
    return id;
  }

  @override
  void save(FloatingPin pin) => saved.add(pin);

  @override
  void remove(FloatingPin pin) => removed.add(pin);

  @override
  void reorder(List<FloatingPin> pins) =>
      reorders.add([for (final p in pins) p.dbId!]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('controller clamps, resizes, collapses, orders, and closes pins', (
    tester,
  ) async {
    final controller = FloatingPinController();
    final bounds = Rect.fromLTWH(8, 8, 392, 292);
    final first = controller.addSnapshot(
      image: await _testImage(),
      rect: const Rect.fromLTWH(0, 0, 200, 200),
      usableBounds: bounds,
    );
    final second = controller.addSnapshot(
      image: await _testImage(width: 100, height: 100),
      rect: const Rect.fromLTWH(40, 40, 120, 120),
      usableBounds: bounds,
    );

    expect(controller.value.first.id, first.id);
    expect(controller.value.last.id, second.id);
    expect(first.rect.left, 8);
    expect(first.rect.top, 8);
    expect(first.rect.height, floatingPinHeaderHeight + 100);

    controller.commitRect(
      first.id,
      const Rect.fromLTWH(40, 50, 260, 100),
      bounds,
    );
    final resized = controller.value.firstWhere((pin) => pin.id == first.id);
    expect(resized.rect.width, 260);
    expect(resized.rect.height, floatingPinHeaderHeight + 130);

    controller.toggleCollapsed(first.id);
    expect(
      controller.value.firstWhere((pin) => pin.id == first.id).collapsed,
      isTrue,
    );

    controller.bringToFront(first.id);
    expect(controller.value.last.id, first.id);

    controller.close(first.id);
    expect(controller.value.map((pin) => pin.id), isNot(contains(first.id)));
    controller.close(second.id);
  });

  testWidgets('layer appears without rebuilding host and commits drag on release', (
    tester,
  ) async {
    final controller = FloatingPinController();
    final bounds = Rect.fromLTWH(8, 8, 392, 292);
    var hostBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 420,
          height: 320,
          child: KeyedSubtree(
            key: const ValueKey('pin-layer-host'),
            child: Builder(
              builder: (_) {
                hostBuilds++;
                return FloatingPinsLayer(
                  controller: controller,
                  usableBounds: bounds,
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(hostBuilds, 1);
    final layerBoundaries = find.descendant(
      of: find.byKey(const ValueKey('pin-layer-host')),
      matching: find.byType(RepaintBoundary),
    );
    expect(layerBoundaries, findsNothing);

    final pin = controller.addSnapshot(
      image: await _testImage(),
      rect: const Rect.fromLTWH(30, 30, 160, 160),
      usableBounds: bounds,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(hostBuilds, 1);
    expect(find.byKey(ValueKey(pin.id)), findsOneWidget);
    expect(layerBoundaries, findsOneWidget);

    final initialRect = controller.value.single.rect;
    await tester.drag(
      find.byKey(ValueKey('pin-header-${pin.id}')),
      const Offset(50, 40),
    );
    await tester.pump();

    expect(controller.value.single.rect.left, initialRect.left + 50);
    expect(controller.value.single.rect.top, initialRect.top + 40);

    await tester.tap(find.byIcon(YuLiIcons.close));
    await tester.pump();
    expect(controller.value.single.id, pin.id);
    expect(find.byKey(ValueKey(pin.id)), findsOneWidget);

    await tester.pumpAndSettle();
    expect(controller.value, isEmpty);
    expect(find.byKey(ValueKey(pin.id)), findsNothing);
  });

  test('image pin persists through the seam; snapshot stays volatile', () async {
    final controller = FloatingPinController();
    final fake = _FakePersistence();
    controller.persistence = fake;
    final bounds = Rect.fromLTWH(8, 8, 800, 600);

    final img = await controller.addImage(
      filePath: '/tmp/a.jpg',
      aspectRatio: 2.0,
      rect: const Rect.fromLTWH(0, 0, 200, 0),
      usableBounds: bounds,
    );
    expect(img.dbId, isNotNull);
    expect(img.persisted, isTrue);
    expect(fake.inserted, hasLength(1));
    expect(fake.reorders, isNotEmpty); // z-order written on add
    // aspect 2.0 → body height = width / 2.
    expect(img.rect.height, floatingPinHeaderHeight + 100);

    controller.commitRect(img.id, const Rect.fromLTWH(40, 40, 160, 0), bounds);
    expect(fake.saved, isNotEmpty);

    fake.saved.clear();
    controller.toggleCollapsed(img.id);
    expect(fake.saved.single.collapsed, isTrue);

    // A volatile snapshot must NOT hit the seam.
    final snap = controller.addSnapshot(
      image: await _testImage(),
      rect: const Rect.fromLTWH(0, 0, 120, 0),
      usableBounds: bounds,
    );
    fake.saved.clear();
    controller.commitRect(snap.id, const Rect.fromLTWH(10, 10, 120, 0), bounds);
    expect(fake.saved, isEmpty);

    // Closing a persisted pin removes via the seam; a snapshot does not.
    controller.close(img.id);
    expect(fake.removed.single.dbId, img.dbId);
    controller.close(snap.id);
    expect(fake.removed, hasLength(1));
  });

  test('loadPersisted is idempotent and sits behind volatile snapshots', () async {
    final controller = FloatingPinController();
    final bounds = Rect.fromLTWH(8, 8, 800, 600);
    final snap = controller.addSnapshot(
      image: await _testImage(),
      rect: const Rect.fromLTWH(0, 0, 120, 0),
      usableBounds: bounds,
    );
    final persisted = FloatingPin(
      id: 'db1',
      dbId: 1,
      kind: FloatingPinKind.image,
      payload: ImagePinPayload(filePath: '/tmp/x.jpg', aspectRatio: 1),
      rect: const Rect.fromLTWH(0, 0, 100, 100),
    );

    controller.loadPersisted([persisted]);
    // Persisted (older) behind, the session snapshot on top (list end = front).
    expect(controller.value.map((p) => p.id).toList(), ['db1', snap.id]);
    expect(controller.persistedLoaded, isTrue);

    controller.loadPersisted([persisted]); // no-op on re-entry
    expect(controller.value.where((p) => p.id == 'db1'), hasLength(1));
  });

  group('repository round-trip', () {
    late AppDatabase db;
    late LocalFloatingPinRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LocalFloatingPinRepository(db);
    });
    tearDown(() async => db.close());

    Future<int> makeNote() async {
      final folderId = await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(name: 'f', color: '#FFFFFF'));
      return db.into(db.notes).insert(NotesCompanion.insert(folderId: folderId));
    }

    FloatingPinRecord rec(int noteId, String filename, int order) =>
        FloatingPinRecord(
          id: 0,
          noteId: noteId,
          kind: 'image',
          left: 1,
          top: 2,
          width: 100,
          height: 80,
          collapsed: false,
          sortOrder: order,
          metadata: {'filename': filename, 'aspect': 1.25},
        );

    test('insert, order, update, delete and GC references', () async {
      final noteId = await makeNote();
      final id1 = await repo.insert(rec(noteId, 'a.jpg', 0));
      final id2 = await repo.insert(rec(noteId, 'b.jpg', 1));

      var pins = await repo.forNote(noteId);
      expect(pins.map((p) => p.id).toList(), [id1, id2]);
      expect(pins.first.metadata['filename'], 'a.jpg');
      expect((pins.first.metadata['aspect'] as num).toDouble(), 1.25);

      await repo.setOrder([id2, id1]);
      pins = await repo.forNote(noteId);
      expect(pins.map((p) => p.id).toList(), [id2, id1]);

      await repo.update(
        pins.firstWhere((p) => p.id == id1).copyWith(collapsed: true),
      );
      pins = await repo.forNote(noteId);
      expect(pins.firstWhere((p) => p.id == id1).collapsed, isTrue);

      var referenced = await repo.referencedFilesByNote();
      expect(referenced[noteId], {'a.jpg', 'b.jpg'});

      await repo.delete(id1);
      referenced = await repo.referencedFilesByNote();
      expect(referenced[noteId], {'b.jpg'});
      expect(await repo.forNote(noteId), hasLength(1));
    });
  });
}
