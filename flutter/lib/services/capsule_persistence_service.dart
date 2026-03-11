import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import 'capsule_backup_codec.dart';
import 'capsule_file_store.dart';
import 'capsule_index_store.dart';
import 'capsule_ledger_summary_parser.dart';
import 'capsule_persistence_models.dart';
import 'capsule_runtime_bootstrap_service.dart';
import 'capsule_seed_store.dart';

class CapsulePersistenceService {
  static final CapsulePersistenceService _instance =
      CapsulePersistenceService._internal();

  factory CapsulePersistenceService() => _instance;

  CapsulePersistenceService._internal() {
    _runtimeBootstrapService =
        CapsuleRuntimeBootstrapService(_fileStore, _seedStore);
  }

  final CapsuleFileStore _fileStore = const CapsuleFileStore();
  final CapsuleIndexStore _indexStore = const CapsuleIndexStore();
  final CapsuleLedgerSummaryParser _summaryParser =
      const CapsuleLedgerSummaryParser();
  final CapsuleSeedStore _seedStore = const CapsuleSeedStore();
  late final CapsuleRuntimeBootstrapService _runtimeBootstrapService;

  Future<void> persistAfterCreate({
    required HivraBindings hivra,
    required Uint8List seed,
    required bool isGenesis,
    required bool isNeste,
  }) async {
    final pubKey = hivra.capsulePublicKey();
    final pubKeyHex = pubKey != null ? _bytesToHex(pubKey) : null;
    final dir = await _currentCapsuleDir(hivra, create: true);

    final state = <String, dynamic>{
      'isGenesis': isGenesis,
      'isNeste': isNeste,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'seedLength': seed.length,
    };
    await _fileStore.writeState(dir, state);

    final ledger = hivra.exportLedger();
    if (ledger != null && ledger.isNotEmpty) {
      await _fileStore.writeLedger(dir, ledger);

      final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: ledger,
        isGenesis: isGenesis,
        isNeste: isNeste,
      );
      await _fileStore.writeBackup(dir, backupJson);
    }

