import 'package:flutter/material.dart';

class YuliEditorViewport extends StatefulWidget {
  final Widget child;

  const YuliEditorViewport({super.key, required this.child});

  static Rect? boundsOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ViewportScope>();
    final box = scope?.boundsKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  State<YuliEditorViewport> createState() => _YuliEditorViewportState();
}

class _YuliEditorViewportState extends State<YuliEditorViewport> {
  final _boundsKey = GlobalKey();
  final _scrollVersion = ValueNotifier(0);
  bool _scheduled = false;

  bool _scrolled(ScrollNotification notification) {
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) _scrollVersion.value++;
      });
    }
    return false;
  }

  @override
  void dispose() {
    _scrollVersion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ViewportScope(
    boundsKey: _boundsKey,
    notifier: _scrollVersion,
    child: NotificationListener<ScrollNotification>(
      onNotification: _scrolled,
      child: ClipRect(key: _boundsKey, child: widget.child),
    ),
  );
}

class _ViewportScope extends InheritedNotifier<ValueNotifier<int>> {
  final GlobalKey boundsKey;

  const _ViewportScope({
    required this.boundsKey,
    required super.notifier,
    required super.child,
  });
}

Future<T?> showYuliEditorMenu<T>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  required Color color,
  required ShapeBorder shape,
}) {
  final viewport = YuliEditorViewport.boundsOf(context);
  final target = context.findRenderObject() as RenderBox;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject() as RenderBox;
  final bounds = (viewport ?? (Offset.zero & overlay.size)).shift(
    -overlay.localToGlobal(Offset.zero),
  );
  final anchor =
      target.localToGlobal(Offset.zero, ancestor: overlay) & target.size;
  final width = (bounds.width - 16).clamp(48.0, 300.0);
  final maxHeight = (bounds.height - 16).clamp(48.0, double.infinity);
  final height = (items.fold<double>(
    16,
    (sum, item) => sum + item.height,
  )).clamp(0.0, maxHeight);
  final position = Rect.fromLTWH(
    (anchor.right - width).clamp(
      bounds.left + 8,
      (bounds.right - width - 8).clamp(bounds.left + 8, double.infinity),
    ),
    (anchor.bottom + 8).clamp(
      bounds.top + 8,
      (bounds.bottom - height - 8).clamp(bounds.top + 8, double.infinity),
    ),
    width,
    0,
  );
  return showMenu<T>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(position, Offset.zero & overlay.size),
    constraints: BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: maxHeight,
    ),
    color: color,
    shape: shape,
    items: items,
  );
}
