import 'dart:ui' show Offset, Size;

/// Recognition mode. Only [text] is implemented (ML Kit on-device handwriting).
/// [math] is a reserved seam: handwritten math → LaTeX will plug in here via a
/// separate engine (e.g. Mathpix, cloud) and land in a Math cell. The text
/// recognizer is the wrong tool for notation (Σ, integrals, fractions); see
/// ONLINE_FEATURES.md (v1 — OCR, "TEXTO, no matemáticas").
enum InkRecognitionMode { text, math }

/// One recognition guess. Candidates come best-first; [score] is the engine's
/// raw score (may be 0 when the engine doesn't provide one) — prefer order over
/// the absolute value.
class InkCandidate {
  final String text;
  final double score;
  const InkCandidate(this.text, this.score);
}

/// On-device handwriting recognizer (ink → text). Input is a list of strokes,
/// each a polyline of points in canvas/page coordinates. Stateless from the
/// caller's view; implementations may cache per-language engines internally.
abstract class InkRecognizer {
  /// True if the model for [langTag] (BCP-47, e.g. 'es') is already downloaded.
  Future<bool> isModelReady(String langTag);

  /// Download the model for [langTag] (needs network once). Returns success.
  Future<bool> downloadModel(String langTag);

  /// Delete the downloaded model for [langTag] to free space. Returns success.
  Future<bool> deleteModel(String langTag);

  /// Recognize [strokes] (each a polyline of points). Returns candidates
  /// best-first; empty when there's nothing to read.
  ///
  /// Throws [UnsupportedError] for [InkRecognitionMode.math] — not implemented;
  /// the seam exists so a math→LaTeX engine can be added without reshaping
  /// callers.
  Future<List<InkCandidate>> recognize(
    List<List<Offset>> strokes, {
    String langTag = 'es',
    InkRecognitionMode mode = InkRecognitionMode.text,
    Size? writingArea,
  });
}
