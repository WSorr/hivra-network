import 'dart:convert';

import '../models/relationship.dart';
import 'ledger_view_support.dart';

class RelationshipProjectionService {
  final LedgerViewSupport _support;

  const RelationshipProjectionService(this._support);

  List<Relationship> loadRelationships(Map<String, dynamic> root) {
    final events = _support.events(root);
    final byKey = <String, Relationship>{};

    for (final e in events) {
      final kind = _support.kindCode(e['kind']);
      final payload = _support.payloadBytes(e['payload']);
      final timestamp = _support.eventTime(e['timestamp']);
      if (kind == 7 && payload.length == 97) {
        final key =
            '${base64.encode(payload.sublist(0, 32))}:${base64.encode(payload.sublist(32, 64))}';
        byKey[key] = Relationship(
          peerPubkey: base64.encode(payload.sublist(0, 32)),
          kind: _support.starterKindFromByte(payload[96]),
          ownStarterId: base64.encode(payload.sublist(32, 64)),
          peerStarterId: base64.encode(payload.sublist(64, 96)),
          establishedAt: timestamp,
          isActive: true,
        );
      } else if (kind == 8 && payload.length == 64) {
        final key =
            '${base64.encode(payload.sublist(0, 32))}:${base64.encode(payload.sublist(32, 64))}';
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
}
