import 'dart:convert';
import 'dart:typed_data';

import '../models/starter.dart';

class LedgerViewSupport {
  const LedgerViewSupport();

  Map<String, dynamic>? exportLedgerRoot(String? json) {
    if (json == null || json.isEmpty) return null;
    final decoded = jsonDecode(json);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  List<dynamic> events(Map<String, dynamic> root) {
    final events = root['events'];
    return events is List ? events : const <dynamic>[];
  }

  int kindCode(dynamic value) {
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

  DateTime eventTime(dynamic ts) {
    if (ts is! num) return DateTime.now();

    final raw = ts.toInt();
    if (raw <= 0) return DateTime.now();

    final millis = raw < 100000000000 ? raw * 1000 : raw;

    try {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return DateTime.now();
    }
  }

  Uint8List payloadBytes(dynamic payload) {
    if (payload is List) {
      return Uint8List.fromList(
        payload.whereType<num>().map((v) => v.toInt()).toList(),
      );
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

  Uint8List bytes32(dynamic value) {
    if (value is List && value.length == 32) {
      return Uint8List.fromList(
        value.whereType<num>().map((v) => v.toInt()).toList(),
      );
    }
    final bytes = payloadBytes(value);
    return bytes.length == 32 ? bytes : Uint8List(32);
  }

  bool eq32(Uint8List a, Uint8List b) {
    if (a.length != 32 || b.length != 32) return false;
    for (var i = 0; i < 32; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int? slotForStarterId(Uint8List starterId, Map<int, Uint8List> slotToId) {
    for (final entry in slotToId.entries) {
      if (eq32(starterId, entry.value)) return entry.key;
    }
    return null;
  }

  StarterKind starterKindFromByte(int value) {
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
