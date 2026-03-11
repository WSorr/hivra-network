import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class CapsuleSeedStore {
  static const String _capsulesDirName = 'capsules';
  static const String _seedKeyPrefix = 'hivra.seed.';
  static const String _seedFallbackFileName = 'capsule_seeds.json';

  final FlutterSecureStorage _secureStorage;

  const CapsuleSeedStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<void> storeSeed(String pubKeyHex, Uint8List seed) async {
    final encoded = base64.encode(seed);
    final key = '$_seedKeyPrefix$pubKeyHex';
    try {
      await _secureStorage.write(key: key, value: encoded);
      await deleteFallback(pubKeyHex);
    } catch (_) {
      await _writeSeedFallback(pubKeyHex, encoded);
    }
  }

  Future<String?> readSecureEncoded(String pubKeyHex) async {
    final key = '$_seedKeyPrefix$pubKeyHex';
    try {
      return _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> loadSeed(String pubKeyHex) async {
    var encoded = await readSecureEncoded(pubKeyHex);
    encoded ??= await _readSeedFallback(pubKeyHex);
    return _decodeSeedString(encoded);
  }

  Future<bool> hasStoredSeed(String pubKeyHex) async {
    var encoded = await readSecureEncoded(pubKeyHex);
    encoded ??= await _readSeedFallback(pubKeyHex);
    return _decodeSeedString(encoded) != null;
  }

  Future<void> deleteSeed(String pubKeyHex) async {
    try {
      await _secureStorage.delete(key: '$_seedKeyPrefix$pubKeyHex');
    } catch (_) {
      // Ignore secure storage cleanup errors.
    }
    await deleteFallback(pubKeyHex);
  }

  Future<void> deleteFallback(String pubKeyHex) async {
    final file = await _seedFallbackFile();
    if (!await file.exists()) return;

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      map.remove(pubKeyHex);
      await file.writeAsString(jsonEncode(map), flush: true);
    } catch (_) {
      // Ignore fallback cleanup errors.
    }
  }

  Future<Uint8List?> loadValidatedSeed(
    String pubKeyHex, {
    required Future<bool> Function(Uint8List seed) isValidSeed,
    required Future<void> Function(Uint8List seed) persistValidatedSeed,
  }) async {
    final secureSeed = _decodeSeedString(await readSecureEncoded(pubKeyHex));
    if (secureSeed != null && await isValidSeed(secureSeed)) {
      await deleteFallback(pubKeyHex);
      return secureSeed;
    }

    final fallbackSeed = _decodeSeedString(await _readSeedFallback(pubKeyHex));
    if (fallbackSeed != null && await isValidSeed(fallbackSeed)) {
      await persistValidatedSeed(fallbackSeed);
      return fallbackSeed;
    }

    return null;
  }

  Future<File> _seedFallbackFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final capsulesRoot = Directory('${docs.path}/$_capsulesDirName');
    if (!await capsulesRoot.exists()) {
      await capsulesRoot.create(recursive: true);
    }
    return File('${capsulesRoot.path}/$_seedFallbackFileName');
  }

  Future<void> _writeSeedFallback(String pubKeyHex, String encodedSeed) async {
    final file = await _seedFallbackFile();
    Map<String, dynamic> map = {};
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            map = Map<String, dynamic>.from(decoded);
          }
        }
      } catch (_) {
        map = {};
      }
    }

    map[pubKeyHex] = encodedSeed;
    await file.writeAsString(jsonEncode(map), flush: true);
  }

  Future<String?> _readSeedFallback(String pubKeyHex) async {
    final file = await _seedFallbackFile();
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      return map[pubKeyHex]?.toString();
    } catch (_) {
      return null;
    }
  }

  Uint8List? _decodeSeedString(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = base64.decode(encoded);
      if (bytes.length != 32) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }
}
