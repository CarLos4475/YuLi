import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'backup_bundle.dart';

class StudyUploadEntry {
  final String token;
  final String account;
  final String key;
  final String folderKey;
  final String folderName;
  final String name;
  final String hash;
  final DateTime createdAt;
  final File file;

  const StudyUploadEntry({
    required this.token,
    required this.account,
    required this.key,
    required this.folderKey,
    required this.folderName,
    required this.name,
    required this.hash,
    required this.createdAt,
    required this.file,
  });
}

class StudyUploadQueue {
  static const _uploadedPrefix = 'study_uploaded_v2_';
  final Directory documents;
  final SharedPreferences preferences;

  const StudyUploadQueue(this.documents, this.preferences);

  Directory get _root =>
      Directory(p.join(documents.path, 'study_exports', 'ready'));

  String _uploadedKey(String account) => '$_uploadedPrefix$account';

  Map<String, dynamic> _uploaded(String account) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(preferences.getString(_uploadedKey(account)) ?? '{}') as Map,
      );
    } catch (_) {
      return {};
    }
  }

  Future<bool> contains(String account, String key, String hash) async {
    if (_uploaded(account)[key] == hash) return true;
    for (final entry in await pending(account: account)) {
      if (entry.key == key && entry.hash == hash) return true;
    }
    return false;
  }

  Future<Set<String>> knownVersions(String account) async {
    final result = <String>{
      for (final entry in _uploaded(account).entries)
        if (entry.value is String) '${entry.key}\u0000${entry.value}',
    };
    for (final entry in await pending(account: account)) {
      result.add('${entry.key}\u0000${entry.hash}');
    }
    return result;
  }

  Future<StudyUploadEntry> add({
    required String account,
    required String key,
    required String folderKey,
    required String folderName,
    required String name,
    required String hash,
    required File rendered,
  }) async {
    _validateText(account, 256);
    _validateKey(key);
    _validateKey(folderKey);
    _validateText(folderName, 512);
    _validateText(name, 512);
    _validateHash(hash);
    if (!name.toLowerCase().endsWith('.pdf')) {
      throw const BackupFailure('El apunte preparado no es un PDF.');
    }
    final root = _root;
    await root.create(recursive: true);
    final token = const Uuid().v4();
    final target = File(p.join(root.path, '$token.pdf'));
    final descriptor = File(p.join(root.path, '$token.json'));
    final temporary = File(p.join(root.path, '$token.json.tmp'));
    try {
      await rendered.rename(target.path);
    } on FileSystemException {
      await rendered.copy(target.path);
      await rendered.delete();
    }
    final data = {
      'version': 1,
      'token': token,
      'account': account,
      'key': key,
      'folderKey': folderKey,
      'folderName': folderName,
      'name': name,
      'hash': hash,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await temporary.writeAsString(jsonEncode(data), flush: true);
      await temporary.rename(descriptor.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await target.exists()) await target.delete();
      rethrow;
    }
    final entry = (await _read(descriptor))!;
    for (final older in await pending(account: account)) {
      if (older.key == key && older.token != token) await _delete(older);
    }
    return entry;
  }

  Future<List<StudyUploadEntry>> pending({String? account}) async {
    final root = _root;
    if (!await root.exists()) return [];
    final result = <StudyUploadEntry>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final entry = await _read(entity);
        if (entry == null) {
          await _deleteIfExists(entity);
        } else if (account == null || entry.account == account) {
          result.add(entry);
        }
      } catch (_) {
        await _deleteIfExists(entity);
      }
    }
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  Future<void> complete(StudyUploadEntry entry) async {
    final uploaded = _uploaded(entry.account)..[entry.key] = entry.hash;
    if (!await preferences.setString(
      _uploadedKey(entry.account),
      jsonEncode(uploaded),
    )) {
      throw const BackupFailure('No se pudo guardar el progreso de los PDF.');
    }
    await _delete(entry);
  }

  Future<void> discardAccount(String account) async {
    for (final entry in await pending(account: account)) {
      await _delete(entry);
    }
    await preferences.remove(_uploadedKey(account));
  }

  Future<void> _delete(StudyUploadEntry entry) async {
    for (final file in [
      File(p.join(_root.path, '${entry.token}.json')),
      entry.file,
    ]) {
      await _deleteIfExists(file);
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      return;
    }
  }

  Future<StudyUploadEntry?> _read(File descriptor) async {
    final data = jsonDecode(await descriptor.readAsString());
    if (data is! Map<String, dynamic> || data['version'] != 1) return null;
    final token = data['token'];
    final account = data['account'];
    final key = data['key'];
    final folderKey = data['folderKey'];
    final folderName = data['folderName'];
    final name = data['name'];
    final hash = data['hash'];
    final createdAt = DateTime.tryParse('${data['createdAt']}');
    if (token is! String ||
        account is! String ||
        key is! String ||
        folderKey is! String ||
        folderName is! String ||
        name is! String ||
        hash is! String ||
        createdAt == null ||
        !RegExp(r'^[0-9a-f-]{36}$').hasMatch(token) ||
        p.basename(descriptor.path) != '$token.json') {
      return null;
    }
    _validateText(account, 256);
    _validateKey(key);
    _validateKey(folderKey);
    _validateText(folderName, 512);
    _validateText(name, 512);
    _validateHash(hash);
    final file = File(p.join(_root.path, '$token.pdf'));
    if (!await file.exists() || await file.length() == 0) return null;
    return StudyUploadEntry(
      token: token,
      account: account,
      key: key,
      folderKey: folderKey,
      folderName: folderName,
      name: name,
      hash: hash,
      createdAt: createdAt,
      file: file,
    );
  }

  static void _validateText(String value, int max) {
    if (value.isEmpty || value.length > max || value.contains('\x00')) {
      throw const BackupFailure('Metadatos de apunte inválidos.');
    }
  }

  static void _validateKey(String value) {
    if (!RegExp(r'^[a-z]+:[0-9]+$').hasMatch(value)) {
      throw const BackupFailure('Identidad de apunte inválida.');
    }
  }

  static void _validateHash(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const BackupFailure('Versión de apunte inválida.');
    }
  }
}
