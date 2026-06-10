import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/services/math_recognizer.dart';

class MathInputTensor {
  final Float32List values;
  final List<int> shape;

  const MathInputTensor(this.values, this.shape);
}

class MathFeatureTensor {
  final Float32List values;
  final List<int> shape;

  const MathFeatureTensor(this.values, this.shape);
}

class LocalMathRecognizer implements MathRecognizer {
  static const encoderAsset = 'math_model/exported/encoder.onnx';
  static const encoderDataAsset = 'math_model/exported/encoder.onnx.data';
  static const decoderAsset = 'math_model/exported/decoder_step.onnx';
  static const decoderDataAsset = 'math_model/exported/decoder_step.onnx.data';
  static const runtimeAsset = 'math_model/exported/math_runtime.json';
  static const vocabAsset = 'math_model/exported/vocab.json';

  final OnnxRuntime _ort;

  Map<int, String>? _vocab;
  int _bosId = 1;
  int _eosId = 2;
  int _validVocabSize = 1175;
  int _maxSeqLen = 512;
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;

  LocalMathRecognizer({OnnxRuntime? ort}) : _ort = ort ?? OnnxRuntime();

  @override
  Future<MathRecognitionResult> recognize(List<List<Offset>> strokes) async {
    if (strokes.isEmpty) {
      throw const MathRecognitionException('NO HAY TRAZOS PARA RECONOCER.');
    }
    await _loadMetadata();
    await _loadSessions();

    final tensor = renderMathInputTensor(strokes);
    final features = await _runEncoder(tensor);
    final tokenIds = await _generateTokenIds(features);
    final latex = _postProcessLatex(_decodeTokenIds(tokenIds));
    if (latex.isEmpty) {
      throw const MathRecognitionException('MATH LOCAL NO GENERÓ LATEX.');
    }
    return MathRecognitionResult(latex: latex);
  }

  Future<void> _loadMetadata() async {
    if (_vocab != null) return;
    final vocabRaw = await rootBundle.loadString(vocabAsset);
    final vocabJson = jsonDecode(vocabRaw) as Map<String, dynamic>;
    final entries = vocabJson['vocab'] as Map<String, dynamic>;
    _vocab = {
      for (final entry in entries.entries)
        int.parse(entry.key): entry.value as String,
    };

    final runtimeRaw = await rootBundle.loadString(runtimeAsset);
    final runtimeJson = jsonDecode(runtimeRaw) as Map<String, dynamic>;
    final tokenJson = runtimeJson['tokens'] as Map<String, dynamic>;
    _bosId = tokenJson['bos_id'] as int? ?? _bosId;
    _eosId = tokenJson['eos_id'] as int? ?? _eosId;
    _validVocabSize = tokenJson['valid_vocab_size'] as int? ?? _validVocabSize;
    _maxSeqLen = tokenJson['max_seq_len'] as int? ?? _maxSeqLen;
  }

  Future<void> _loadSessions() async {
    if (_encoderSession != null && _decoderSession != null) return;

    final encoderPath = await _copyAssetModel(encoderAsset, encoderDataAsset);
    final decoderPath = await _copyAssetModel(decoderAsset, decoderDataAsset);

    _encoderSession ??= await _ort.createSession(encoderPath);
    _decoderSession ??= await _ort.createSession(decoderPath);
  }

  Future<String> _copyAssetModel(String modelAsset, String dataAsset) async {
    final dir = await getApplicationSupportDirectory();
    final modelDir = Directory(p.join(dir.path, 'math_model', 'exported'));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final modelPath = p.join(modelDir.path, p.basename(modelAsset));
    final dataPath = p.join(modelDir.path, p.basename(dataAsset));
    await _copyAssetIfNeeded(modelAsset, modelPath);
    await _copyAssetIfNeeded(dataAsset, dataPath);
    return modelPath;
  }

  Future<void> _copyAssetIfNeeded(String asset, String targetPath) async {
    final bytes = await rootBundle.load(asset);
    final file = File(targetPath);
    if (await file.exists() && await file.length() == bytes.lengthInBytes) {
      return;
    }
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  Future<MathFeatureTensor> _runEncoder(MathInputTensor tensor) async {
    final session = _encoderSession;
    if (session == null) {
      throw const MathRecognitionException('ENCODER MATH NO ESTÁ CARGADO.');
    }

    final input = await OrtValue.fromList(tensor.values, tensor.shape);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run({'image': input});
      final features = outputs['features'];
      if (features == null) {
        throw const MathRecognitionException(
          'ENCODER MATH NO DEVOLVIÓ FEATURES.',
        );
      }
      return MathFeatureTensor(
        _float32FromList(await features.asFlattenedList()),
        features.shape,
      );
    } finally {
      await input.dispose();
      if (outputs != null) {
        for (final output in outputs.values) {
          await output.dispose();
        }
      }
    }
  }

  Future<List<int>> _generateTokenIds(MathFeatureTensor features) async {
    final session = _decoderSession;
    if (session == null) {
      throw const MathRecognitionException('DECODER MATH NO ESTÁ CARGADO.');
    }

    final tokenIds = <int>[_bosId];
    final maxSteps = math.min(_maxSeqLen, 160);
    for (var step = 0; step < maxSteps; step++) {
      final tokenValues = Int64List.fromList(tokenIds);
      final tokensInput = await OrtValue.fromList(tokenValues, [
        1,
        tokenIds.length,
      ]);
      final featuresInput = await OrtValue.fromList(
        features.values,
        features.shape,
      );
      Map<String, OrtValue>? outputs;
      try {
        outputs = await session.run({
          'tokens': tokensInput,
          'features': featuresInput,
        });
        final logitsValue = outputs['logits'];
        if (logitsValue == null) {
          throw const MathRecognitionException(
            'DECODER MATH NO DEVOLVIÓ LOGITS.',
          );
        }
        final logits = await logitsValue.asFlattenedList();
        final nextToken = _argmaxValid(logits);
        if (nextToken == _eosId) break;
        tokenIds.add(nextToken);
      } finally {
        await tokensInput.dispose();
        await featuresInput.dispose();
        if (outputs != null) {
          for (final output in outputs.values) {
            await output.dispose();
          }
        }
      }
    }
    return tokenIds.skip(1).toList();
  }

