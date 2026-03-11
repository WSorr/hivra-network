import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../ffi/hivra_bindings.dart';

class CapsuleFileStore {
  static const String stateFileName = 'capsule_state.json';
  static const String ledgerFileName = 'ledger.json';
  static const String backupFileName = 'capsule-backup.v1.json';
  static const String capsulesDirName = 'capsules';

  const CapsuleFileStore();

  Future<Directory> docsDirectory() async {
    return getApplicationDocumentsDirectory();
  }

  Future<Directory> capsulesRoot({bool create = false}) async {
    final docs = await docsDirectory();
    final root = Directory('${docs.path}/$capsulesDirName');
    if (create && !await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<Directory> capsuleDirForHex(
    String pubKeyHex, {
    bool create = false,
  }) async {
    final root = await capsulesRoot(create: create);
    final dir = Directory('${root.path}/$pubKeyHex');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> currentCapsuleDir(
    HivraBindings? hivra, {
    required String Function(Uint8List bytes) bytesToHex,
    bool create = false,
  }) async {
    final docs = await docsDirectory();
    final root = await capsulesRoot(create: create);

    String? capsuleId;
    if (hivra != null) {
      final pubKey = hivra.capsulePublicKey();
      if (pubKey != null && pubKey.length == 32) {
        capsuleId = bytesToHex(pubKey);
      }
    }

    if (capsuleId == null || capsuleId.isEmpty) {
      return docs;
    }

    final dir = Directory('${root.path}/$capsuleId');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File stateFile(Directory dir) => File('${dir.path}/$stateFileName');

  File ledgerFile(Directory dir) => File('${dir.path}/$ledgerFileName');

  File backupFile(Directory dir) => File('${dir.path}/$backupFileName');

  Future<Map<String, dynamic>?> readState(Directory dir) async {
    final file = stateFile(dir);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeState(Directory dir, Map<String, dynamic> state) async {
    await stateFile(dir).writeAsString(jsonEncode(state), flush: true);
  }

  Future<String?> readLedger(Directory dir) async {
    final file = ledgerFile(dir);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return raw.trim().isEmpty ? null : raw;
  }

  Future<void> writeLedger(Directory dir, String ledgerJson) async {
    await ledgerFile(dir).writeAsString(ledgerJson, flush: true);
  }

  Future<String?> readBackup(Directory dir) async {
    final file = backupFile(dir);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    return raw.trim().isEmpty ? null : raw;
  }

  Future<void> writeBackup(Directory dir, String backupJson) async {
    await backupFile(dir).writeAsString(backupJson, flush: true);
  }

  Future<void> clearPersisted(
    Directory dir, {
    bool includeBackup = false,
  }) async {
    final state = stateFile(dir);
    final ledger = ledgerFile(dir);
    final backup = backupFile(dir);
    if (await state.exists()) await state.delete();
    if (await ledger.exists()) await ledger.delete();
    if (includeBackup && await backup.exists()) await backup.delete();
  }

  Future<String> backupPath(Directory dir) async {
    return backupFile(dir).path;
  }

  Future<String> ledgerPath(Directory dir) async {
    return ledgerFile(dir).path;
  }

  Future<void> deleteCapsuleDir(String pubKeyHex) async {
    final dir = await capsuleDirForHex(pubKeyHex);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  File legacyStateFile(Directory docs) => File('${docs.path}/$stateFileName');

  File legacyLedgerFile(Directory docs) => File('${docs.path}/$ledgerFileName');

  File legacyBackupFile(Directory docs) => File('${docs.path}/$backupFileName');
}
