import 'dart:convert';
import 'dart:typed_data';
import '../ffi/hivra_bindings.dart';

class CapsuleState {
  final Uint8List publicKey;
  final int starterCount;
  final int relationshipCount;
  final int pendingInvitations;
  final int version;
  final String ledgerHashHex;
  final bool isNeste;
  final List<Uint8List?> starterIds;

  CapsuleState({
    required this.publicKey,
    required this.starterCount,
    required this.relationshipCount,
    required this.pendingInvitations,
    required this.version,
    required this.ledgerHashHex,
    required this.isNeste,
    required this.starterIds,
  });

  List<StarterSlotState> get starterSlots {
    return List<StarterSlotState>.generate(5, (i) {
      final id = i < starterIds.length ? starterIds[i] : null;
      return StarterSlotState(
        occupied: id != null,
        kind: _starterKindName(i),
        starterId: id,
      );
    });
  }

  static String _starterKindName(int index) {
    switch (index) {
      case 0:
        return 'Juice';
      case 1:
        return 'Spark';
      case 2:
        return 'Seed';
      case 3:
        return 'Pulse';
      case 4:
        return 'Kick';
      default:
        return 'Unknown';
    }
  }

  factory CapsuleState.fromHivra(HivraBindings hivra) {
    List<Uint8List?> starters = List.filled(5, null);
    int count = 0;
    
    for (int i = 0; i < 5; i++) {
      if (!hivra.starterExists(i)) continue;
      final starter = hivra.getStarterId(i);
      if (starter == null) continue;
      starters[i] = starter;
      count++;
    }

    final pubKey = hivra.capsulePublicKey() ?? Uint8List(0);
    final ledger = _parseLedger(hivra.exportLedger());

    return CapsuleState(
      publicKey: pubKey,
      starterCount: count,
      relationshipCount: ledger.relationshipCount,
      pendingInvitations: ledger.pendingInvitations,
      version: ledger.version,
      ledgerHashHex: ledger.hashHex,
      isNeste: true, // Will come from settings
      starterIds: starters,
    );
  }

  static _LedgerInfo _parseLedger(String? json) {
    if (json == null || json.isEmpty) {
      return const _LedgerInfo(version: 0, hashHex: '0', relationshipCount: 0, pendingInvitations: 0);
    }

    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) {
        return const _LedgerInfo(version: 0, hashHex: '0', relationshipCount: 0, pendingInvitations: 0);
      }

      final rawHash = decoded['last_hash'];
      final hashHex = rawHash == null ? '0' : rawHash.toString();
      final eventsRaw = decoded['events'];
      final events = eventsRaw is List ? eventsRaw : const [];
      final version = events.length;

      final pending = <String>{};
      final relActive = <String>{};
      for (final item in events) {
        if (item is! Map) continue;
        final kind = _kindCode(item['kind']);
        final payload = _payload(item['payload']);
        if (kind == 1 && payload.length == 96) {
          pending.add(base64.encode(payload.sublist(0, 32)));
        } else if ((kind == 2 && payload.length == 96) || (kind == 3 && payload.length == 33) || (kind == 4 && payload.length == 32)) {
          pending.remove(base64.encode(payload.sublist(0, 32)));
        } else if (kind == 7 && payload.length == 97) {
          relActive.add('${base64.encode(payload.sublist(0, 32))}:${base64.encode(payload.sublist(32, 64))}');
        } else if (kind == 8 && payload.length == 64) {
          relActive.remove('${base64.encode(payload.sublist(0, 32))}:${base64.encode(payload.sublist(32, 64))}');
        }
      }

      return _LedgerInfo(
        version: version,
        hashHex: hashHex,
        relationshipCount: relActive.length,
        pendingInvitations: pending.length,
      );
    } catch (_) {
      return const _LedgerInfo(version: 0, hashHex: '0', relationshipCount: 0, pendingInvitations: 0);
    }
  }

  static int _kindCode(dynamic kind) {
    if (kind is int) return kind;
    if (kind is String) {
      switch (kind) {
        case 'InvitationSent':
          return 1;
        case 'InvitationAccepted':
          return 2;
        case 'InvitationRejected':
          return 3;
        case 'InvitationExpired':
          return 4;
        case 'RelationshipEstablished':
          return 7;
        case 'RelationshipBroken':
          return 8;
      }
    }
    return -1;
  }

  static Uint8List _payload(dynamic payload) {
    if (payload is List) {
      return Uint8List.fromList(payload.whereType<num>().map((v) => v.toInt()).toList());
    }
    if (payload is String) {
      try {
        return Uint8List.fromList(base64.decode(payload));
      } catch (_) {
        return Uint8List(0);
      }
    }
    return Uint8List(0);
  }
}

class _LedgerInfo {
  final int version;
  final String hashHex;
  final int relationshipCount;
  final int pendingInvitations;

  const _LedgerInfo({
    required this.version,
    required this.hashHex,
    required this.relationshipCount,
    required this.pendingInvitations,
  });
}

class StarterSlotState {
  final bool occupied;
  final String kind;
  final Uint8List? starterId;

  const StarterSlotState({
    required this.occupied,
    required this.kind,
    required this.starterId,
  });
}

class CapsuleStateManager {
  final HivraBindings _hivra;
  CapsuleState? _currentState;

  CapsuleStateManager(this._hivra);

  CapsuleState get state {
    _currentState ??= CapsuleState.fromHivra(_hivra);
    return _currentState!;
  }

  void refresh() {
    _currentState = CapsuleState.fromHivra(_hivra);
  }

  // Will be used by our new FFI function
  void refreshWithFullState() {
    // TODO: Call capsule_state_encode when ready
    refresh(); // Fallback to old method for now
  }
}