  int _argmaxValid(List<dynamic> logits) {
    final limit = math.min(_validVocabSize, logits.length);
    var bestId = 0;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < limit; i++) {
      final score = (logits[i] as num).toDouble();
      if (score > bestScore) {
        bestScore = score;
        bestId = i;
      }
    }
    return bestId;
  }

  String _decodeTokenIds(List<int> tokenIds) {
    final vocab = _vocab;
    if (vocab == null) return '';
    final buffer = StringBuffer();
    for (final tokenId in tokenIds) {
      final token = vocab[tokenId];
      if (token == null ||
          token == '[PAD]' ||
          token == '[BOS]' ||
          token == '[EOS]') {
        continue;
      }
      buffer.write(token);
    }
    return buffer.toString();
  }
}

MathInputTensor renderMathInputTensor(List<List<Offset>> strokes) {
  final points = strokes.expand((stroke) => stroke).toList();
  if (points.isEmpty) {
    throw const MathRecognitionException('NO HAY TRAZOS PARA RECONOCER.');
  }

  var left = points.first.dx;
  var right = points.first.dx;
  var top = points.first.dy;
  var bottom = points.first.dy;
  for (final point in points) {
    left = math.min(left, point.dx);
    right = math.max(right, point.dx);
    top = math.min(top, point.dy);
    bottom = math.max(bottom, point.dy);
  }

  const maxW = 672;
  const minW = 32;
  const snap = 16;
  const targetH = 128;
  const padding = 10.0;
  const strokeWidth = 2.0;

  final sourceW = math.max(1.0, right - left);
  final sourceH = math.max(1.0, bottom - top);
  var scale = (targetH - padding * 2) / sourceH;
  if (sourceW * scale + padding * 2 > maxW) {
    scale = (maxW - padding * 2) / sourceW;
  }

  final drawnW = sourceW * scale;
  final drawnH = sourceH * scale;
  final snappedW = (((drawnW + padding * 2).ceil() + snap - 1) ~/ snap) * snap;
  final targetW = math.max(minW, math.min(maxW, snappedW));
  final offsetX = (targetW - drawnW) / 2 - left * scale;
  final offsetY = (targetH - drawnH) / 2 - top * scale;

  final values = Float32List(targetW * targetH);
  for (var i = 0; i < values.length; i++) {
    values[i] = _normalizePixel(1.0);
  }

  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    if (stroke.length == 1) {
      final point = stroke.first;
      _drawDot(
        values,
        targetW,
        targetH,
        point.dx * scale + offsetX,
        point.dy * scale + offsetY,
        strokeWidth,
      );
      continue;
    }
    for (var i = 1; i < stroke.length; i++) {
      final a = stroke[i - 1];
      final b = stroke[i];
      _drawLine(
        values,
        targetW,
        targetH,
        a.dx * scale + offsetX,
        a.dy * scale + offsetY,
        b.dx * scale + offsetX,
        b.dy * scale + offsetY,
        strokeWidth,
      );
    }
  }

  return MathInputTensor(values, [1, 1, targetH, targetW]);
}

Float32List _float32FromList(List<dynamic> values) {
  final result = Float32List(values.length);
  for (var i = 0; i < values.length; i++) {
    result[i] = (values[i] as num).toDouble();
  }
  return result;
}

String _postProcessLatex(String latex) {
  var value =
      latex
          .replaceAll('[EOS]', '')
          .replaceAll('[BOS]', '')
          .replaceAll('[PAD]', '')
          .replaceAll('Ġ', ' ')
          .replaceAll('Ä ', ' ')
          .replaceAll('Â', '')
          .replaceAll('\\left', '')
          .replaceAll('\\right', '')
          .replaceAll('{\\mbox{', '{')
          .trim();
  value = value.replaceAll(RegExp(r'\s+'), ' ');
  value = value.replaceAll(RegExp(r'\s*([{}_^=+\-*/(),])\s*'), r'$1');
  value = value.replaceAll(RegExp(r'\\\s+'), r'\');
  return value.trim();
}

void _drawLine(
  Float32List values,
  int width,
  int height,
  double x0,
  double y0,
  double x1,
  double y1,
  double strokeWidth,
) {
  final steps =
      math.max((x1 - x0).abs(), (y1 - y0).abs()).ceil().clamp(1, 10000).toInt();
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    _drawDot(
      values,
      width,
      height,
      x0 + (x1 - x0) * t,
      y0 + (y1 - y0) * t,
      strokeWidth,
    );
  }
}

void _drawDot(
  Float32List values,
  int width,
  int height,
  double cx,
  double cy,
  double radius,
) {
  final minX = (cx - radius).floor().clamp(0, width - 1).toInt();
  final maxX = (cx + radius).ceil().clamp(0, width - 1).toInt();
  final minY = (cy - radius).floor().clamp(0, height - 1).toInt();
  final maxY = (cy + radius).ceil().clamp(0, height - 1).toInt();
  final r2 = radius * radius;
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= r2) {
        values[y * width + x] = _normalizePixel(0.0);
      }
    }
  }
}

double _normalizePixel(double value) => (value - 0.7931) / 0.1738;
