import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

// C function typedefs
typedef HivraSeedToMnemonicC = Int32 Function(
  Pointer<Uint8> seed,
  Uint32 wordCount,
  Pointer<Pointer<Int8>> outPhrase,
);
typedef HivraSeedToMnemonicDart = int Function(
  Pointer<Uint8> seed,
  int wordCount,
  Pointer<Pointer<Int8>> outPhrase,
);

typedef HivraMnemonicToSeedC = Int32 Function(
  Pointer<Int8> phrase,
  Pointer<Uint8> outSeed,
);
typedef HivraMnemonicToSeedDart = int Function(
  Pointer<Int8> phrase,
  Pointer<Uint8> outSeed,
);

typedef HivraGenerateRandomSeedC = Int32 Function(Pointer<Uint8> outSeed);
typedef HivraGenerateRandomSeedDart = int Function(Pointer<Uint8> outSeed);

typedef HivraSeedPublicKeyC = Int32 Function(
  Pointer<Uint8> seed,
  Pointer<Uint8> outKey,
);
typedef HivraSeedPublicKeyDart = int Function(
  Pointer<Uint8> seed,
  Pointer<Uint8> outKey,
);

typedef HivraFreeStringC = Void Function(Pointer<Int8> ptr);
typedef HivraFreeStringDart = void Function(Pointer<Int8> ptr);

typedef HivraSeedExistsC = Int8 Function();
typedef HivraSeedExistsDart = int Function();

typedef HivraSeedSaveC = Int32 Function(Pointer<Uint8> seed);
typedef HivraSeedSaveDart = int Function(Pointer<Uint8> seed);

typedef HivraSeedLoadC = Int32 Function(Pointer<Uint8> outSeed);
typedef HivraSeedLoadDart = int Function(Pointer<Uint8> outSeed);

typedef HivraSeedDeleteC = Int32 Function();
typedef HivraSeedDeleteDart = int Function();

typedef HivraCapsuleCreateC = Int32 Function(
  Pointer<Uint8> seed,
  Uint8 network,
  Uint8 capsuleType,
);
typedef HivraCapsuleCreateDart = int Function(
  Pointer<Uint8> seed,
  int network,
  int capsuleType,
);

typedef HivraCapsulePublicKeyC = Int32 Function(Pointer<Uint8> outKey);
typedef HivraCapsulePublicKeyDart = int Function(Pointer<Uint8> outKey);

typedef HivraCapsuleResetC = Int32 Function();
typedef HivraCapsuleResetDart = int Function();

typedef HivraStarterGetIdC = Int32 Function(
  Uint8 slot,
  Pointer<Uint8> outId,
);
typedef HivraStarterGetIdDart = int Function(
  int slot,
  Pointer<Uint8> outId,
);

typedef HivraStarterGetTypeC = Int32 Function(Uint8 slot);
typedef HivraStarterGetTypeDart = int Function(int slot);

typedef HivraStarterExistsC = Int8 Function(Uint8 slot);
typedef HivraStarterExistsDart = int Function(int slot);

typedef HivraSendInvitationC = Int32 Function(
  Pointer<Uint8> toPubkey,
  Uint8 starterSlot,
);
typedef HivraSendInvitationDart = int Function(
  Pointer<Uint8> toPubkey,
  int starterSlot,
);

typedef HivraTransportReceiveC = Int32 Function();
typedef HivraTransportReceiveDart = int Function();

typedef HivraAcceptInvitationC = Int32 Function(
  Pointer<Uint8> invitationId,
  Pointer<Uint8> fromPubkey,
  Pointer<Uint8> createdStarterId,
);
typedef HivraAcceptInvitationDart = int Function(
  Pointer<Uint8> invitationId,
  Pointer<Uint8> fromPubkey,
  Pointer<Uint8> createdStarterId,
);

typedef HivraRejectInvitationC = Int32 Function(
  Pointer<Uint8> invitationId,
  Uint8 reason,
);
typedef HivraRejectInvitationDart = int Function(
  Pointer<Uint8> invitationId,
  int reason,
);

typedef HivraExpireInvitationC = Int32 Function(Pointer<Uint8> invitationId);
typedef HivraExpireInvitationDart = int Function(Pointer<Uint8> invitationId);

