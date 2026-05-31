import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Optional Jina Reader API key (higher rate limits). Stored OS-secure like the
/// DeepSeek key; never logged or displayed back. The reader works without it
/// (free tier, rate-limited).
class JinaKeyStore {
  static const _key = 'jina_api_key_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String value) =>
      _storage.write(key: _key, value: value.trim());
  Future<void> clear() => _storage.delete(key: _key);
  Future<bool> hasKey() async => ((await read())?.trim().isNotEmpty) ?? false;
}

class WebReaderException implements Exception {
  final String message;
  const WebReaderException(this.message);
  @override
  String toString() => message;
}

/// Fetched web document: a [title] (page metadata) and the clean [content]
/// (markdown body, metadata header stripped).
class WebDoc {
  final String title;
  final String content;
  const WebDoc({required this.title, required this.content});
}

/// Reads a URL as clean markdown via Jina Reader (`https://r.jina.ai/<url>`).
/// Jina prepends a `Title:` / `URL Source:` / `Markdown Content:` header which
/// we parse for the page title and strip from the body.
class WebReader {
  final JinaKeyStore keyStore;
  final http.Client _client;

  WebReader(this.keyStore, {http.Client? client})
      : _client = client ?? http.Client();

  static const _base = 'https://r.jina.ai/';

  Future<WebDoc> fetch(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) throw const WebReaderException('URL vacía.');
    final normalized =
        clean.startsWith('http://') || clean.startsWith('https://')
            ? clean
            : 'https://$clean';

    final key = (await keyStore.read())?.trim();
    http.Response res;
    try {
      res = await _client.get(
        Uri.parse('$_base$normalized'),
        headers: {
          'Accept': 'text/plain',
          if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key',
        },
      ).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw const WebReaderException(
          'No se pudo leer la página (¿sin conexión?).');
    }
    if (res.statusCode == 429) {
      throw const WebReaderException(
          'Límite de Jina alcanzado. Agrega una API key en Ajustes o intenta luego.');
    }
    if (res.statusCode != 200) {
      throw WebReaderException('Jina devolvió ${res.statusCode}.');
    }
    return _parse(res.body, normalized);
  }

  WebDoc _parse(String body, String url) {
    String title = '';
    var content = body;
    // Jina header: "Title: ...\nURL Source: ...\nMarkdown Content:\n<body>".
    final marker = body.indexOf('Markdown Content:');
    if (marker >= 0) {
      final header = body.substring(0, marker);
      final tm = RegExp(r'^Title:\s*(.+)$', multiLine: true).firstMatch(header);
      if (tm != null) title = tm.group(1)!.trim();
      content = body.substring(marker + 'Markdown Content:'.length).trim();
    }
    if (title.isEmpty) {
      // Fallback: host + path as a readable label.
      final u = Uri.tryParse(url);
      title = u != null ? '${u.host}${u.path}' : url;
    }
    return WebDoc(title: title, content: content.trim());
  }
}
