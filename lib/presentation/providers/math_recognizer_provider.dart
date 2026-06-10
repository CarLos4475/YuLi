import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/local_math_recognizer.dart';
import '../../domain/services/math_recognizer.dart';

final mathRecognizerProvider = Provider<MathRecognizer>((_) {
  return LocalMathRecognizer();
});