typedef HivraNostrSendPreparedSelfCheckC = Int32 Function();
typedef HivraNostrSendPreparedSelfCheckDart = int Function();

typedef HivraExportLedgerC = Int32 Function(Pointer<Pointer<Int8>> outJson);
typedef HivraExportLedgerDart = int Function(Pointer<Pointer<Int8>> outJson);

typedef HivraImportLedgerC = Int32 Function(Pointer<Int8> json);
typedef HivraImportLedgerDart = int Function(Pointer<Int8> json);

typedef HivraLedgerAppendEventC = Int32 Function(
  Uint8 kind,
  Pointer<Uint8> payload,
  Uint64 payloadLen,
);
typedef HivraLedgerAppendEventDart = int Function(
  int kind,
  Pointer<Uint8> payload,
  int payloadLen,
);

class HivraBindings {
  static final HivraBindings _instance = HivraBindings._internal();
  
  factory HivraBindings() => _instance;
  static HivraBindings load() => _instance;

  static final DynamicLibrary _lib = Platform.isMacOS
      ? DynamicLibrary.open('libhivra_ffi.dylib')
      : Platform.isAndroid
          ? DynamicLibrary.open('libhivra_ffi.so')
          : DynamicLibrary.process();

  late final HivraSeedToMnemonicDart _seedToMnemonic;
  late final HivraMnemonicToSeedDart _mnemonicToSeed;
  late final HivraGenerateRandomSeedDart _generateRandomSeed;
  late final HivraSeedPublicKeyDart _seedPublicKey;
  late final HivraFreeStringDart _freeString;
  late final HivraSeedExistsDart _seedExists;
  late final HivraSeedSaveDart _seedSave;
  late final HivraSeedLoadDart _seedLoad;
  late final HivraSeedDeleteDart _seedDelete;
  late final HivraCapsuleCreateDart _capsuleCreate;
  late final HivraCapsulePublicKeyDart _capsulePublicKey;
  late final HivraCapsuleResetDart _capsuleReset;
  late final HivraStarterGetIdDart _starterGetId;
  late final HivraStarterGetTypeDart _starterGetType;
  late final HivraStarterExistsDart _starterExists;
  HivraSendInvitationDart? _sendInvitation;
  HivraTransportReceiveDart? _transportReceive;
  HivraAcceptInvitationDart? _acceptInvitation;
  HivraRejectInvitationDart? _rejectInvitation;
  HivraExpireInvitationDart? _expireInvitation;
  HivraNostrSendPreparedSelfCheckDart? _nostrSendPreparedSelfCheck;
  late final HivraExportLedgerDart _exportLedger;
  late final HivraImportLedgerDart _importLedger;
  late final HivraLedgerAppendEventDart _ledgerAppendEvent;

