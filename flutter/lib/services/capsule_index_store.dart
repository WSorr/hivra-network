import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'capsule_persistence_models.dart';

class CapsulesIndex {
  String? activePubKeyHex;
  final Map<String, CapsuleIndexEntry> capsules;

  CapsulesIndex({
    required this.activePubKeyHex,
    required this.capsules,
  });
}

class CapsuleIndexStore {
  static const String _capsulesDirName = 'capsules';
  static const String _indexFileName = 'capsules_index.json';

  const CapsuleIndexStore();

  Future<CapsulesIndex> read() async {
    final docs = await getApplicationDocumentsDirectory();
    final capsulesRoot = Directory('${docs.path}/$_capsulesDirName');
    final indexFile = File('${capsulesRoot.path}/$_indexFileName');
    if (!await indexFile.exists()) {
      return CapsulesIndex(activePubKeyHex: null, capsules: {});
    }

    try {
      final raw = await indexFile.readAsString();
      return _fromJson(raw);
    } catch (_) {
      return CapsulesIndex(activePubKeyHex: null, capsules: {});
    }
  }

  Future<void> write(CapsulesIndex index) async {
    final docs = await getApplicationDocumentsDirectory();
    final capsulesRoot = Directory('${docs.path}/$_capsulesDirName');
    if (!await capsulesRoot.exists()) {
      await capsulesRoot.create(recursive: true);
    }
    final indexFile = File('${capsulesRoot.path}/$_indexFileName');
    await indexFile.writeAsString(_toJson(index), flush: true);
  }

  Future<void> setActive(String pubKeyHex) async {
    final index = await read();
    index.activePubKeyHex = pubKeyHex;
    await write(index);
  }

  Future<void> upsert(
    String pubKeyHex, {
    bool? isGenesis,
    bool? isNeste,
  }) async {
    final index = await read();
    final now = DateTime.now().toUtc();
    final existing = index.capsules[pubKeyHex];
    index.capsules[pubKeyHex] = CapsuleIndexEntry(
      pubKeyHex: pubKeyHex,
      createdAt: existing?.createdAt ?? now,
      lastActive: now,
      isGenesis: isGenesis ?? existing?.isGenesis ?? false,
      isNeste: isNeste ?? existing?.isNeste ?? true,
    );
    await write(index);
  }

  CapsulesIndex _fromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return CapsulesIndex(activePubKeyHex: null, capsules: {});
    final map = Map<String, dynamic>.from(decoded);
    final active = map['active']?.toString();
    final capsulesMap = <String, CapsuleIndexEntry>{};
    final list = map['capsules'];
    if (list is Map) {
      final items = Map<String, dynamic>.from(list);
      for (final entry in items.entries) {
        if (entry.value is Map) {
          capsulesMap[entry.key] =
              CapsuleIndexEntry.fromMap(Map<String, dynamic>.from(entry.value));
        }
      }
    }
    return CapsulesIndex(activePubKeyHex: active, capsules: capsulesMap);
  }

  String _toJson(CapsulesIndex index) {
    final capsulesJson = <String, dynamic>{};
    for (final entry in index.capsules.entries) {
      capsulesJson[entry.key] = entry.value.toMap();
    }
    return jsonEncode({
      'active': index.activePubKeyHex,
      'capsules': capsulesJson,
    });
  }
}
