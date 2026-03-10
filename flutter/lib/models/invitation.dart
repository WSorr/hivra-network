import 'package:flutter/material.dart';
import 'starter.dart';

enum InvitationStatus {
  pending('Pending', Colors.orange),
  accepted('Accepted', Colors.green),
  rejected('Rejected', Colors.red),
  expired('Expired', Colors.grey);

  const InvitationStatus(this.displayName, this.color);
  final String displayName;
  final Color color;
}

enum RejectionReason {
  emptySlot('Empty slot - starter burned'),
  other('Declined');

  const RejectionReason(this.displayName);
  final String displayName;
}

class Invitation {
  final String id;
  final String fromPubkey;
  final String? toPubkey; // null if incoming
  final StarterKind kind;
  final int? starterSlot; // which slot is locked
  final InvitationStatus status;
  final DateTime sentAt;
  final DateTime? expiresAt;
  final DateTime? respondedAt;
  final RejectionReason? rejectionReason;

  Invitation({
    required this.id,
    required this.fromPubkey,
    this.toPubkey,
    required this.kind,
    this.starterSlot,
    required this.status,
    required this.sentAt,
    this.expiresAt,
    this.respondedAt,
    this.rejectionReason,
  });

  bool get isIncoming => toPubkey == null;
  bool get isOutgoing => toPubkey != null;
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  // Mock data for testing
  static List<Invitation> mock() {
    return [
      Invitation(
        id: 'inv1',
        fromPubkey: '0x1234...5678',
        toPubkey: null, // incoming
        kind: StarterKind.juice,
        status: InvitationStatus.pending,
        sentAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().add(const Duration(hours: 22)),
      ),
      Invitation(
        id: 'inv2',
        fromPubkey: '0x8765...4321',
        toPubkey: '0xAA...', // outgoing
        kind: StarterKind.spark,
        starterSlot: 1,
        status: InvitationStatus.pending,
        sentAt: DateTime.now().subtract(const Duration(hours: 5)),
        expiresAt: DateTime.now().add(const Duration(hours: 19)),
      ),
      Invitation(
        id: 'inv3',
        fromPubkey: '0x2468...1357',
        toPubkey: null,
        kind: StarterKind.seed,
        status: InvitationStatus.accepted,
        sentAt: DateTime.now().subtract(const Duration(days: 2)),
        respondedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Invitation(
        id: 'inv4',
        fromPubkey: '0x1357...2468',
        toPubkey: null,
        kind: StarterKind.pulse,
        status: InvitationStatus.rejected,
        rejectionReason: RejectionReason.emptySlot,
        sentAt: DateTime.now().subtract(const Duration(days: 3)),
        respondedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];
  }
}
