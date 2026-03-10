import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:bech32/bech32.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_state_manager.dart';
import '../services/capsule_persistence_service.dart';

class StartersScreen extends StatefulWidget {
  const StartersScreen({super.key});

  @override
  State<StartersScreen> createState() => _StartersScreenState();
}

class _StartersScreenState extends State<StartersScreen> {
  final HivraBindings _hivra = HivraBindings();
  final CapsulePersistenceService _persistence = CapsulePersistenceService();
  List<Map<String, dynamic>> _slots = const [];

  // Helper function to convert bits (5-bit to 8-bit)
  List<int>? _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    var result = <int>[];
    var maxv = (1 << toBits) - 1;
    
    for (var value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        return null;
      }
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }
    
    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      return null;
    }
    
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  void _loadSlots() {
    final stateManager = CapsuleStateManager(_hivra);
    stateManager.refresh();
    final starterSlots = stateManager.state.starterSlots;

    final slots = <Map<String, dynamic>>[];
    for (int i = 0; i < 5; i++) {
      final slotState = i < starterSlots.length ? starterSlots[i] : null;
      final id = slotState?.starterId;

      slots.add({
        'index': i,
        'occupied': slotState?.occupied ?? false,
        'type': slotState?.kind ?? 'Unknown',
        'starterId': id != null ? _formatStarterId(id) : null,
        'starterIdRaw': id,
        'locked': false,
      });
    }

    if (!mounted) return;
    setState(() {
      _slots = slots;
    });
  }

  String _formatStarterId(Uint8List id) {
    final b64 = base64.encode(id);
    if (b64.length <= 12) return b64;
    return '${b64.substring(0, 6)}...${b64.substring(b64.length - 6)}';
  }

  Uint8List? _decodePubkey(String input) {
    input = input.trim();
    
    // Try base64 first (32 bytes)
    try {
      final bytes = base64.decode(input);
      if (bytes.length == 32) return bytes;
    } catch (_) {}
    
    // Try bech32 (npub...)
    if (input.startsWith('npub1')) {
      try {
        final decoded = bech32.decode(input);
        if (decoded.hrp == 'npub') {
          final data = _convertBits(decoded.data, 5, 8, false);
          if (data != null && data.length == 32) {
            return Uint8List.fromList(data);
          }
        }
      } catch (_) {}
    }
    
    // Try hex
    try {
      final cleanHex = input.replaceAll(':', '').replaceAll(' ', '').replaceAll('-', '');
      // Convert hex string to bytes manually
      final bytes = <int>[];
      for (int i = 0; i < cleanHex.length; i += 2) {
        final hexByte = cleanHex.substring(i, i + 2);
        bytes.add(int.parse(hexByte, radix: 16));
      }
      if (bytes.length == 32) {
        return Uint8List.fromList(bytes);
      }
    } catch (_) {}
    
    return null;
  }

  Future<void> _showInviteDialog(Map<String, dynamic> slot) async {
    final TextEditingController pubkeyController = TextEditingController();
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invite with ${slot['type']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter recipient public key:'),
            const SizedBox(height: 8),
            const Text(
              'Supports: base64, npub... (bech32), hex',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pubkeyController,
              decoration: const InputDecoration(
                hintText: 'Public key',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final input = pubkeyController.text.trim();
              if (input.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter public key')),
                );
                return;
              }
              
              final pubkeyBytes = _decodePubkey(input);
              if (pubkeyBytes == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid public key format')),
                );
                return;
              }
              
              try {
                final slotIndex = slot['index'] is int ? slot['index'] as int : -1;
                if (slotIndex < 0 || slotIndex > 4) {
                  throw Exception('Invalid starter slot');
                }

                final sent = _hivra.sendInvitation(pubkeyBytes, slotIndex);
                if (!sent) {
                  throw Exception('transport send failed');
                }

                final persisted = await _persistence.persistLedgerSnapshot(_hivra);
                if (!persisted) {
                  throw Exception('ledger snapshot was not saved');
                }

                Navigator.pop(context);
                if (!mounted) return;
                final peerPreview = input.length <= 8 ? input : '${input.substring(0, 8)}...';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Invitation sent to $peerPreview')),
                );

                setState(() {
                  slot['locked'] = true;
                });
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to send: $e')),
                );
              }
            },
            child: const Text('Send Invitation'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_slots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        _loadSlots();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) {
          final slot = _slots[index];
          return _buildSlotCard(slot);
        },
      ),
    );
  }

  Widget _buildSlotCard(Map<String, dynamic> slot) {
    final bool occupied = slot['occupied'];
    final String type = slot['type'];
    final String displayType = occupied ? type : 'Empty';
    final bool locked = slot['locked'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getTypeColor(displayType).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _getTypeColor(displayType)),
                  ),
                  child: Text(
                    displayType,
                    style: TextStyle(
                      color: _getTypeColor(displayType),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Slot ${slot['index'] + 1}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (occupied) ...[
              Row(
                children: [
                  const Icon(Icons.fingerprint, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ID: ${slot['starterId']}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    locked ? Icons.lock : Icons.lock_open,
                    size: 16,
                    color: locked ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    locked ? 'Locked (invitation pending)' : 'Available',
                    style: TextStyle(
                      color: locked ? Colors.orange : Colors.green,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'Empty slot - ready to receive',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (occupied && !locked)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showInviteDialog(slot),
                  icon: const Icon(Icons.send),
                  label: const Text('Invite'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Juice':
        return Colors.orange;
      case 'Spark':
        return Colors.yellow;
      case 'Seed':
        return Colors.green;
      case 'Pulse':
        return Colors.red;
      case 'Kick':
        return Colors.blue;
      case 'Empty':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}
