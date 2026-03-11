import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../ffi/hivra_bindings.dart';
import 'capsule_backup_codec.dart';

class CapsulePersistenceService {
  static final CapsulePersistenceService _instance =
      CapsulePersistenceService._internal();

  factory CapsulePersistenceService() => _instance;

  CapsulePersistenceService._internal();

  static const String _stateFileName = 'capsule_state.json';
  static const String _ledgerFileName = 'ledger.json';
  static const String _backupFileName = 'capsule-backup.v1.json';
  static const String _capsulesDirName = 'capsules';
  static const String _indexFileName = 'capsules_index.json';
  static const String _seedKeyPrefix = 'hivra.seed.';
  static const String _seedFallbackFileName = 'capsule_seeds.json';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<void> persistAfterCreate({
    required HivraBindings hivra,
    required Uint8List seed,
    required bool isGenesis,
    required bool isNeste,
  }) async {
    final pubKey = hivra.capsulePublicKey();
    final pubKeyHex = pubKey != null ? _bytesToHex(pubKey) : null;
    final dir = await _currentCapsuleDir(hivra, create: true);

    final stateFile = File('${dir.path}/$_stateFileName');
    final state = <String, dynamic>{
      'isGenesis': isGenesis,
      'isNeste': isNeste,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'seedLength': seed.length,
    };
    await stateFile.writeAsString(jsonEncode(state), flush: true);

    final ledger = hivra.exportLedger();
    if (ledger != null && ledger.isNotEmpty) {
      final ledgerFile = File('${dir.path}/$_ledgerFileName');
      await ledgerFile.writeAsString(ledger, flush: true);

      final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
        ledgerJson: ledger,
        isGenesis: isGenesis,
        isNeste: isNeste,
      );
      final backupFile = File('${dir.path}/$_backupFileName');
      await backupFile.writeAsString(backupJson, flush: true);
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
    final ledgerFile = File('${dir.path}/$_ledgerFileName');
    if (await ledgerFile.exists()) {
      final ledgerJson = await ledgerFile.readAsString();
      if (ledgerJson.trim().isNotEmpty && hivra.importLedger(ledgerJson)) {
        await _touchActiveCapsule(hivra);
        return true;
      }
    }
    return importBackupEnvelopeIfExists(hivra);
  }

  Future<bool> persistLedgerSnapshot(HivraBindings hivra) async {
    final ledger = hivra.exportLedger();
    if (ledger == null || ledger.isEmpty) return false;

    final dir = await _currentCapsuleDir(hivra, create: true);
    final ledgerFile = File('${dir.path}/$_ledgerFileName');
    await ledgerFile.writeAsString(ledger, flush: true);
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
    final backupFile = File('${dir.path}/$_backupFileName');
    await backupFile.writeAsString(backupJson, flush: true);
    await _touchActiveCapsule(hivra);
    return backupFile.path;
  }

  Future<bool> importBackupEnvelopeIfExists(HivraBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra);
    final backupFile = File('${dir.path}/$_backupFileName');
    if (!await backupFile.exists()) return false;

    final backupJson = await backupFile.readAsString();
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
    final stateFile = File('${dir.path}/$_stateFileName');
    final ledgerFile = File('${dir.path}/$_ledgerFileName');
    final backupFile = File('${dir.path}/$_backupFileName');

