import 'dart:ffi';
import 'dart:typed_data';

// Using @Native annotation for Dart 3+
@Native<Pointer<FfiBytes> Function(Pointer<Void>)>(symbol: 'capsule_state_encode')
external Pointer<FfiBytes> capsuleStateEncode(Pointer<Void> capsulePtr);

@Native<Void Function(Pointer<Uint8>, IntPtr)>(symbol: 'free_bytes')
external void freeBytes(Pointer<Uint8> ptr, int len);

final class FfiBytes extends Struct {
  external Pointer<Uint8> data;

  @IntPtr()
  external int len;
}

class CapsuleState {
  final Uint8List publicKey;
  final int capsuleType;
  final int network;
  final List<Uint8List?> slots;
  final int ledgerHash;
  final int relationshipsCount;
  final int version;

  CapsuleState({
    required this.publicKey,
    required this.capsuleType,
    required this.network,
    required this.slots,
    required this.ledgerHash,
    required this.relationshipsCount,
    required this.version,
  });

  factory CapsuleState.fromBytes(Uint8List bytes) {
    // TODO: Implement real deserialization
    return CapsuleState(
      publicKey: Uint8List(32),
      capsuleType: 0,
      network: 0,
      slots: List.filled(5, null),
      ledgerHash: 0,
      relationshipsCount: 0,
      version: 1,
    );
  }

  bool get isRelay => capsuleType == 1;
  bool get isNeste => network == 1;
  bool get isHood => network == 0;
}

class CapsuleService {
  static final CapsuleService _instance = CapsuleService._internal();
  factory CapsuleService() => _instance;
  CapsuleService._internal();

  static bool _initialized = false;

  static void init(DynamicLibrary lib) {
    _initialized = true;
  }

  CapsuleState getCapsuleState(Pointer<Void> capsulePtr) {
    if (!_initialized) {
      return CapsuleState(
        publicKey: Uint8List(32),
        capsuleType: 0,
        network: 0,
        slots: List.filled(5, null),
        ledgerHash: 0,
        relationshipsCount: 0,
        version: 1,
      );
    }

    try {
      final resultPtr = capsuleStateEncode(capsulePtr);
      if (resultPtr == nullptr) {
        throw Exception('Failed to encode capsule state');
      }

      final ffiBytes = resultPtr.ref;
      final data = ffiBytes.data.asTypedList(ffiBytes.len);
      freeBytes(ffiBytes.data, ffiBytes.len);
      
      return CapsuleState.fromBytes(data);
    } catch (e) {
      print('Error getting capsule state: $e');
      rethrow;
    }
  }
}
