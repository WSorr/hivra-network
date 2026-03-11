import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../models/relationship.dart';
import '../models/starter.dart';
import '../widgets/relationship_card.dart';
import '../ffi/hivra_bindings.dart';
import '../services/ledger_view_service.dart';

class RelationshipsScreen extends StatefulWidget {
  final HivraBindings hivra;

  const RelationshipsScreen({super.key, required this.hivra});

  @override
  State<RelationshipsScreen> createState() => _RelationshipsScreenState();
}

class _RelationshipsScreenState extends State<RelationshipsScreen> {
  List<Relationship> _relationships = [];
  bool _isLoading = true;
  String? _filterKind;

  @override
  void initState() {
    super.initState();
    _loadRelationships();
  }

  Future<void> _loadRelationships() async {
    final service = LedgerViewService(widget.hivra);
    setState(() {
      _relationships = service.loadRelationships();
      _isLoading = false;
    });
  }

  void _breakRelationship(Relationship relationship) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Break Relationship?'),
        content: Text(
          'This will break your relationship with ${relationship.peerDisplayName}. '
          'Your starter will NOT be burned.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              final peer = _decodeB64_32(relationship.peerPubkey);
              final own = _decodeB64_32(relationship.ownStarterId);
              if (peer == null || own == null) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to break relationship')),
                );
                return;
              }
              final payload = Uint8List(64);
              payload.setRange(0, 32, peer);
              payload.setRange(32, 64, own);
              final ok = widget.hivra.ledgerAppendEvent(8, payload);
              Navigator.pop(context);
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to break relationship')),
                );
                return;
              }
              _loadRelationships();
            },
            child: const Text('Break'),
          ),
        ],
      ),
    );
  }

  List<Relationship> get _filteredRelationships {
    if (_filterKind == null) return _relationships;
    return _relationships.where((r) => r.kind.displayName == _filterKind).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relationships'),
        actions: [
          // Filter by kind
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _filterKind = value == 'all' ? null : value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('All'),
              ),
              ...StarterKind.values.map((kind) => PopupMenuItem(
                value: kind.displayName,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: kind.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(kind.displayName),
                  ],
                ),
              )),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRelationships,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredRelationships.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No relationships yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Accept invitations to build your network',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  itemCount: _filteredRelationships.length,
                  itemBuilder: (context, index) {
                    final rel = _filteredRelationships[index];
                    return RelationshipCard(
                      relationship: rel,
                      onBreak: rel.isActive ? () => _breakRelationship(rel) : null,
                      onTap: () {
                        // TODO: Show relationship details
                      },
                    );
                  },
                ),
    );
  }

  Uint8List? _decodeB64_32(String value) {
    try {
      final bytes = base64.decode(value);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
  }
}
