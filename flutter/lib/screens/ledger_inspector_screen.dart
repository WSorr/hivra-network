import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ffi/hivra_bindings.dart';
import '../services/capsule_state_manager.dart';

class LedgerInspectorScreen extends StatefulWidget {
  const LedgerInspectorScreen({super.key});

  @override
  State<LedgerInspectorScreen> createState() => _LedgerInspectorScreenState();
}

class _LedgerInspectorScreenState extends State<LedgerInspectorScreen> {
  final HivraBindings _hivra = HivraBindings();
  late final CapsuleStateManager _stateManager;

  bool _isLoading = true;
  String? _error;
  String _rawLedgerJson = '';
  List<_LedgerEventRow> _recentEvents = const <_LedgerEventRow>[];
  Map<String, int> _eventCounts = const <String, int>{};

  @override
  void initState() {
    super.initState();
    _stateManager = CapsuleStateManager(_hivra);
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _stateManager.refreshWithFullState();
      final raw = _hivra.exportLedger();
      if (raw == null || raw.trim().isEmpty) {
        setState(() {
          _rawLedgerJson = '';
          _recentEvents = const <_LedgerEventRow>[];
          _eventCounts = const <String, int>{};
          _error = 'Ledger export returned empty result';
          _isLoading = false;
        });
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        setState(() {
          _rawLedgerJson = raw;
          _recentEvents = const <_LedgerEventRow>[];
          _eventCounts = const <String, int>{};
          _error = 'Ledger JSON has unsupported shape';
          _isLoading = false;
        });
        return;
      }

      final events = _readEvents(decoded);
      final counts = <String, int>{};
      final rows = <_LedgerEventRow>[];

      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        final kindLabel = _kindLabel(event['kind']);
        counts[kindLabel] = (counts[kindLabel] ?? 0) + 1;

        rows.add(
          _LedgerEventRow(
            index: i,
            kind: kindLabel,
            timestamp: _timestampLabel(event['timestamp']),
            payloadSize: _payloadSize(event['payload']),
            signer: _shortSigner(event['signer']),
          ),
        );
      }

      final recent = rows.reversed.take(40).toList(growable: false);

      setState(() {
        _rawLedgerJson = raw;
        _recentEvents = recent;
        _eventCounts = counts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to read ledger: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _readEvents(Map<String, dynamic> root) {
    final rawEvents = root['events'];
    if (rawEvents is! List) return const <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final item in rawEvents) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }

  String _kindLabel(dynamic kind) {
    if (kind is String) return kind;
    if (kind is int) {
      switch (kind) {
        case 0:
          return 'CapsuleCreated';
        case 1:
          return 'InvitationSent';
        case 2:
          return 'InvitationAccepted';
        case 3:
          return 'InvitationRejected';
        case 4:
          return 'InvitationExpired';
        case 5:
          return 'StarterCreated';
        case 6:
          return 'StarterBurned';
        case 7:
          return 'RelationshipEstablished';
        case 8:
          return 'RelationshipBroken';
      }
      return 'Kind($kind)';
    }
    return 'Unknown';
  }

  String _timestampLabel(dynamic timestamp) {
    if (timestamp is! num) return 'n/a';
    final raw = timestamp.toInt();
    if (raw <= 0) return 'n/a';

    // Support multiple possible timestamp units from different backends.
    int epochMs;
    if (raw >= 1000000000000000000) {
      // nanoseconds
      epochMs = raw ~/ 1000000;
    } else if (raw >= 1000000000000000) {
      // microseconds
      epochMs = raw ~/ 1000;
    } else if (raw >= 1000000000000) {
      // milliseconds
      epochMs = raw;
    } else if (raw >= 1000000000) {
      // seconds
      epochMs = raw * 1000;
    } else {
      // Likely logical counter/version, not wall-clock Unix time.
      return 'logical:$raw';
    }

    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
    if (dt.year < 2020 || dt.year > 2100) {
      return 'logical:$raw';
    }

    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$mi:$ss UTC';
  }

  int _payloadSize(dynamic payload) {
    if (payload is List) return payload.length;
    if (payload is String) {
      try {
        return base64.decode(payload).length;
      } catch (_) {
        return payload.length;
      }
    }
    return 0;
  }

  String _shortSigner(dynamic signer) {
    if (signer is List) {
      final bytes = signer.whereType<num>().map((v) => v.toInt()).toList(growable: false);
      if (bytes.isNotEmpty) return _short(base64.encode(bytes));
    }
    if (signer is String && signer.isNotEmpty) return _short(signer);
    return 'n/a';
  }

  String _short(String value, {int start = 10, int end = 6}) {
    if (value.length <= start + end + 3) return value;
    return '${value.substring(0, start)}...${value.substring(value.length - end)}';
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final state = _stateManager.state;
    final ownerB64 = state.publicKey.isEmpty ? 'No key' : base64.encode(state.publicKey);
    final distribution = _eventCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger Inspector'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Copy raw ledger JSON',
            onPressed: _rawLedgerJson.isEmpty
                ? null
                : () => _copyToClipboard(_rawLedgerJson, 'Ledger JSON'),
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionTitle('Capsule'),
                      _infoCard(
                        children: [
                          _kv('Owner (base64)', _short(ownerB64, start: 14, end: 8), trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: ownerB64 == 'No key' ? null : () => _copyToClipboard(ownerB64, 'Owner key'),
                          )),
                          _kv('Network', state.isNeste ? 'NESTE' : 'HOOD'),
                          _kv('Ledger version', state.version.toString()),
                          _kv('Ledger hash', _short(state.ledgerHashHex, start: 12, end: 8), trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: state.ledgerHashHex.isEmpty ? null : () => _copyToClipboard(state.ledgerHashHex, 'Ledger hash'),
                          )),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('State Counters'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _counterChip('Starters', state.starterCount, Colors.blue),
                          _counterChip('Relationships', state.relationshipCount, Colors.green),
                          _counterChip('Pending', state.pendingInvitations, Colors.orange),
                          _counterChip('Events', _recentEvents.length, Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('Event Distribution'),
                      _infoCard(
                        children: distribution
                            .map<Widget>((e) => _kv(e.key, e.value.toString()))
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('Recent Events (latest 40)'),
                      if (_recentEvents.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No events available'),
                          ),
                        )
                      else
                        ..._recentEvents.map((event) => Card(
                              child: ListTile(
                                dense: true,
                                title: Text(event.kind),
                                subtitle: Text(
                                  '#${event.index}  •  ${event.timestamp}\n'
                                  'payload ${event.payloadSize} bytes  •  signer ${event.signer}',
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _infoCard({required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(children: children),
      ),
    );
  }

  Widget _kv(String key, String value, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              key,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _counterChip(String label, int value, Color color) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: color.withOpacity(0.18),
      side: BorderSide(color: color.withOpacity(0.45)),
      labelStyle: TextStyle(color: color),
    );
  }
}

class _LedgerEventRow {
  final int index;
  final String kind;
  final String timestamp;
  final int payloadSize;
  final String signer;

  const _LedgerEventRow({
    required this.index,
    required this.kind,
    required this.timestamp,
    required this.payloadSize,
    required this.signer,
  });
}
