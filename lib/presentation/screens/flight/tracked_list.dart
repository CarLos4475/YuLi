import 'dart:collection';

class TrackedEntry<T extends Object> {
  TrackedEntry(this.value, this.position);
  T value;
  int position;
}

class TrackedList<T extends Object> extends ListBase<T> {
  TrackedList(Iterable<T> values, {this.keyOf}) {
    addAll(values);
  }

  final Object? Function(T)? keyOf;
  final List<TrackedEntry<T>> _items = [];
  final Expando<TrackedEntry<T>> _byValue = Expando();
  final Map<TrackedEntry<T>, (T?, int)> _changes = {};
  final Set<void Function(TrackedEntry<T>)> _observers = {};

  void addMutationObserver(void Function(TrackedEntry<T>) observer) =>
      _observers.add(observer);
  void removeMutationObserver(void Function(TrackedEntry<T>) observer) =>
      _observers.remove(observer);

  int? positionOf(T value) {
    final entry = _byValue[value];
    return entry != null && entry.position >= 0 && identical(entry.value, value)
        ? entry.position
        : null;
  }

  TrackedEntry<T> entryAt(int index) => _items[index];
  void acknowledge(TrackedEntry<T> entry) => _changes.remove(entry);
  Map<TrackedEntry<T>, (T?, int)> takeChanges() {
    final result = Map<TrackedEntry<T>, (T?, int)>.of(_changes);
    _changes.clear();
    return result;
  }

  void _mark(TrackedEntry<T> entry) {
    _changes[entry] = (entry.position < 0 ? null : entry.value, entry.position);
    for (final observer in _observers) {
      observer(entry);
    }
  }

  @override
  int get length => _items.length;
  @override
  set length(int value) {
    if (value > length) throw UnsupportedError('Use add or insert');
    removeRange(value, length);
  }

  @override
  T operator [](int index) => _items[index].value;
  @override
  void operator []=(int index, T value) {
    final entry = _items[index];
    if (identical(entry.value, value)) return;
    entry.value = value;
    _byValue[value] = entry;
    _mark(entry);
  }

  TrackedEntry<T> _entry(T value, int position) {
    final previous = _byValue[value];
    final entry =
        previous != null && previous.position < 0
            ? previous
            : TrackedEntry(value, -1);
    entry.value = value;
    entry.position = position;
    _byValue[value] = entry;
    _mark(entry);
    return entry;
  }

  @override
  void add(T element) => _items.add(_entry(element, length));
  @override
  void addAll(Iterable<T> iterable) {
    for (final value in identical(iterable, this) ? toList() : iterable) {
      add(value);
    }
  }

  @override
  void insert(int index, T element) => insertAll(index, [element]);
  @override
  void insertAll(int index, Iterable<T> iterable) {
    RangeError.checkValueInInterval(index, 0, length);
    final values = iterable.toList();
    if (values.isEmpty) return;
    _items.insertAll(index, [
      for (var i = 0; i < values.length; i++) _entry(values[i], index + i),
    ]);
    _reposition(index + values.length);
  }

  void _reposition(int start) {
    for (var i = start; i < length; i++) {
      final entry = _items[i];
      if (entry.position == i) continue;
      entry.position = i;
      _mark(entry);
    }
  }

  void _retire(TrackedEntry<T> entry) {
    entry.position = -1;
    _mark(entry);
  }

  @override
  T removeAt(int index) {
    final entry = _items.removeAt(index);
    _retire(entry);
    _reposition(index);
    return entry.value;
  }

  @override
  T removeLast() => removeAt(length - 1);
  @override
  void removeRange(int start, int end) {
    RangeError.checkValidRange(start, end, length);
    if (start == end) return;
    for (var i = start; i < end; i++) {
      _retire(_items[i]);
    }
    _items.removeRange(start, end);
    _reposition(start);
  }

  @override
  void clear() => removeRange(0, length);
  @override
  void removeWhere(bool Function(T) test) {
    _items.removeWhere((entry) {
      if (!test(entry.value)) return false;
      _retire(entry);
      return true;
    });
    _reposition(0);
  }

  @override
  void retainWhere(bool Function(T) test) =>
      removeWhere((value) => !test(value));
  @override
  void sort([int Function(T, T)? compare]) =>
      replaceAll(toList()..sort(compare));
  @override
  void setRange(int start, int end, Iterable<T> iterable, [int skipCount = 0]) {
    RangeError.checkValidRange(start, end, length);
    final values = iterable.skip(skipCount).take(end - start).toList();
    if (values.length != end - start) throw StateError('Not enough elements');
    for (var i = start; i < end; i++) {
      this[i] = values[i - start];
    }
  }

  // Full history restores reconcile identities here, at edit time, never at save time.
  void replaceAll(Iterable<T> values) {
    if (identical(values, this)) return;
    final desired = values.toList();
    final byKey = <Object, TrackedEntry<T>>{};
    if (keyOf != null) {
      for (final entry in _items) {
        final key = keyOf!(entry.value);
        if (key != null) byKey[key] = entry;
      }
    }
    final used = <TrackedEntry<T>>{};
    final next = <TrackedEntry<T>>[];
    for (var i = 0; i < desired.length; i++) {
      final value = desired[i];
      final key = keyOf?.call(value);
      var entry = _byValue[value] ?? (key == null ? null : byKey[key]);
      if (entry == null || !used.add(entry)) {
        entry = TrackedEntry(value, -1);
        used.add(entry);
      }
      final changed = !identical(entry.value, value) || entry.position != i;
      entry.value = value;
      entry.position = i;
      _byValue[value] = entry;
      if (changed) _mark(entry);
      next.add(entry);
    }
    for (final entry in _items) {
      if (!used.contains(entry)) _retire(entry);
    }
    _items
      ..clear()
      ..addAll(next);
  }
}