  HivraBindings._internal() {
    _seedToMnemonic = _lib
        .lookup<NativeFunction<HivraSeedToMnemonicC>>('hivra_seed_to_mnemonic')
        .asFunction();
    
    _mnemonicToSeed = _lib
        .lookup<NativeFunction<HivraMnemonicToSeedC>>('hivra_mnemonic_to_seed')
        .asFunction();
    
    _generateRandomSeed = _lib
        .lookup<NativeFunction<HivraGenerateRandomSeedC>>('hivra_generate_random_seed')
        .asFunction();

    _seedPublicKey = _lib
        .lookup<NativeFunction<HivraSeedPublicKeyC>>('hivra_seed_public_key')
        .asFunction();
    
    _freeString = _lib
        .lookup<NativeFunction<HivraFreeStringC>>('hivra_free_string')
        .asFunction();

    _seedExists = _lib
        .lookup<NativeFunction<HivraSeedExistsC>>('hivra_seed_exists')
        .asFunction();

    _seedSave = _lib
        .lookup<NativeFunction<HivraSeedSaveC>>('hivra_seed_save')
        .asFunction();

    _seedLoad = _lib
        .lookup<NativeFunction<HivraSeedLoadC>>('hivra_seed_load')
        .asFunction();

    _seedDelete = _lib
        .lookup<NativeFunction<HivraSeedDeleteC>>('hivra_seed_delete')
        .asFunction();

    _capsuleCreate = _lib
        .lookup<NativeFunction<HivraCapsuleCreateC>>('hivra_capsule_create')
        .asFunction();

    _capsulePublicKey = _lib
        .lookup<NativeFunction<HivraCapsulePublicKeyC>>('hivra_capsule_public_key')
        .asFunction();

    _capsuleReset = _lib
        .lookup<NativeFunction<HivraCapsuleResetC>>('hivra_capsule_reset')
        .asFunction();

    _starterGetId = _lib
        .lookup<NativeFunction<HivraStarterGetIdC>>('hivra_starter_get_id')
        .asFunction();

    _starterGetType = _lib
        .lookup<NativeFunction<HivraStarterGetTypeC>>('hivra_starter_get_type')
        .asFunction();

    _starterExists = _lib
        .lookup<NativeFunction<HivraStarterExistsC>>('hivra_starter_exists')
        .asFunction();

    try {
      _sendInvitation = _lib
          .lookup<NativeFunction<HivraSendInvitationC>>('hivra_send_invitation')
          .asFunction();
    } catch (_) {
      _sendInvitation = null;
    }

    try {
      _transportReceive = _lib
          .lookup<NativeFunction<HivraTransportReceiveC>>('hivra_transport_receive')
          .asFunction();
    } catch (_) {
      _transportReceive = null;
    }

    try {
      _acceptInvitation = _lib
          .lookup<NativeFunction<HivraAcceptInvitationC>>('hivra_accept_invitation')
          .asFunction();
    } catch (_) {
      _acceptInvitation = null;
    }

    try {
      _rejectInvitation = _lib
          .lookup<NativeFunction<HivraRejectInvitationC>>('hivra_reject_invitation')
          .asFunction();
    } catch (_) {
      _rejectInvitation = null;
    }

    try {
      _expireInvitation = _lib
          .lookup<NativeFunction<HivraExpireInvitationC>>('hivra_expire_invitation')
          .asFunction();
    } catch (_) {
      _expireInvitation = null;
    }

    _exportLedger = _lib
        .lookup<NativeFunction<HivraExportLedgerC>>('hivra_export_ledger')
        .asFunction();

    _importLedger = _lib
        .lookup<NativeFunction<HivraImportLedgerC>>('hivra_import_ledger')
        .asFunction();

    _ledgerAppendEvent = _lib
        .lookup<NativeFunction<HivraLedgerAppendEventC>>('hivra_ledger_append_event')
        .asFunction();

    try {
      _nostrSendPreparedSelfCheck = _lib
          .lookup<NativeFunction<HivraNostrSendPreparedSelfCheckC>>('hivra_nostr_send_prepared_self_check')
          .asFunction();
    } catch (_) {
      _nostrSendPreparedSelfCheck = null;
    }
  }

  // Alias for seedExists for compatibility
  bool initSeed() => _seedExists() != 0;
  
  // Alias for capsulePublicKey for compatibility
  Uint8List? publicKey() => capsulePublicKey();

  bool seedExists() => _seedExists() != 0;
  
  bool saveSeed(Uint8List seed) {
    if (seed.length != 32) return false;
    final seedPtr = calloc<Uint8>(32);
    try {
      final seedNative = seedPtr.asTypedList(32);
      seedNative.setAll(0, seed);
      return _seedSave(seedPtr) == 0;
    } finally {
      calloc.free(seedPtr);
    }
  }

  Uint8List? seedPublicKey(Uint8List seed) {
    if (seed.length != 32) return null;
    final seedPtr = calloc<Uint8>(32);
    final outPtr = calloc<Uint8>(32);
    try {
      seedPtr.asTypedList(32).setAll(0, seed);
      final result = _seedPublicKey(seedPtr, outPtr);
      if (result != 0) return null;
      final key = Uint8List(32);
      key.setAll(0, outPtr.asTypedList(32));
      return key;
    } finally {
      calloc.free(seedPtr);
      calloc.free(outPtr);
    }
  }

