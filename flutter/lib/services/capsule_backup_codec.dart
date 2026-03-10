import 'dart:convert';

class CapsuleBackupCodec {
    static const String schema = 'hivra.capsule_backup';
    static const int version = 1;

    static String encodeBackupEnvelope({
        required String ledgerJson,
        bool? isGenesis,
        bool? isNeste,
    }) {
        final decoded = jsonDecode(ledgerJson);
        if (decoded is! Map) {
            throw const FormatException('Ledger JSON must be an object');
        }

        final envelope = <String, dynamic>{
            'schema': schema,
            'version': version,
            'exported_at_utc': DateTime.now().toUtc().toIso8601String(),
            'ledger': Map<String, dynamic>.from(decoded),
            'meta': <String, dynamic>{
                if (isGenesis != null) 'is_genesis': isGenesis,
                if (isNeste != null) 'is_neste': isNeste,
            },
        };

        return jsonEncode(envelope);
    }

    static String? tryExtractLedgerJson(String inputJson) {
        final trimmed = inputJson.trim();
        if (trimmed.isEmpty) return null;

        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) return null;

        final obj = Map<String, dynamic>.from(decoded);

        // v1 envelope
        if (obj['schema'] == schema && obj['version'] == version) {
            final ledger = obj['ledger'];
            if (ledger is Map) {
                return jsonEncode(Map<String, dynamic>.from(ledger));
            }
            return null;
        }

        // Legacy raw ledger JSON
        if (obj.containsKey('owner') && obj.containsKey('events')) {
            return jsonEncode(obj);
        }

        return null;
    }
}
