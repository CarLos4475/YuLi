import '../models/canvas_ocr.dart';

abstract class CanvasOcrRepository {
  Future<CanvasOcrPage?> read(int blockId);
  Future<bool> save(int blockId, int revision, List<CanvasOcrSegment> segments);
  Future<List<CanvasOcrHit>> search(String query);
  Future<String> contextForNote(int noteId, {int? blockId});
}
