import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/services/math_ocr_service.dart';
import 'mathpix_key_store.dart';

class MathpixOcrService implements MathOcrService {
  final MathpixKeyStore keyStore;
  final http.Client _client;

  MathpixOcrService(this.keyStore, {http.Client? client})
      : _client = client ?? http.Client();

  static const _endpoint = 'https://api.mathpix.com/v3/text';

  @override
  Future<String> recognizeImageDataUri(String dataUri) async {
    final appId = (await keyStore.readAppId())?.trim();
    final appKey = (await keyStore.readAppKey())?.trim();
    if (appId == null || appId.isEmpty || appKey == null || appKey.isEmpty) {
      throw const MathOcrException('FALTA CONFIGURAR MATHPIX EN AJUSTES.');
    }

    http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_endpoint),
        headers: {
          'app_id': appId,
          'app_key': appKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'src': dataUri,
          'formats': ['text', 'latex_styled'],
          'math_inline_delimiters': [r'$', r'$'],
          'math_display_delimiters': [r'$$', r'$$'],
          'rm_spaces': true,
        }),
      );
    } catch (_) {
      throw const MathOcrException('SIN CONEXIÓN O ERROR DE RED.');
    }

    if (response.statusCode != 200) {
      throw MathOcrException(_friendlyError(response.statusCode));
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const MathOcrException('RESPUESTA INVÁLIDA DE MATHPIX.');
    }
    final apiError = body['error'];
    if (apiError is String && apiError.trim().isNotEmpty) {
      throw MathOcrException(apiError);
    }
    final latex = (body['latex_styled'] as String?)?.trim();
    if (latex != null && latex.isNotEmpty) return latex;
    final text = (body['text'] as String?)?.trim();
    if (text != null && text.isNotEmpty) return _stripMathDelimiters(text);
    throw const MathOcrException('NO SE RECONOCIÓ UNA FÓRMULA.');
  }

  String _stripMathDelimiters(String value) {
    var s = value.trim();
    if (s.startsWith(r'\(') && s.endsWith(r'\)')) {
      s = s.substring(2, s.length - 2).trim();
    }
    if (s.startsWith(r'\[') && s.endsWith(r'\]')) {
      s = s.substring(2, s.length - 2).trim();
    }
    if (s.startsWith(r'$$') && s.endsWith(r'$$')) {
      s = s.substring(2, s.length - 2).trim();
    }
    if (s.startsWith(r'$') && s.endsWith(r'$')) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  String _friendlyError(int code) => switch (code) {
        401 => 'CREDENCIALES MATHPIX INVÁLIDAS.',
        403 => 'MATHPIX RECHAZÓ LA SOLICITUD.',
        429 => 'LÍMITE DE MATHPIX ALCANZADO.',
        _ => 'ERROR DE MATHPIX ($code).',
      };
}
