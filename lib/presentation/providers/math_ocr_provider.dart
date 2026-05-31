import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/mathpix_key_store.dart';
import '../../data/services/mathpix_ocr_service.dart';
import '../../domain/services/math_ocr_service.dart';

final mathpixKeyStoreProvider =
    Provider<MathpixKeyStore>((ref) => MathpixKeyStore());

final mathOcrServiceProvider = Provider<MathOcrService>(
  (ref) => MathpixOcrService(ref.read(mathpixKeyStoreProvider)),
);

final mathpixHasKeysProvider =
    FutureProvider<bool>((ref) => ref.read(mathpixKeyStoreProvider).hasKeys());