    if (await stateFile.exists()) {
      await stateFile.delete();
    }
    if (await ledgerFile.exists()) {
      await ledgerFile.delete();
    }
    if (includeBackup && await backupFile.exists()) {
      await backupFile.delete();
    }
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
    return '${dir.path}/$_backupFileName';
  }

  Future<String> getCurrentLedgerPath(HivraBindings hivra) async {
    final dir = await _currentCapsuleDir(hivra, create: true);
    return '${dir.path}/$_ledgerFileName';
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
    final docs = await getApplicationDocumentsDirectory();
    final capsuleDir = Directory('${docs.path}/$_capsulesDirName/$pubKeyHex');
    final ledgerFile = File('${capsuleDir.path}/$_ledgerFileName');
    if (!await ledgerFile.exists()) {
      return CapsuleLedgerSummary.empty();
    }
    try {
      final raw = await ledgerFile.readAsString();
      return _parseLedgerSummary(raw);
    } catch (_) {
      return CapsuleLedgerSummary.empty();
    }
  }

  Future<CapsuleRuntimeBootstrap?> loadRuntimeBootstrap(
    String pubKeyHex, {
    HivraBindings? hivra,
  }) async {
    final seed = hivra == null
        ? await _loadSeedForCapsule(pubKeyHex)
        : await _loadValidatedSeedForCapsule(hivra, pubKeyHex);
    if (seed == null) return null;

    final state = await _readStateForCapsuleHex(pubKeyHex);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;

    final dir = await _capsuleDirForHex(pubKeyHex, create: true);
    final ledgerFile = File('${dir.path}/$_ledgerFileName');

    String? ledgerJson;
    if (await ledgerFile.exists()) {
      final raw = await ledgerFile.readAsString();
      if (raw.trim().isNotEmpty) {
        ledgerJson = raw;
      }
    } else {
      final backupFile = File('${dir.path}/$_backupFileName');
      if (await backupFile.exists()) {
        final backupJson = await backupFile.readAsString();
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
      HivraBindings hivra) async {
    final pubKey = hivra.capsulePublicKey();
    final seed = hivra.loadSeed();
    if (pubKey == null || pubKey.length != 32 || seed == null) return null;

    final state = await _readStateForCurrentCapsule(hivra);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;
    final ledgerJson = hivra.exportLedger();

    return CapsuleRuntimeBootstrap(
      pubKeyHex: _bytesToHex(pubKey),
      seed: seed,
      isGenesis: isGenesis,
      isNeste: isNeste,
      ledgerJson:
          (ledgerJson != null && ledgerJson.isNotEmpty) ? ledgerJson : null,
    );
  }

  Future<String?> exportCapsuleBackupToPath(
      String pubKeyHex, String targetPath) async {
    final docs = await getApplicationDocumentsDirectory();
    final capsuleDir = Directory('${docs.path}/$_capsulesDirName/$pubKeyHex');
    final ledgerFile = File('${capsuleDir.path}/$_ledgerFileName');
    if (!await ledgerFile.exists()) return null;

    final ledgerJson = await ledgerFile.readAsString();
    if (ledgerJson.trim().isEmpty) return null;

    final backupJson = CapsuleBackupCodec.encodeBackupEnvelope(
      ledgerJson: ledgerJson,
    );
    final outFile = File(targetPath);
    await outFile.writeAsString(backupJson, flush: true);
    return outFile.path;
  }

  Future<bool> refreshCapsuleSnapshot(
      HivraBindings hivra, String pubKeyHex) async {
    final seed = await _loadValidatedSeedForCapsule(hivra, pubKeyHex);
    if (seed == null) return false;
    if (!hivra.saveSeed(seed)) return false;

    final state = await _readStateForCapsuleHex(pubKeyHex);
    final isGenesis = state?['isGenesis'] == true;
    final isNeste = state?['isNeste'] != false;
    if (!hivra.createCapsule(seed, isGenesis: isGenesis, isNeste: isNeste)) {
      return false;
    }

    final dir = await _capsuleDirForHex(pubKeyHex, create: true);
    final ledgerFile = File('${dir.path}/$_ledgerFileName');
    if (await ledgerFile.exists()) {
      final ledgerJson = await ledgerFile.readAsString();
      if (ledgerJson.trim().isNotEmpty) {
        hivra.importLedger(ledgerJson);
      }
    } else {
      final backupFile = File('${dir.path}/$_backupFileName');
      if (await backupFile.exists()) {
        final backupJson = await backupFile.readAsString();
        final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(backupJson);
        if (ledgerJson != null && ledgerJson.trim().isNotEmpty) {
          hivra.importLedger(ledgerJson);
        }
      }
    }

    final exported = hivra.exportLedger();
    if (exported == null || exported.isEmpty) return false;
    await ledgerFile.writeAsString(exported, flush: true);
    return true;
  }

  Future<String?> importCapsuleFromBackupJson(String rawJson) async {
    final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(rawJson);
    if (ledgerJson == null) return null;

    final ownerHex = _extractOwnerHex(ledgerJson);
    if (ownerHex == null) return null;

    final docs = await getApplicationDocumentsDirectory();
    final capsuleDir = Directory('${docs.path}/$_capsulesDirName/$ownerHex');
    if (!await capsuleDir.exists()) {
      await capsuleDir.create(recursive: true);
    }

    final ledgerFile = File('${capsuleDir.path}/$_ledgerFileName');
    await ledgerFile.writeAsString(ledgerJson, flush: true);

    final backupFile = File('${capsuleDir.path}/$_backupFileName');
    await backupFile.writeAsString(rawJson, flush: true);

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
      final docs = await getApplicationDocumentsDirectory();
      final capsuleDir = Directory('${docs.path}/$_capsulesDirName/$pubKeyHex');
      if (await capsuleDir.exists()) {
        await capsuleDir.delete(recursive: true);
      }
    }
    try {
      await _secureStorage.delete(key: '$_seedKeyPrefix$pubKeyHex');
    } catch (_) {
      await _deleteSeedFallback(pubKeyHex);
    }
    final index = await _readIndex();
    index.capsules.remove(pubKeyHex);
    if (index.activePubKeyHex == pubKeyHex) {
      index.activePubKeyHex = null;
    }
    await _writeIndex(index);
  }

  Future<bool> hasStoredSeed(String pubKeyHex) async {
    String? encoded;
    encoded = await _readSeedFromSecureStorage(pubKeyHex);
    encoded ??= await _readSeedFallback(pubKeyHex);
    return encoded != null && encoded.isNotEmpty;
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
    final stateFile = File('${dir.path}/$_stateFileName');
    if (!await stateFile.exists()) return null;

    try {
      final raw = await stateFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _currentCapsuleDir(HivraBindings? hivra,
      {bool create = false}) async {
    final docs = await getApplicationDocumentsDirectory();
    final capsulesRoot = Directory('${docs.path}/$_capsulesDirName');
    if (create && !await capsulesRoot.exists()) {
      await capsulesRoot.create(recursive: true);
    }

    String? capsuleId;
    if (hivra != null) {
      final pubKey = hivra.capsulePublicKey();
      if (pubKey != null && pubKey.length == 32) {
        capsuleId = _bytesToHex(pubKey);
      }
    }

    if (capsuleId == null || capsuleId.isEmpty) {
      return docs;
    }

    final dir = Directory('${capsulesRoot.path}/$capsuleId');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
      await _migrateLegacyToCapsuleDir(docs, dir, capsuleId);
    }
    return dir;
  }

  Future<Directory> _capsuleDirForHex(String pubKeyHex,
      {bool create = false}) async {
    final docs = await getApplicationDocumentsDirectory();
    final capsulesRoot = Directory('${docs.path}/$_capsulesDirName');
    if (create && !await capsulesRoot.exists()) {
      await capsulesRoot.create(recursive: true);
    }
    final dir = Directory('${capsulesRoot.path}/$pubKeyHex');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
      await _migrateLegacyToCapsuleDir(docs, dir, pubKeyHex);
    }
    return dir;
  }

  Future<void> _migrateLegacyToCapsuleDir(
    Directory docs,
    Directory target,
    String pubKeyHex,
  ) async {
    final legacyState = File('${docs.path}/$_stateFileName');
    final legacyLedger = File('${docs.path}/$_ledgerFileName');
    final legacyBackup = File('${docs.path}/$_backupFileName');

    if (!await legacyLedger.exists()) return;
    try {
      final raw = await legacyLedger.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final ledger = Map<String, dynamic>.from(decoded);
      final ownerBytes = _parseBytesField(ledger['owner']);
      if (ownerBytes == null) return;
      final ownerHex = _bytesToHex(Uint8List.fromList(ownerBytes));
      if (ownerHex != pubKeyHex) return;
    } catch (_) {
      return;
    }

    if (await legacyState.exists()) {
      await legacyState.rename('${target.path}/$_stateFileName');
    }
    if (await legacyLedger.exists()) {
      await legacyLedger.rename('${target.path}/$_ledgerFileName');
    }
    if (await legacyBackup.exists()) {
      await legacyBackup.rename('${target.path}/$_backupFileName');
    }
  }

  Future<void> _storeSeedForCapsule(String pubKeyHex, Uint8List seed) async {
    final encoded = base64Encode(seed);
    try {
      await _secureStorage.write(
          key: '$_seedKeyPrefix$pubKeyHex', value: encoded);
      return;
    } catch (_) {
      await _writeSeedFallback(pubKeyHex, encoded);
    }
  }

  Future<String?> _readSeedFromSecureStorage(String pubKeyHex) async {
    try {
      return await _secureStorage.read(key: '$_seedKeyPrefix$pubKeyHex');
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _loadSeedForCapsule(String pubKeyHex) async {
    var encoded = await _readSeedFromSecureStorage(pubKeyHex);
    encoded ??= await _readSeedFallback(pubKeyHex);
    return _decodeSeedString(encoded);
  }

  Future<Uint8List?> _loadValidatedSeedForCapsule(
    HivraBindings hivra,
    String pubKeyHex,
  ) async {
    final secureSeed = _decodeSeedString(
      await _readSeedFromSecureStorage(pubKeyHex),
    );
    if (secureSeed != null &&
        await seedMatchesCapsule(hivra, secureSeed, pubKeyHex)) {
      return secureSeed;
    }

    final fallbackSeed = _decodeSeedString(await _readSeedFallback(pubKeyHex));
    if (fallbackSeed != null &&
        await seedMatchesCapsule(hivra, fallbackSeed, pubKeyHex)) {
      await _storeSeedForCapsule(pubKeyHex, fallbackSeed);
      return fallbackSeed;
    }

    return null;
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
    final index = await _readIndex();
    final now = DateTime.now().toUtc();
    final existing = index.capsules[pubKeyHex];
    final entry = CapsuleIndexEntry(
      pubKeyHex: pubKeyHex,
      createdAt: existing?.createdAt ?? now,
      lastActive: now,
      isGenesis: isGenesis ?? existing?.isGenesis ?? false,
      isNeste: isNeste ?? existing?.isNeste ?? true,
    );
    index.capsules[pubKeyHex] = entry;
    await _writeIndex(index);
  }

  Future<void> _setActiveCapsule(String pubKeyHex) async {
    final index = await _readIndex();
    index.activePubKeyHex = pubKeyHex;
    await _writeIndex(index);
  }

  Future<_CapsulesIndex> _readIndex() async {
    final docs = await getApplicationDocumentsDirectory();
    final capsulesRoot = Directory('${docs.path}/$_capsulesDirName');
    final indexFile = File('${capsulesRoot.path}/$_indexFileName');
    if (!await indexFile.exists()) {
      return _CapsulesIndex.empty();
    }
    try {
      final raw = await indexFile.readAsString();
      return _CapsulesIndex.fromJson(raw);
    } catch (_) {
      return _CapsulesIndex.empty();
    }
  }

  Future<void> _writeIndex(_CapsulesIndex index) async {
    final docs = await getApplicationDocumentsDirectory();
    final capsulesRoot = Directory('${docs.path}/$_capsulesDirName');
    if (!await capsulesRoot.exists()) {
      await capsulesRoot.create(recursive: true);
    }
    final indexFile = File('${capsulesRoot.path}/$_indexFileName');
    await indexFile.writeAsString(index.toJson(), flush: true);
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
    final stateFile = File('${dir.path}/$_stateFileName');
    if (!await stateFile.exists()) return null;
    try {
      final raw = await stateFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  String _bytesToHex(Uint8List bytes) {
    final b = StringBuffer();
    for (final byte in bytes) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  CapsuleLedgerSummary _parseLedgerSummary(String json) {
    if (json.trim().isEmpty) return CapsuleLedgerSummary.empty();
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return CapsuleLedgerSummary.empty();
      final ledger = Map<String, dynamic>.from(decoded);
      final eventsRaw = ledger['events'];
      final events = eventsRaw is List ? eventsRaw : const [];

      int relationshipEstablished = 0;
      int relationshipBroken = 0;
      int invitationSent = 0;
      int invitationResolved = 0;
      final activeStartersById = <String, int>{};

      for (final eventRaw in events) {
        if (eventRaw is! Map) continue;
        final event = Map<String, dynamic>.from(eventRaw);
        final kind = _eventKindCode(event['kind']);

        switch (kind) {
          case 1:
            invitationSent++;
            break;
          case 2:
          case 3:
          case 4:
            invitationResolved++;
            break;
          case 5:
            final payload = _parseBytesField(event['payload']);
            final starter = _parseStarterCreated(payload);
            if (starter != null) {
              activeStartersById[
                      _bytesToHex(Uint8List.fromList(starter.starterId))] =
                  starter.kindCode;
            }
            break;
          case 6:
            final payload = _parseBytesField(event['payload']);
            final burnedId = _parseStarterBurnedId(payload);
            if (burnedId != null) {
              activeStartersById
                  .remove(_bytesToHex(Uint8List.fromList(burnedId)));
            }
            break;
          case 7:
            relationshipEstablished++;
            break;
          case 8:
            relationshipBroken++;
            break;
          default:
            break;
        }
      }

      final starterCount = activeStartersById.length.clamp(0, 5);
      final relationshipCount =
          (relationshipEstablished - relationshipBroken).clamp(0, 9999);
      final pendingInvitations =
          (invitationSent - invitationResolved).clamp(0, 9999);
      final ledgerVersion = events.length;
      final ledgerHashHex = _parseLedgerHashHex(ledger['last_hash']);

      return CapsuleLedgerSummary(
        starterCount: starterCount,
        relationshipCount: relationshipCount,
        pendingInvitations: pendingInvitations,
        ledgerVersion: ledgerVersion,
        ledgerHashHex: ledgerHashHex,
      );
    } catch (_) {
      return CapsuleLedgerSummary.empty();
    }
  }

  int _eventKindCode(dynamic rawKind) {
    if (rawKind is num) return rawKind.toInt();
    if (rawKind is! String) return -1;
    switch (rawKind) {
      case 'InvitationSent':
        return 1;
      case 'InvitationAccepted':
        return 2;
      case 'InvitationRejected':
        return 3;
      case 'InvitationExpired':
        return 4;
      case 'StarterCreated':
        return 5;
      case 'StarterBurned':
        return 6;
      case 'RelationshipEstablished':
        return 7;
      case 'RelationshipBroken':
        return 8;
      default:
        return -1;
    }
  }

  List<int>? _parseBytesField(dynamic raw) {
    if (raw is List) {
      final out = <int>[];
      for (final item in raw) {
        if (item is! num) return null;
        final value = item.toInt();
        if (value < 0 || value > 255) return null;
        out.add(value);
      }
      return out;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final isHex = RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed);
      if (isHex && trimmed.length.isEven) {
        final out = <int>[];
        for (int i = 0; i < trimmed.length; i += 2) {
          out.add(int.parse(trimmed.substring(i, i + 2), radix: 16));
        }
        return out;
      }
      try {
        return base64Decode(trimmed);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  _StarterRecord? _parseStarterCreated(List<int>? payload) {
    if (payload == null || payload.length < 66) return null;
    final kindCode = payload[64];
    if (kindCode < 0 || kindCode > 4) return null;
    final starterId = payload.sublist(0, 32);
    return _StarterRecord(kindCode: kindCode, starterId: starterId);
  }

  List<int>? _parseStarterBurnedId(List<int>? payload) {
    if (payload == null || payload.length < 32) return null;
    return payload.sublist(0, 32);
  }

  String _parseLedgerHashHex(dynamic raw) {
    if (raw == null) return '0';
    if (raw is int) {
      return raw.toUnsigned(64).toRadixString(16);
    }
    if (raw is double) {
      return raw.toInt().toUnsigned(64).toRadixString(16);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return '0';
      final dec = int.tryParse(trimmed);
      if (dec != null) return dec.toUnsigned(64).toRadixString(16);
      final hex = trimmed.startsWith('0x') ? trimmed.substring(2) : trimmed;
      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
        return hex.toLowerCase();
      }
    }
    return '0';
  }

  String? _extractOwnerHex(String ledgerJson) {
    try {
      final decoded = jsonDecode(ledgerJson);
      if (decoded is! Map) return null;
      final ledger = Map<String, dynamic>.from(decoded);
      final ownerBytes = _parseBytesField(ledger['owner']);
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
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    map[pubKeyHex] = encodedSeed;
    await file.writeAsString(jsonEncode(map), flush: true);
  }

  Future<String?> _readSeedFallback(String pubKeyHex) async {
    final file = await _seedFallbackFile();
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final value = map[pubKeyHex];
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteSeedFallback(String pubKeyHex) async {
    final file = await _seedFallbackFile();
    if (!await file.exists()) return;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      map.remove(pubKeyHex);
      await file.writeAsString(jsonEncode(map), flush: true);
    } catch (_) {}
  }

  Uint8List? _decodeSeedString(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }
}

class CapsuleIndexEntry {
  final String pubKeyHex;
  final DateTime createdAt;
  final DateTime lastActive;
  final bool isGenesis;
  final bool isNeste;

  CapsuleIndexEntry({
    required this.pubKeyHex,
    required this.createdAt,
    required this.lastActive,
    required this.isGenesis,
    required this.isNeste,
  });

  Map<String, dynamic> toMap() => {
        'pubKeyHex': pubKeyHex,
        'createdAt': createdAt.toIso8601String(),
        'lastActive': lastActive.toIso8601String(),
        'isGenesis': isGenesis,
        'isNeste': isNeste,
      };

  static CapsuleIndexEntry fromMap(Map<String, dynamic> map) {
    final created = DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
        DateTime.now().toUtc();
    final last =
        DateTime.tryParse(map['lastActive']?.toString() ?? '') ?? created;
    return CapsuleIndexEntry(
      pubKeyHex: map['pubKeyHex']?.toString() ?? '',
      createdAt: created.toUtc(),
      lastActive: last.toUtc(),
      isGenesis: map['isGenesis'] == true,
      isNeste: map['isNeste'] != false,
    );
  }
}

class CapsuleLedgerSummary {
  final int starterCount;
  final int relationshipCount;
  final int pendingInvitations;
  final int ledgerVersion;
  final String ledgerHashHex;

  CapsuleLedgerSummary({
    required this.starterCount,
    required this.relationshipCount,
    required this.pendingInvitations,
    required this.ledgerVersion,
    required this.ledgerHashHex,
  });

  static CapsuleLedgerSummary empty() => CapsuleLedgerSummary(
        starterCount: 0,
        relationshipCount: 0,
        pendingInvitations: 0,
        ledgerVersion: 0,
        ledgerHashHex: '0',
      );
}

class CapsuleRuntimeBootstrap {
  final String pubKeyHex;
  final Uint8List seed;
  final bool isGenesis;
  final bool isNeste;
  final String? ledgerJson;

  CapsuleRuntimeBootstrap({
    required this.pubKeyHex,
    required this.seed,
    required this.isGenesis,
    required this.isNeste,
    required this.ledgerJson,
  });
}

class _StarterRecord {
  final int kindCode;
  final List<int> starterId;

  _StarterRecord({required this.kindCode, required this.starterId});
}

class _BackupMeta {
  final bool? isGenesis;
  final bool? isNeste;

  _BackupMeta({required this.isGenesis, required this.isNeste});
}

class _CapsulesIndex {
  String? activePubKeyHex;
  final Map<String, CapsuleIndexEntry> capsules;

  _CapsulesIndex({required this.activePubKeyHex, required this.capsules});

  static _CapsulesIndex empty() =>
      _CapsulesIndex(activePubKeyHex: null, capsules: {});

  static _CapsulesIndex fromJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return _CapsulesIndex.empty();
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
    return _CapsulesIndex(activePubKeyHex: active, capsules: capsulesMap);
  }

  String toJson() {
    final capsulesJson = <String, dynamic>{};
    for (final entry in capsules.entries) {
      capsulesJson[entry.key] = entry.value.toMap();
    }
    return jsonEncode({
      'active': activePubKeyHex,
      'capsules': capsulesJson,
    });
  }
}
