import 'dart:typed_data';

class CapsuleLedgerSnapshot {
  final Uint8List publicKey;
  final int starterCount;
  final int relationshipCount;
  final int pendingInvitations;
  final int version;
  final String ledgerHashHex;
  final List<Uint8List?> starterIds;
  final List<String?> starterKinds;
  final Set<int> lockedStarterSlots;

  const CapsuleLedgerSnapshot({
    required this.publicKey,
    required this.starterCount,
    required this.relationshipCount,
    required this.pendingInvitations,
    required this.version,
    required this.ledgerHashHex,
    required this.starterIds,
    required this.starterKinds,
    required this.lockedStarterSlots,
  });
}