    if (pubKeyHex != null) {
      await _storeSeedForCapsule(pubKeyHex, seed);
      await _upsertCapsuleIndex(
        pubKeyHex,
        isGenesis: isGenesis,
        isNeste: isNeste,
      );
      await _setActiveCapsule(pubKeyHex);
    }
  }

  Future<bool> bootstrapRuntimeFromDisk(HivraBindings hivra) async {
    final seed = hivra.loadSeed();
    if (seed == null) return false;

    final state = await _readStateForCurrentCapsule(hivra);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;

    if (!hivra.createCapsule(seed, isGenesis: isGenesis, isNeste: isNeste)) {
      return false;
    }

    await importLedgerIfExists(hivra);
    return true;
  }

  Future<bool> importLedgerIfExists(HivraBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra);
    final ledgerJson = await _fileStore.readLedger(dir);
    if (ledgerJson != null && hivra.importLedger(ledgerJson)) {
      await _touchActiveCapsule(hivra);
      return true;
    }
    return importBackupEnvelopeIfExists(hivra);
  }

  Future<bool> persistLedgerSnapshot(HivraBindings hivra) async {
    final ledger = hivra.exportLedger();
    if (ledger == null || ledger.isEmpty) return false;

    final dir = await _currentCapsuleDir(hivra, create: true);
    await _fileStore.writeLedger(dir, ledger);
    await _touchActiveCapsule(hivra);
    return true;
  }

  Future<String?> exportBackupEnvelope(HivraBindings hivra) async {
    final ledger = hivra.exportLedger();
    if (ledger == null || ledger.isEmpty) return null;

    final state = await _readStateForCurrentCapsule(hivra);
    final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
      ledgerJson: ledger,
      isGenesis: state?['isGenesis'] == true,
      isNeste: state?['isNeste'] != false,
    );

    final dir = await _currentCapsuleDir(hivra, create: true);
    await _fileStore.writeBackup(dir, backupJson);
    await _touchActiveCapsule(hivra);
    return _fileStore.backupPath(dir);
  }

  Future<bool> importBackupEnvelopeIfExists(HivraBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra);
    final backupJson = await _fileStore.readBackup(dir);
    if (backupJson == null) return false;
    final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
    if (ledgerJson == null) return false;
    final imported = hivra.importLedger(ledgerJson);
    if (imported) {
      await _touchActiveCapsule(hivra);
    }
    return imported;
  }

  Future<void> clearPersistedData(HivraBindings hivra,
      {bool includeBackup = false}) async {
    final dir = await _currentCapsuleDir(hivra);
    await _fileStore.clearPersisted(dir, includeBackup: includeBackup);
  }

  Future<String?> resolveActiveCapsuleHex(HivraBindings hivra) async {
    final index = await _readIndex();
    if (index.activePubKeyHex != null && index.activePubKeyHex!.isNotEmpty) {
      return index.activePubKeyHex;
    }

    final pubKey = hivra.capsulePublicKey();
    if (pubKey != null && pubKey.length == 32) {
      return _bytesToHex(pubKey);
    }
    return null;
  }

  Future<bool> bootstrapActiveCapsuleRuntime(HivraBindings hivra) async {
    final activeHex = await resolveActiveCapsuleHex(hivra);
    if (activeHex == null || activeHex.isEmpty) {
      return bootstrapRuntimeFromDisk(hivra);
    }

    final bootstrap = await loadRuntimeBootstrap(activeHex, hivra: hivra);
    if (bootstrap == null) return false;

    if (!hivra.saveSeed(bootstrap.seed)) return false;
    if (!hivra.createCapsule(
      bootstrap.seed,
      isGenesis: bootstrap.isGenesis,
      isNeste: bootstrap.isNeste,
    )) {
      return false;
    }

    if (bootstrap.ledgerJson != null &&
        bootstrap.ledgerJson!.isNotEmpty &&
        !hivra.importLedger(bootstrap.ledgerJson!)) {
      return false;
    }

    await _setActiveCapsule(activeHex);
    return true;
  }

  Future<String?> diagnoseActiveCapsuleBootstrap(HivraBindings hivra) async {
    final activeHex = await resolveActiveCapsuleHex(hivra);
    if (activeHex == null || activeHex.isEmpty) {
      return 'No active capsule selected';
    }

    final bootstrap = await loadRuntimeBootstrap(activeHex, hivra: hivra);
    if (bootstrap == null) {
      return 'No bootstrap data for capsule $activeHex';
    }

    if (!hivra.saveSeed(bootstrap.seed)) {
      return 'Failed to save seed for capsule $activeHex';
    }

    if (!hivra.createCapsule(
      bootstrap.seed,
      isGenesis: bootstrap.isGenesis,
      isNeste: bootstrap.isNeste,
    )) {
      return 'Failed to create runtime capsule for $activeHex';
    }

    final runtimePubKey = hivra.capsulePublicKey();
    final runtimeHex = runtimePubKey != null && runtimePubKey.length == 32
        ? _bytesToHex(runtimePubKey)
        : null;
    if (runtimeHex != activeHex) {
      return 'Seed/pubkey mismatch: expected $activeHex, got ${runtimeHex ?? 'none'}';
    }

    final ledgerJson = bootstrap.ledgerJson;
    if (ledgerJson != null &&
        ledgerJson.isNotEmpty &&
        !hivra.importLedger(ledgerJson)) {
      return 'Failed to import ledger for capsule $activeHex';
    }

    return null;
  }

  Future<void> deleteActiveCapsule(HivraBindings hivra) async {
    final pubKeyHex = await resolveActiveCapsuleHex(hivra);
    if (pubKeyHex == null || pubKeyHex.isEmpty) return;
    await deleteCapsule(pubKeyHex, deleteLocalData: true);
  }

  Future<String> getCurrentBackupPath(HivraBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra, create: true);
    return _fileStore.backupPath(dir);
  }

  Future<String> getCurrentLedgerPath(HivraBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra, create: true);
    return _fileStore.ledgerPath(dir);
  }

  Future<List<CapsuleIndexEntry>> listCapsules({HivraBindings? hivra}) async {
    if (hivra != null) {
      await _ensureIndexFromCurrentSeed(hivra);
    }
    final index = await _readIndex();
    final entries = <CapsuleIndexEntry>[];
    for (final entry in index.capsules.values) {
      entries.add(entry);
    }
    entries.sort((a, b) => b.lastActive.compareTo(a.lastActive));
    return entries;
  }

  Future<CapsuleLedgerSummary> loadCapsuleSummary(String pubKeyHex) async {
    final capsuleDir = await _capsuleDirForHex(pubKeyHex);
    final raw = await _fileStore.readLedger(capsuleDir);
    if (raw == null) {
      return CapsuleLedgerSummary.empty();
    }
    try {
      return _summaryParser.parse(raw, _bytesToHex);
    } catch (_) {
      return CapsuleLedgerSummary.empty();
    }
  }

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrap(
    String pubKeyHex, {
    HivraBindings? hivra,
  }) async {
    return _runtimeBootstrapService.loadRuntimeBootstrap(
      pubKeyHex,
      hivra: hivra,
      bytesToHex: _bytesToHex,
    );
  }

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrapForCurrent(
      HivraBindings hivra) async {
    return _runtimeBootstrapService.loadRuntimeBootstrapForCurrent(
      hivra,
      bytesToHex: _bytesToHex,
    );
  }

  Future<Map<String, Object?>?> loadWorkerBootstrapArgs(
      HivraBindings hivra) async {
    final activeHex = await resolveActiveCapsuleHex(hivra);
    CapsuleRuntimeBootstrap? bootstrap;
    if (activeHex != null && activeHex.isNotEmpty) {
      bootstrap = await loadRuntimeBootstrap(activeHex);
    }
    bootstrap ??= await loadRuntimeBootstrapForCurrent(hivra);
    if (bootstrap == null) return null;

    return <String, Object?>{
      'seed': bootstrap.seed,
      'isGenesis': bootstrap.isGenesis,
      'isNeste': bootstrap.isNeste,
      'ledgerJson': bootstrap.ledgerJson,
    };
  }

  Future<String?> exportCapsuleBackupToPath(
      String pubKeyHex, String targetPath) async {
    final capsuleDir = await _capsuleDirForHex(pubKeyHex);
    final ledgerJson = await _fileStore.readLedger(capsuleDir);
    if (ledgerJson == null) return null;

    final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
      ledgerJson: ledgerJson,
    );
    final outFile = File(targetPath);
    await outFile.writeAsString(backupJson, flush: true);
    return outFile.path;
  }

  Future<bool> refreshCapsuleSnapshot(
      HivraBindings hivra, String pubKeyHex) async {
    return _runtimeBootstrapService.refreshCapsuleSnapshot(
      hivra,
      pubKeyHex,
      bytesToHex: _bytesToHex,
    );
  }

  Future<String?> importCapsuleFromBackupJson(String rawJson) async {
    final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(rawJson);
    if (ledgerJson == null) return null;

    final ownerHex = _extractOwnerHex(ledgerJson);
    if (ownerHex == null) return null;

    final capsuleDir = await _capsuleDirForHex(ownerHex, create: true);
    await _fileStore.writeLedger(capsuleDir, ledgerJson);
    await _fileStore.writeBackup(capsuleDir, rawJson);

    final meta = _extractBackupMeta(rawJson);
    await _upsertCapsuleIndex(
      ownerHex,
      isGenesis: meta?.isGenesis,
      isNeste: meta?.isNeste,
    );
    await _setActiveCapsule(ownerHex);
    return ownerHex;
  }

  Future<void> deleteCapsule(String pubKeyHex,
      {bool deleteLocalData = false}) async {
    if (deleteLocalData) {
      await _fileStore.deleteCapsuleDir(pubKeyHex);
    }
    await _seedStore.deleteSeed(pubKeyHex);
    final index = await _readIndex();
    index.capsules.remove(pubKeyHex);
    if (index.activePubKeyHex == pubKeyHex) {
      index.activePubKeyHex = null;
    }
    await _writeIndex(index);
  }

  Future<bool> hasStoredSeed(String pubKeyHex) async {
    return _seedStore.hasStoredSeed(pubKeyHex);
  }

  Future<bool> seedMatchesCapsule(
    HivraBindings hivra,
    Uint8List seed,
    String pubKeyHex,
  ) async {
    if (!hivra.saveSeed(seed)) return false;
    if (!hivra.createCapsule(seed)) return false;
    final derivedPubKey = hivra.capsulePublicKey();
    if (derivedPubKey == null || derivedPubKey.length != 32) return false;
    return _bytesToHex(derivedPubKey) == pubKeyHex;
  }

  Future<void> saveSeedForCapsule(String pubKeyHex, Uint8List seed) async {
    await _storeSeedForCapsule(pubKeyHex, seed);
  }

  Future<void> activateCapsule(HivraBindings hivra, String pubKeyHex) async {
    final storedSeed = await _loadSeedForCapsule(pubKeyHex);
    if (storedSeed != null) {
      if (!hivra.saveSeed(storedSeed)) {
        throw Exception('Failed to save seed into runtime');
      }
    } else {
      // Fallback: if current keychain seed matches target pubkey, keep it.
      final currentPubKey = hivra.capsulePublicKey();
      final currentHex = currentPubKey != null && currentPubKey.length == 32
          ? _bytesToHex(currentPubKey)
          : null;
      if (currentHex != pubKeyHex) {
        throw Exception('Seed not found for capsule');
      }
      final currentSeed = hivra.loadSeed();
      if (currentSeed != null) {
        await _storeSeedForCapsule(pubKeyHex, currentSeed);
      }
    }
    await _setActiveCapsule(pubKeyHex);
  }

  Future<Map<String, dynamic>?> _readStateForCurrentCapsule(
      HivraBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra);
    return _fileStore.readState(dir);
  }

  Future<Directory> _currentCapsuleDir(HivraBindings? hivra,
      {bool create = false}) async {
    final docs = await _fileStore.docsDirectory();
    String? capsuleId;
    if (hivra != null) {
      final pubKey = hivra.capsulePublicKey();
      if (pubKey != null && pubKey.length == 32) {
        capsuleId = _bytesToHex(pubKey);
      }
    }
    if (capsuleId == null || capsuleId.isEmpty) return docs;

    final dir = await _fileStore.capsuleDirForHex(capsuleId, create: false);
    final existed = await dir.exists();
    if (create && !existed) {
      await _fileStore.capsuleDirForHex(capsuleId, create: true);
      await _migrateLegacyToCapsuleDir(docs, dir, capsuleId);
    }
    return dir;
  }

  Future<Directory> _capsuleDirForHex(String pubKeyHex,
      {bool create = false}) async {
    final docs = await _fileStore.docsDirectory();
    final dir = await _fileStore.capsuleDirForHex(pubKeyHex, create: false);
    final existed = await dir.exists();
    if (create && !existed) {
      await _fileStore.capsuleDirForHex(pubKeyHex, create: true);
      await _migrateLegacyToCapsuleDir(docs, dir, pubKeyHex);
    }
    return dir;
  }

  Future<void> _migrateLegacyToCapsuleDir(
    Directory docs,
    Directory target,
    String pubKeyHex,
  ) async {
    final legacyState = _fileStore.legacyStateFile(docs);
    final legacyLedger = _fileStore.legacyLedgerFile(docs);
    final legacyBackup = _fileStore.legacyBackupFile(docs);

    if (!await legacyLedger.exists()) return;
    try {
      final raw = await legacyLedger.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final ledger = Map<String, dynamic>.from(decoded);
      final ownerBytes = _summaryParser.parseBytesField(ledger['owner']);
      if (ownerBytes == null) return;
      final ownerHex = _bytesToHex(Uint8List.fromList(ownerBytes));
      if (ownerHex != pubKeyHex) return;
    } catch (_) {
      return;
    }

    if (await legacyState.exists()) {
      await legacyState.rename('${target.path}/${CapsuleFileStore.stateFileName}');
    }
    if (await legacyLedger.exists()) {
      await legacyLedger.rename('${target.path}/${CapsuleFileStore.ledgerFileName}');
    }
    if (await legacyBackup.exists()) {
      await legacyBackup.rename('${target.path}/${CapsuleFileStore.backupFileName}');
    }
  }

  Future<void> _storeSeedForCapsule(String pubKeyHex, Uint8List seed) async {
    await _seedStore.storeSeed(pubKeyHex, seed);
  }

  Future<Uint8List?> _loadSeedForCapsule(String pubKeyHex) async {
    return _seedStore.loadSeed(pubKeyHex);
  }

  Future<void> _touchActiveCapsule(HivraBindings hivra) async {
    final pubKey = hivra.capsulePublicKey();
    if (pubKey == null || pubKey.length != 32) return;
    final pubKeyHex = _bytesToHex(pubKey);
    await _upsertCapsuleIndex(pubKeyHex);
    await _setActiveCapsule(pubKeyHex);
  }

  Future<void> _upsertCapsuleIndex(
    String pubKeyHex, {
    bool? isGenesis,
    bool? isNeste,
  }) async {
    await _indexStore.upsert(
      pubKeyHex,
      isGenesis: isGenesis,
      isNeste: isNeste,
    );
  }

  Future<void> _setActiveCapsule(String pubKeyHex) async {
    await _indexStore.setActive(pubKeyHex);
  }

  Future<CapsulesIndex> _readIndex() async {
    return _indexStore.read();
  }

  Future<void> _writeIndex(CapsulesIndex index) async {
    await _indexStore.write(index);
  }

  Future<void> _ensureIndexFromCurrentSeed(HivraBindings hivra) async {
    final index = await _readIndex();
    if (index.capsules.isNotEmpty) return;
    if (!hivra.seedExists()) return;
    final pubKey = hivra.capsulePublicKey();
    if (pubKey == null || pubKey.length != 32) return;
    final pubKeyHex = _bytesToHex(pubKey);

    await _capsuleDirForHex(pubKeyHex, create: true);
    final currentSeed = hivra.loadSeed();
    if (currentSeed != null) {
      await _storeSeedForCapsule(pubKeyHex, currentSeed);
    }
    final state = await _readStateForCapsuleHex(pubKeyHex);
    await _upsertCapsuleIndex(
      pubKeyHex,
      isGenesis: state?['isGenesis'] == true,
      isNeste: state?['isNeste'] != false,
    );
    await _setActiveCapsule(pubKeyHex);
  }

  Future<Map<String, dynamic>?> _readStateForCapsuleHex(
      String pubKeyHex) async {
    final dir = await _capsuleDirForHex(pubKeyHex);
    return _fileStore.readState(dir);
  }

  String _bytesToHex(Uint8List bytes) {
    final b = StringBuffer();
    for (final byte in bytes) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  String? _extractOwnerHex(String ledgerJson) {
    try {
      final decoded = jsonDecode(ledgerJson);
      if (decoded is! Map) return null;
      final ledger = Map<String, dynamic>.from(decoded);
      final ownerBytes = _summaryParser.parseBytesField(ledger['owner']);
      if (ownerBytes == null || ownerBytes.length != 32) return null;
      return _bytesToHex(Uint8List.fromList(ownerBytes));
    } catch (_) {
      return null;
    }
  }

  _BackupMeta? _extractBackupMeta(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final meta = map['meta'];
      if (meta is! Map) return null;
      final m = Map<String, dynamic>.from(meta);
      return _BackupMeta(
        isGenesis: m['is_genesis'] == true
            ? true
            : (m['is_genesis'] == false ? false : null),
        isNeste: m['is_neste'] == true
            ? true
            : (m['is_neste'] == false ? false : null),
      );
    } catch (_) {
      return null;
    }
  }
}

class _BackupMeta {
  final bool? isGenesis;
  final bool? isNeste;

  _BackupMeta({required this.isGenesis, required this.isNeste});
}
