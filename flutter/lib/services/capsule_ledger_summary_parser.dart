import 'dart:convert';
import 'dart:typed_data';

import 'capsule_persistence_models.dart';

class CapsuleLedgerSummaryParser {
  const CapsuleLedgerSummaryParser();

  CapsuleLedgerSummary parse(String json, String Function(Uint8List bytes) toHex) {
    if (json.trim().isEmpty) return CapsuleLedgerSummary.empty();
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return CapsuleLedgerSummary.empty();
      final ledger = Map<String, dynamic>.from(decoded);
      final eventsRaw = ledger['events'];
      final events = eventsRaw is List ? eventsRaw : const [];

      int relationshipEstablished = 0;
      int relationshipBroken = 0;
      int invitationSent = 0;
      int invitationResolved = 0;
      final activeStartersById = <String, int>{};

      for (final eventRaw in events) {
        if (eventRaw is! Map) continue;
        final event = Map<String, dynamic>.from(eventRaw);
        final kind = _eventKindCode(event['kind']);

        switch (kind) {
          case 1:
            invitationSent++;
            break;
          case 2:
          case 3:
          case 4:
            invitationResolved++;
            break;
          case 5:
            final payload = parseBytesField(event['payload']);
            final starter = _parseStarterCreated(payload);
            if (starter != null) {
              activeStartersById[toHex(Uint8List.fromList(starter.starterId))] =
                  starter.kindCode;
            }
            break;
          case 6:
            final payload = parseBytesField(event['payload']);
            final burnedId = _parseStarterBurnedId(payload);
            if (burnedId != null) {
              activeStartersById.remove(toHex(Uint8List.fromList(burnedId)));
            }
            break;
          case 7:
            relationshipEstablished++;
            break;
          case 8:
            relationshipBroken++;
            break;
          default:
            break;
        }
      }

      final starterCount = activeStartersById.length.clamp(0, 5);
      final relationshipCount =
          (relationshipEstablished - relationshipBroken).clamp(0, 9999);
      final pendingInvitations = (invitationSent - invitationResolved).clamp(0, 9999);
      final ledgerVersion = events.length;
      final ledgerHashHex = _parseLedgerHashHex(ledger['last_hash']);

      return CapsuleLedgerSummary(
        starterCount: starterCount,
        relationshipCount: relationshipCount,
        pendingInvitations: pendingInvitations,
        ledgerVersion: ledgerVersion,
        ledgerHashHex: ledgerHashHex,
      );
    } catch (_) {
      return CapsuleLedgerSummary.empty();
    }
  }

  List<int>? parseBytesField(dynamic raw) {
    if (raw is List) {
      final out = <int>[];
      for (final item in raw) {
        if (item is! num) return null;
        final value = item.toInt();
        if (value < 0 || value > 255) return null;
        out.add(value);
      }
      return out;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final isHex = RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed);
      if (isHex && trimmed.length.isEven) {
        final out = <int>[];
        for (int i = 0; i < trimmed.length; i += 2) {
          out.add(int.parse(trimmed.substring(i, i + 2), radix: 16));
        }
        return out;
      }
      try {
        return base64Decode(trimmed);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  int _eventKindCode(dynamic rawKind) {
    if (rawKind is num) return rawKind.toInt();
    if (rawKind is! String) return -1;
    switch (rawKind) {
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
      default:
        return -1;
    }
  }

  _StarterRecord? _parseStarterCreated(List<int>? payload) {
    if (payload == null || payload.length < 66) return null;
    final kindCode = payload[64];
    if (kindCode < 0 || kindCode > 4) return null;
    final starterId = payload.sublist(0, 32);
    return _StarterRecord(kindCode: kindCode, starterId: starterId);
  }

  List<int>? _parseStarterBurnedId(List<int>? payload) {
    if (payload == null || payload.length < 32) return null;
    return payload.sublist(0, 32);
  }

  String _parseLedgerHashHex(dynamic raw) {
    if (raw == null) return '0';
    if (raw is int) {
      return raw.toUnsigned(64).toRadixString(16);
    }
    if (raw is double) {
      return raw.toInt().toUnsigned(64).toRadixString(16);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return '0';
      final dec = int.tryParse(trimmed);
      if (dec != null) return dec.toUnsigned(64).toRadixString(16);
      final hex = trimmed.startsWith('0x') ? trimmed.substring(2) : trimmed;
      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
        return hex.toLowerCase();
      }
    }
    return '0';
  }
}

class _StarterRecord {
  final int kindCode;
  final List<int> starterId;

  _StarterRecord({required this.kindCode, required this.starterId});
}