  Uint8List? loadSeed() {
    final outPtr = calloc<Uint8>(32);
    try {
      final result = _seedLoad(outPtr);
      if (result != 0) return null;
      final seed = Uint8List(32);
      final seedNative = outPtr.asTypedList(32);
      seed.setAll(0, seedNative);
      return seed;
    } finally {
      calloc.free(outPtr);
    }
  }

  bool deleteSeed() => _seedDelete() == 0;

  bool createCapsule(Uint8List seed, {bool isNeste = true, bool isGenesis = false}) {
    if (seed.length != 32) return false;
    final seedPtr = calloc<Uint8>(32);
    try {
      final seedNative = seedPtr.asTypedList(32);
      seedNative.setAll(0, seed);
      final network = isNeste ? 1 : 0;
      final capsuleType = isGenesis ? 1 : 0;
      return _capsuleCreate(seedPtr, network, capsuleType) == 0;
    } finally {
      calloc.free(seedPtr);
    }
  }

  Uint8List? capsulePublicKey() {
    final outPtr = calloc<Uint8>(32);
    try {
      final result = _capsulePublicKey(outPtr);
      if (result != 0) return null;
      final key = Uint8List(32);
      final keyNative = outPtr.asTypedList(32);
      key.setAll(0, keyNative);
      return key;
    } finally {
      calloc.free(outPtr);
    }
  }

  bool resetCapsule() => _capsuleReset() == 0;

  Uint8List? getStarterId(int slot) {
    if (slot < 0 || slot > 4) return null;
    final outPtr = calloc<Uint8>(32);
    try {
      final result = _starterGetId(slot, outPtr);
      if (result != 0) return null;
      final id = Uint8List(32);
      final idNative = outPtr.asTypedList(32);
      id.setAll(0, idNative);
      return id;
    } finally {
      calloc.free(outPtr);
    }
  }

  String getStarterType(int slot) {
    final typeIndex = _starterGetType(slot);
    switch (typeIndex) {
      case 0: return 'Juice';
      case 1: return 'Spark';
      case 2: return 'Seed';
      case 3: return 'Pulse';
      case 4: return 'Kick';
      default: return 'Unknown';
    }
  }

  bool starterExists(int slot) => _starterExists(slot) != 0;

  bool sendInvitation(Uint8List toPubkey, int starterSlot) {
    if (toPubkey.length != 32 || starterSlot < 0 || starterSlot > 4) return false;
    final toPtr = calloc<Uint8>(32);
    try {
      final sendInvitationFn = _sendInvitation;
      if (sendInvitationFn == null) {
        return false;
      }
      toPtr.asTypedList(32).setAll(0, toPubkey);
      return sendInvitationFn(toPtr, starterSlot) == 0;
    } finally {
      calloc.free(toPtr);
    }
  }

  int receiveTransportMessages() => _transportReceive?.call() ?? -1002;

  int acceptInvitationCode(Uint8List invitationId, Uint8List fromPubkey, Uint8List createdStarterId) {
    if (invitationId.length != 32 || fromPubkey.length != 32 || createdStarterId.length != 32) {
      return -1;
    }
    final invitationIdPtr = calloc<Uint8>(32);
    final fromPubkeyPtr = calloc<Uint8>(32);
    final createdStarterIdPtr = calloc<Uint8>(32);
    try {
      final acceptInvitationFn = _acceptInvitation;
      if (acceptInvitationFn == null) {
        return -1002;
      }
      invitationIdPtr.asTypedList(32).setAll(0, invitationId);
      fromPubkeyPtr.asTypedList(32).setAll(0, fromPubkey);
      createdStarterIdPtr.asTypedList(32).setAll(0, createdStarterId);
      return acceptInvitationFn(invitationIdPtr, fromPubkeyPtr, createdStarterIdPtr);
    } finally {
      calloc.free(invitationIdPtr);
      calloc.free(fromPubkeyPtr);
      calloc.free(createdStarterIdPtr);
    }
  }

  bool acceptInvitation(Uint8List invitationId, Uint8List fromPubkey, Uint8List createdStarterId) {
    return acceptInvitationCode(invitationId, fromPubkey, createdStarterId) == 0;
  }

