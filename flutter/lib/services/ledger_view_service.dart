import 'dart:convert';
import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import '../models/invitation.dart';
import '../models/relationship.dart';
import '../models/starter.dart';

class LedgerViewService {
  final HivraBindings _hivra;

  LedgerViewService(this._hivra);

  List<Invitation> loadInvitations() {
    final root = _exportLedgerRoot();
    if (root == null) return <Invitation>[];
    final events = _events(root);
    final self = _hivra.capsulePublicKey();
    if (self == null) return <Invitation>[];

    final starterKinds = <String, StarterKind>{};
    for (final e in events) {
      if (_kindCode(e['kind']) != 5) continue;
      final payload = _payloadBytes(e['payload']);
      if (payload.length != 66) continue;
      starterKinds[base64.encode(payload.sublist(0, 32))] = _starterKindFromByte(payload[64]);
    }

    final ownStarterBySlot = <int, Uint8List>{};
    for (var i = 0; i < 5; i++) {
      final id = _hivra.getStarterId(i);
      if (id != null) ownStarterBySlot[i] = id;
    }

    final byId = <String, Invitation>{};
    final acceptedAtById = <String, DateTime>{};
    final rejectedById = <String, ({DateTime at, RejectionReason reason})>{};
    final expiredAtById = <String, DateTime>{};

    for (final e in events) {
      final kind = _kindCode(e['kind']);
      final timestamp = _eventTime(e['timestamp']);
      final payload = _payloadBytes(e['payload']);
      final signer = _bytes32(e['signer']);

      if (kind == 1 && (payload.length == 96 || payload.length == 97)) {
        final invitationId = payload.sublist(0, 32);
        final starterId = payload.sublist(32, 64);
        final toPubkey = payload.sublist(64, 96);

        final hasKindByte = payload.length == 97;
        final kindFromPayload = hasKindByte ? _starterKindFromByte(payload[96]) : null;

        final fromPubkey = signer;

        final id = base64.encode(invitationId);
        final current = byId[id];
        final starterSlot = _slotForStarterId(starterId, ownStarterBySlot);
        // Direction must be derived from the addressed capsule first.
        // Signer can be local for replayed/projected ledger events, so treating
        // `from == self` as proof of outgoing causes recipient-side invitations
        // to render as if they were sent by the current capsule.
        final isIncomingByAddress = _eq32(toPubkey, self);
        // Prefer incoming when an explicitly addressed record proves the
        // invitation belongs to the local capsule. This avoids getting stuck
        // with an outgoing projection when the same invitation id later arrives
        // from transport.
        final isIncoming = isIncomingByAddress || (current?.isIncoming ?? false);

        final expiresAt = timestamp.add(const Duration(hours: 24));
        InvitationStatus status = InvitationStatus.pending;
        DateTime? respondedAt;
        RejectionReason? rejectionReason;

        if (acceptedAtById.containsKey(id)) {
          status = InvitationStatus.accepted;
          respondedAt = acceptedAtById[id];
        } else if (rejectedById.containsKey(id)) {
          status = InvitationStatus.rejected;
          respondedAt = rejectedById[id]!.at;
          rejectionReason = rejectedById[id]!.reason;
        } else if (expiredAtById.containsKey(id)) {
          status = InvitationStatus.expired;
          respondedAt = expiredAtById[id];
        } else if (expiresAt.isBefore(DateTime.now())) {
          status = InvitationStatus.expired;
          respondedAt = expiresAt;
        }

        byId[id] = Invitation(
          id: id,
          fromPubkey: base64.encode(fromPubkey),
          toPubkey: isIncoming ? null : (current?.toPubkey ?? base64.encode(toPubkey)),
          kind: kindFromPayload ?? starterKinds[base64.encode(starterId)] ?? StarterKind.juice,
          starterSlot: isIncoming ? null : (current?.starterSlot ?? starterSlot),
          status: status,
          sentAt: timestamp,
          expiresAt: expiresAt,
          respondedAt: respondedAt,
          rejectionReason: rejectionReason,
        );
      } else if (kind == 2 && payload.length == 96) {
        final id = base64.encode(payload.sublist(0, 32));
        acceptedAtById[id] = timestamp;
        final current = byId[id];
        if (current != null) {
          byId[id] = Invitation(
            id: current.id,
            fromPubkey: current.fromPubkey,
            toPubkey: current.toPubkey,
            kind: current.kind,
            starterSlot: current.starterSlot,
            status: InvitationStatus.accepted,
            sentAt: current.sentAt,
            expiresAt: current.expiresAt,
            respondedAt: timestamp,
          );
        }
      } else if (kind == 3 && payload.length == 33) {
        final id = base64.encode(payload.sublist(0, 32));
        final reason = payload[32] == 0 ? RejectionReason.emptySlot : RejectionReason.other;
        rejectedById[id] = (at: timestamp, reason: reason);
        final current = byId[id];
        if (current != null) {
          byId[id] = Invitation(
            id: current.id,
            fromPubkey: current.fromPubkey,
            toPubkey: current.toPubkey,
            kind: current.kind,
            starterSlot: current.starterSlot,
            status: InvitationStatus.rejected,
            sentAt: current.sentAt,
            expiresAt: current.expiresAt,
            respondedAt: timestamp,
            rejectionReason: reason,
          );
        }
      } else if (kind == 4 && payload.length == 32) {
        final id = base64.encode(payload.sublist(0, 32));
        expiredAtById[id] = timestamp;
        final current = byId[id];
        if (current != null) {
          byId[id] = Invitation(
            id: current.id,
            fromPubkey: current.fromPubkey,
            toPubkey: current.toPubkey,
            kind: current.kind,
            starterSlot: current.starterSlot,
            status: InvitationStatus.expired,
            sentAt: current.sentAt,
            expiresAt: current.expiresAt,
            respondedAt: timestamp,
          );
        }
      }
    }

    final list = byId.values.toList();
    list.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return list;
  }

