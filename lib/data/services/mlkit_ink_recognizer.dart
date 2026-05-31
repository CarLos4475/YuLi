import 'dart:ui' show Offset, Size;

import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

import '../../domain/services/ink_recognizer.dart';

/// On-device handwriting recognizer backed by ML Kit Digital Ink. Text only;
/// [InkRecognitionMode.math] throws (reserved seam — see [InkRecognizer]).
class MlkitInkRecognizer implements InkRecognizer {
  final _modelManager = DigitalInkRecognizerModelManager();
  final Map<String, DigitalInkRecognizer> _recognizers = {};

  DigitalInkRecognizer _recognizerFor(String langTag) => _recognizers
      .putIfAbsent(langTag, () => DigitalInkRecognizer(languageCode: langTag));

  @override
  Future<bool> isModelReady(String langTag) =>
      _modelManager.isModelDownloaded(langTag);

  @override
  Future<bool> downloadModel(String langTag) =>
      _modelManager.downloadModel(langTag);

  @override
  Future<List<InkCandidate>> recognize(
    List<List<Offset>> strokes, {
    String langTag = 'es',
    InkRecognitionMode mode = InkRecognitionMode.text,
    Size? writingArea,
  }) async {
    if (mode == InkRecognitionMode.math) {
      throw UnsupportedError(
        'Math recognition not implemented yet (reserved seam — see ONLINE_FEATURES.md)',
      );
    }
    final ink = _buildInk(strokes);
    if (ink.strokes.isEmpty) return const [];

    final context = writingArea == null
        ? null
        : DigitalInkRecognitionContext(
            preContext: '',
            writingArea: WritingArea(
              width: writingArea.width,
              height: writingArea.height,
            ),
          );

    final candidates =
        await _recognizerFor(langTag).recognize(ink, context: context);
    return candidates.map((c) => InkCandidate(c.text, c.score)).toList();
  }

  /// Map our point-polyline strokes into ML Kit [Ink]. Timestamps aren't stored
  /// for every stroke type (baked fountain points drop them), so we synthesize
  /// a monotonic clock — recognition only needs relative ordering.
  Ink _buildInk(List<List<Offset>> strokes) {
    final ink = Ink();
    int t = 0;
    ink.strokes = strokes.where((s) => s.length >= 2).map((s) {
      final stroke = Stroke();
      stroke.points =
          s.map((p) => StrokePoint(x: p.dx, y: p.dy, t: t += 16)).toList();
      return stroke;
    }).toList();
    return ink;
  }

  void dispose() {
    for (final r in _recognizers.values) {
      r.close();
    }
    _recognizers.clear();
  }
}
