import 'dart:ui' show Offset;

class MathRecognitionResult {
  final String latex;
  final bool isFallback;

  const MathRecognitionResult({required this.latex, this.isFallback = false});
}

class MathRecognitionException implements Exception {
  final String message;

  const MathRecognitionException(this.message);

  @override
  String toString() => message;
}

abstract class MathRecognizer {
  Future<MathRecognitionResult> recognize(List<List<Offset>> strokes);
}