  List<Relationship> loadRelationships() {
    final root = _exportLedgerRoot();
    if (root == null) return <Relationship>[];
    final events = _events(root);

    final byKey = <String, Relationship>{};
    for (final e in events) {
      final kind = _kindCode(e['kind']);
      final payload = _payloadBytes(e['payload']);
      final timestamp = _eventTime(e['timestamp']);
      if (kind == 7 && payload.length == 97) {
        final key = '${base64.encode(payload.sublist(0, 32))}:${base64.encode(payload.sublist(32, 64))}';
        byKey[key] = Relationship(
          peerPubkey: base64.encode(payload.sublist(0, 32)),
          kind: _starterKindFromByte(payload[96]),
          ownStarterId: base64.encode(payload.sublist(32, 64)),
          peerStarterId: base64.encode(payload.sublist(64, 96)),
          establishedAt: timestamp,
          isActive: true,
        );
      } else if (kind == 8 && payload.length == 64) {
        final key = '${base64.encode(payload.sublist(0, 32))}:${base64.encode(payload.sublist(32, 64))}';
        final current = byKey[key];
        if (current != null) {
          byKey[key] = Relationship(
            peerPubkey: current.peerPubkey,
            kind: current.kind,
            ownStarterId: current.ownStarterId,
            peerStarterId: current.peerStarterId,
            establishedAt: current.establishedAt,
            isActive: false,
          );
        }
      }
    }

    final list = byKey.values.toList();
    list.sort((a, b) => b.establishedAt.compareTo(a.establishedAt));
    return list;
  }

  Map<String, dynamic>? _exportLedgerRoot() {
    final json = _hivra.exportLedger();
    if (json == null || json.isEmpty) return null;
    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  List<dynamic> _events(Map<String, dynamic> root) {
    final events = root['events'];
    return events is List ? events : const <dynamic>[];
  }

  int _kindCode(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      switch (value) {
        case 'CapsuleCreated':
          return 0;
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
      }
    }
    return -1;
  }

  DateTime _eventTime(dynamic ts) {
    if (ts is! num) return DateTime.now();

    final raw = ts.toInt();
    if (raw <= 0) return DateTime.now();

    // Accept both unix seconds (10 digits) and unix milliseconds (13 digits).
    final millis = raw < 100000000000 ? raw * 1000 : raw;

    try {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return DateTime.now();
    }
  }

  Uint8List _payloadBytes(dynamic payload) {
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

  Uint8List _bytes32(dynamic value) {
    if (value is List && value.length == 32) {
      return Uint8List.fromList(value.whereType<num>().map((v) => v.toInt()).toList());
    }
    final bytes = _payloadBytes(value);
    return bytes.length == 32 ? bytes : Uint8List(32);
  }

  bool _eq32(Uint8List a, Uint8List b) {
    if (a.length != 32 || b.length != 32) return false;
    for (var i = 0; i < 32; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int? _slotForStarterId(Uint8List starterId, Map<int, Uint8List> slotToId) {
    for (final entry in slotToId.entries) {
      if (_eq32(starterId, entry.value)) return entry.key;
    }
    return null;
  }

  StarterKind _starterKindFromByte(int value) {
    switch (value) {
      case 0:
        return StarterKind.juice;
      case 1:
        return StarterKind.spark;
      case 2:
        return StarterKind.seed;
      case 3:
        return StarterKind.pulse;
      case 4:
        return StarterKind.kick;
      default:
        return StarterKind.juice;
    }
  }
}
