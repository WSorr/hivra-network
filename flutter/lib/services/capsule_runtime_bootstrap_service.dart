import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import 'capsule_backup_codec.dart';
import 'capsule_file_store.dart';
import 'capsule_persistence_models.dart';
import 'capsule_seed_store.dart';

class CapsuleRuntimeBootstrapService {
  final CapsuleFileStore _fileStore;
  final CapsuleSeedStore _seedStore;

  const CapsuleRuntimeBootstrapService(this._fileStore, this._seedStore);

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrap(
    String pubKeyHex, {
    HivraBindings? hivra,
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final seed = hivra == null
        ? await _seedStore.loadSeed(pubKeyHex)
        : await _seedStore.loadValidatedSeed(
            pubKeyHex,
            isValidSeed: (seed) =>
                _seedMatchesCapsule(hivra, seed, pubKeyHex, bytesToHex),
            persistValidatedSeed: (seed) => _seedStore.storeSeed(pubKeyHex, seed),
          );
    if (seed == null) return null;

    final dir = await _fileStore.capsuleDirForHex(pubKeyHex, create: true);
    final state = await _fileStore.readState(dir);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;

    String? ledgerJson = await _fileStore.readLedger(dir);
    if (ledgerJson == null) {
      final backupJson = await _fileStore.readBackup(dir);
      if (backupJson != null) {
        final extracted = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
        if (extracted != null && extracted.trim().isNotEmpty) {
          ledgerJson = extracted;
        }
      }
    }

    return CapsuleRuntimeBootstrap(
      pubKeyHex: pubKeyHex,
      seed: seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      ledgerJson: ledgerJson,
    );
  }

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrapForCurrent(
    HivraBindings hivra, {
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final pubKey = hivra.capsulePublicKey();
    final seed = hivra.loadSeed();
    if (pubKey == null || pubKey.length != 32 || seed == null) return null;

    final dir = await _fileStore.currentCapsuleDir(
      hivra,
      bytesToHex: bytesToHex,
      create: false,
    );
    final state = await _fileStore.readState(dir);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;
    final ledgerJson = hivra.exportLedger();

    return CapsuleRuntimeBootstrap(
      pubKeyHex: bytesToHex(pubKey),
      seed: seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      ledgerJson:
          (ledgerJson != null && ledgerJson.isNotEmpty) ? ledgerJson : null,
    );
  }

  Future<bool> refreshCapsuleSnapshot(
    HivraBindings hivra,
    String pubKeyHex, {
    required String Function(Uint8List bytes) bytesToHex,
  }) async {
    final seed = await _seedStore.loadValidatedSeed(
      pubKeyHex,
      isValidSeed: (seed) => _seedMatchesCapsule(hivra, seed, pubKeyHex, bytesToHex),
      persistValidatedSeed: (seed) => _seedStore.storeSeed(pubKeyHex, seed),
    );
    if (seed == null) return false;
    if (!hivra.saveSeed(seed)) return false;

    final dir = await _fileStore.capsuleDirForHex(pubKeyHex, create: true);
    final state = await _fileStore.readState(dir);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;
    if (!hivra.createCapsule(seed, isGenesis: isGenesis, isNeste: isNeste)) {
      return false;
    }

    final ledgerJson = await _fileStore.readLedger(dir);
    if (ledgerJson != null) {
      hivra.importLedger(ledgerJson);
    } else {
      final backupJson = await _fileStore.readBackup(dir);
      if (backupJson != null) {
        final extracted = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
        if (extracted != null && extracted.trim().isNotEmpty) {
          hivra.importLedger(extracted);
        }
      }
    }

    final exported = hivra.exportLedger();
    if (exported == null || exported.isEmpty) return false;
    await _fileStore.writeLedger(dir, exported);
    return true;
  }

  Future<bool> _seedMatchesCapsule(
    HivraBindings hivra,
    Uint8List seed,
    String pubKeyHex,
    String Function(Uint8List bytes) bytesToHex,
  ) async {
    if (!hivra.saveSeed(seed)) return false;
    if (!hivra.createCapsule(seed)) return false;
    final derivedPubKey = hivra.capsulePublicKey();
    if (derivedPubKey == null || derivedPubKey.length != 32) return false;
    return bytesToHex(derivedPubKey) == pubKeyHex;
  }
}