  bool rejectInvitation(Uint8List invitationId, int reason) {
    if (invitationId.length != 32) return false;
    final invitationIdPtr = calloc<Uint8>(32);
    try {
      final rejectInvitationFn = _rejectInvitation;
      if (rejectInvitationFn == null) {
        return false;
      }
      invitationIdPtr.asTypedList(32).setAll(0, invitationId);
      return rejectInvitationFn(invitationIdPtr, reason) == 0;
    } finally {
      calloc.free(invitationIdPtr);
    }
  }

  bool expireInvitation(Uint8List invitationId) {
    if (invitationId.length != 32) return false;
    final invitationIdPtr = calloc<Uint8>(32);
    try {
      final expireInvitationFn = _expireInvitation;
      if (expireInvitationFn == null) {
        return false;
      }
      invitationIdPtr.asTypedList(32).setAll(0, invitationId);
      return expireInvitationFn(invitationIdPtr) == 0;
    } finally {
      calloc.free(invitationIdPtr);
    }
  }

  int nostrSendPreparedSelfCheck() => _nostrSendPreparedSelfCheck?.call() ?? -1001;

  String? exportLedger() {
    final outPtr = calloc<Pointer<Int8>>();
    try {
      if (_exportLedger(outPtr) != 0) return null;
      final cstr = outPtr.value;
      if (cstr == nullptr) return null;
      final json = cstr.cast<Utf8>().toDartString();
      _freeString(cstr);
      return json;
    } finally {
      calloc.free(outPtr);
    }
  }

  bool importLedger(String json) {
    final jsonPtr = json.toNativeUtf8();
    try {
      return _importLedger(jsonPtr.cast<Int8>()) == 0;
    } finally {
      calloc.free(jsonPtr);
    }
  }

  bool ledgerAppendEvent(int kind, Uint8List payload) {
    final payloadPtr = calloc<Uint8>(payload.length);
    try {
      if (payload.isNotEmpty) {
        payloadPtr.asTypedList(payload.length).setAll(0, payload);
      }
      return _ledgerAppendEvent(kind, payloadPtr, payload.length) == 0;
    } finally {
      calloc.free(payloadPtr);
    }
  }

  String seedToMnemonic(Uint8List seed, {int wordCount = 24}) {
    if (seed.length != 32) throw ArgumentError('Seed must be 32 bytes');
    final seedPtr = calloc<Uint8>(32);
    final outPhrasePtr = calloc<Pointer<Int8>>();
    try {
      final seedNative = seedPtr.asTypedList(32);
      seedNative.setAll(0, seed);
      final result = _seedToMnemonic(seedPtr, wordCount, outPhrasePtr);
      if (result != 0) throw Exception('Failed to convert seed (code: $result)');
      final phraseCStr = outPhrasePtr.value;
      if (phraseCStr == nullptr) throw Exception('Null phrase');
      final phrase = phraseCStr.cast<Utf8>().toDartString();
      _freeString(phraseCStr);
      return phrase;
    } finally {
      calloc.free(seedPtr);
      calloc.free(outPhrasePtr);
    }
  }

  Uint8List mnemonicToSeed(String phrase) {
    final phraseCStr = phrase.toNativeUtf8();
    final seedPtr = calloc<Uint8>(32);
    try {
      final result = _mnemonicToSeed(phraseCStr as Pointer<Int8>, seedPtr);
      if (result != 0) throw Exception('Failed to convert mnemonic (code: $result)');
      final seed = Uint8List(32);
      final seedNative = seedPtr.asTypedList(32);
      seed.setAll(0, seedNative);
      return seed;
    } finally {
      calloc.free(phraseCStr);
      calloc.free(seedPtr);
    }
  }

  bool validateMnemonic(String phrase) {
    try {
      mnemonicToSeed(phrase);
      return true;
    } catch (_) {
      return false;
    }
  }

  Uint8List generateRandomSeed() {
    final seedPtr = calloc<Uint8>(32);
    try {
      final result = _generateRandomSeed(seedPtr);
      if (result != 0) throw Exception('Failed to generate seed (code: $result)');
      final seed = Uint8List(32);
      final seedNative = seedPtr.asTypedList(32);
      seed.setAll(0, seedNative);
      return seed;
    } finally {
      calloc.free(seedPtr);
    }
  }
}
