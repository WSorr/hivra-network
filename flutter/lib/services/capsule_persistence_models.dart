import 'dart:typed_data';

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
