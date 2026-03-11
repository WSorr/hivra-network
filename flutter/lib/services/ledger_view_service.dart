import 'dart:typed_data';

import '../ffi/hivra_bindings.dart';
import '../models/invitation.dart';
import '../models/relationship.dart';
import 'capsule_ledger_snapshot.dart';
import 'invitation_projection_service.dart';
import 'ledger_view_support.dart';
import 'relationship_projection_service.dart';

class LedgerViewService {
  final HivraBindings _hivra;
  final LedgerViewSupport _support;
  late final InvitationProjectionService _invitationProjection;
  late final RelationshipProjectionService _relationshipProjection;

  LedgerViewService(this._hivra) : _support = const LedgerViewSupport() {
    _invitationProjection = InvitationProjectionService(_hivra, _support);
    _relationshipProjection = RelationshipProjectionService(_support);
  }

  CapsuleLedgerSnapshot loadCapsuleSnapshot() {
    final root = _exportLedgerRoot();
    final pubKey = _hivra.capsulePublicKey() ?? Uint8List(0);

    var starterCount = 0;
    final starterIds = List<Uint8List?>.filled(5, null);
    final starterKinds = List<String?>.filled(5, null);
    for (var i = 0; i < 5; i++) {
      if (!_hivra.starterExists(i)) continue;
      final starter = _hivra.getStarterId(i);
      if (starter == null) continue;
      starterIds[i] = starter;
      starterKinds[i] = _hivra.getStarterType(i);
      starterCount++;
    }

    if (root == null) {
      return CapsuleLedgerSnapshot(
        publicKey: pubKey,
        starterCount: starterCount,
        relationshipCount: 0,
        pendingInvitations: 0,
        version: 0,
        ledgerHashHex: '0',
        starterIds: starterIds,
        starterKinds: starterKinds,
        lockedStarterSlots: const <int>{},
      );
    }

    final version = _support.events(root).length;
    final rawHash = root['last_hash'];
    final hashHex = rawHash == null ? '0' : rawHash.toString();

    final relationships = loadRelationships();
    final invitations = loadInvitations();
    final pendingInvitations = invitations
        .where((invitation) => invitation.status == InvitationStatus.pending)
        .length;
    final lockedStarterSlots = invitations
        .where((invitation) =>
            invitation.status == InvitationStatus.pending &&
            invitation.starterSlot != null)
        .map((invitation) => invitation.starterSlot!)
        .toSet();

    return CapsuleLedgerSnapshot(
      publicKey: pubKey,
      starterCount: starterCount,
      relationshipCount:
          relationships.where((relationship) => relationship.isActive).length,
      pendingInvitations: pendingInvitations,
      version: version,
      ledgerHashHex: hashHex,
      starterIds: starterIds,
      starterKinds: starterKinds,
      lockedStarterSlots: lockedStarterSlots,
    );
  }

  List<Invitation> loadInvitations() {
    final root = _exportLedgerRoot();
    if (root == null) return <Invitation>[];
    return _invitationProjection.loadInvitations(root);
  }

  List<Relationship> loadRelationships() {
    final root = _exportLedgerRoot();
    if (root == null) return <Relationship>[];
    return _relationshipProjection.loadRelationships(root);
  }

  Map<String, dynamic>? _exportLedgerRoot() {
    return _support.exportLedgerRoot(_hivra.exportLedger());
  }
}
