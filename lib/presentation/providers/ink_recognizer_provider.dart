import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/mlkit_ink_recognizer.dart';
import '../../domain/services/ink_recognizer.dart';

/// On-device handwriting recognizer (ink → text). Feature availability is gated
/// on the language model being downloaded — check [InkRecognizer.isModelReady].
final inkRecognizerProvider = Provider<InkRecognizer>((ref) {
  final recognizer = MlkitInkRecognizer();
  ref.onDispose(recognizer.dispose);
  return recognizer;
});

/// Default handwriting language (BCP-47). Spanish, matching the user.
const kInkDefaultLang = 'es';
