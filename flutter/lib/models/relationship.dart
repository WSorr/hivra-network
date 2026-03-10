import 'starter.dart';

/// Relationship between two capsules
class Relationship {
  final String peerPubkey;
  final StarterKind kind;
  final String ownStarterId;
  final String peerStarterId;
  final DateTime establishedAt;
  final bool isActive;

  Relationship({
    required this.peerPubkey,
    required this.kind,
    required this.ownStarterId,
    required this.peerStarterId,
    required this.establishedAt,
    this.isActive = true,
  });

  /// Get display name for peer (safe short preview)
  String get peerDisplayName {
    if (peerPubkey.isEmpty) return 'Unknown';
    if (peerPubkey.length <= 8) return peerPubkey;
    return '${peerPubkey.substring(0, 8)}...';
  }

  /// For mock data
  static Relationship mock(int index) {
    final kinds = StarterKind.values;
    return Relationship(
      peerPubkey: '0x$index' '234567890123456789012345678901234567890123456789',
      kind: kinds[index % kinds.length],
      ownStarterId: 'starter_$index',
      peerStarterId: 'peer_starter_$index',
      establishedAt: DateTime.now().subtract(Duration(days: index)),
      isActive: index % 3 != 0, // every 3rd is broken
    );
  }
}
