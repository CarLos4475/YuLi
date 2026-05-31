abstract class MathOcrService {
  Future<String> recognizeImageDataUri(String dataUri);
}

class MathOcrException implements Exception {
  final String message;
  const MathOcrException(this.message);

  @override
  String toString() => message;
}
