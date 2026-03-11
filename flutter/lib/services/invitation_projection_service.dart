import 'dart:convert';
import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import '../models/invitation.dart';
import '../models/starter.dart';
import 'ledger_view_support.dart';

class InvitationProjectionService {
  final HivraBindings _hivra;
  final LedgerViewSupport _support;

  const InvitationProjectionService(this._hivra, this._support);

  List<Invitation> loadInvitations(Map<String, dynamic> root) {
    final events = _support.events(root);
    final self = _hivra.capsulePublicKey();
    if (self == null) return <Invitation>[];

    final starterKinds = <String, StarterKind>{};
    for (final e in events) {
      if (_support.kindCode(e['kind']) != 5) continue;
      final payload = _support.payloadBytes(e['payload']);
      if (payload.length != 66) continue;
      starterKinds[base64.encode(payload.sublist(0, 32))] =
          _support.starterKindFromByte(payload[64]);
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
      final kind = _support.kindCode(e['kind']);
      final timestamp = _support.eventTime(e['timestamp']);
      final payload = _support.payloadBytes(e['payload']);
      final signer = _support.bytes32(e['signer']);

      if (kind == 1 && (payload.length == 96 || payload.length == 97)) {
        final invitationId = payload.sublist(0, 32);
        final starterId = payload.sublist(32, 64);
        final toPubkey = payload.sublist(64, 96);

        final hasKindByte = payload.length == 97;
        final kindFromPayload =
            hasKindByte ? _support.starterKindFromByte(payload[96]) : null;

        final id = base64.encode(invitationId);
        final current = byId[id];
        final starterSlot =
            _support.slotForStarterId(starterId, ownStarterBySlot);
        final isIncomingByAddress = _support.eq32(toPubkey, self);
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
          fromPubkey: base64.encode(signer),
          toPubkey:
              isIncoming ? null : (current?.toPubkey ?? base64.encode(toPubkey)),
          kind: kindFromPayload ??
              starterKinds[base64.encode(starterId)] ??
              StarterKind.juice,
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
        final reason =
            payload[32] == 0 ? RejectionReason.emptySlot : RejectionReason.other;
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
}
