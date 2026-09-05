import 'dart:ui';

class NotebookRasterState {
  Rect? pendingInk;
  Rect? editedRegion;
  Rect? queuedPatch;
  int generation = 0;

  void append(Rect region) {
    pendingInk = pendingInk?.expandToInclude(region) ?? region;
    if (editedRegion != null) {
      editedRegion = editedRegion!.expandToInclude(region);
    }
  }

  Rect edit(Rect region) {
    final expanded =
        pendingInk == null ? region : region.expandToInclude(pendingInk!);
    editedRegion = editedRegion?.expandToInclude(expanded) ?? expanded;
    return editedRegion!;
  }

  void queue(Rect region) {
    queuedPatch = queuedPatch?.expandToInclude(region) ?? region;
  }

  void accept() {
    pendingInk = null;
    editedRegion = null;
    queuedPatch = null;
  }
}
