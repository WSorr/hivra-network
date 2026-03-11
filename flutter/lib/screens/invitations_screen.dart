import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:bech32/bech32.dart';
import '../models/invitation.dart';
import '../models/starter.dart';
import '../widgets/invitation_card.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_persistence_service.dart';
import '../services/capsule_state_manager.dart';
import '../services/ledger_view_service.dart';

bool _bootstrapWorkerRuntime(HivraBindings hivra, Map<String, Object?> args) {
  final seed = args['seed'] as Uint8List;
  final isGenesis = args['isGenesis'] as bool;
  final isNeste = args['isNeste'] as bool;
  final ledgerJson = args['ledgerJson'] as String?;

  if (!hivra.saveSeed(seed)) return false;
  if (!hivra.createCapsule(seed, isGenesis: isGenesis, isNeste: isNeste)) {
    return false;
  }
  if (ledgerJson != null &&
      ledgerJson.isNotEmpty &&
      !hivra.importLedger(ledgerJson)) {
    return false;
  }
  return true;
}

Map<String, Object?> _sendInvitationInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'ok': false};
  }

  final toPubkey = args['toPubkey'] as Uint8List;
  final starterSlot = args['starterSlot'] as int;
  final ok = hivra.sendInvitation(toPubkey, starterSlot);
  return <String, Object?>{
    'ok': ok,
    'ledgerJson': ok ? hivra.exportLedger() : null,
  };
}

Map<String, Object?> _receiveInvitationsInWorker(Map<String, Object?> args) {
  final hivra = HivraBindings();
  if (!_bootstrapWorkerRuntime(hivra, args)) {
    return <String, Object?>{'result': -1004};
  }
  final result = hivra.receiveTransportMessages();
  return <String, Object?>{
    'result': result,
    'ledgerJson': hivra.exportLedger(),
  };
}

class InvitationsScreen extends StatefulWidget {
  final HivraBindings hivra;
  final Future<void> Function()? onLedgerChanged;

  const InvitationsScreen({
    super.key,
    required this.hivra,
    this.onLedgerChanged,
  });

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  final CapsulePersistenceService _persistence = CapsulePersistenceService();
  List<Invitation> _invitations = [];
  bool _isFetchingFromNostr = false;
  String? _processingId;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  Future<void> _loadInvitations({bool showLoading = true}) async {
    final service = LedgerViewService(widget.hivra);
    setState(() {
      _invitations = service.loadInvitations();
    });
  }

  Future<void> _refreshAfterLedgerMutation() async {
    await _loadInvitations(showLoading: false);
    await widget.onLedgerChanged?.call();
  }

  Future<void> _sendInvitationAsync(Uint8List pubkey, int slot) async {
    final bootstrap = await _loadWorkerBootstrap();
    if (bootstrap == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Active capsule bootstrap failed')),
        );
      }
      return;
    }

    final workerResult =
        await compute<Map<String, Object?>, Map<String, Object?>>(
      _sendInvitationInWorker,
      <String, Object?>{
        ...bootstrap,
        'toPubkey': pubkey,
        'starterSlot': slot,
      },
    ).timeout(
      const Duration(seconds: 8),
      onTimeout: () => <String, Object?>{'ok': false},
    );
    final ok = workerResult['ok'] == true;
    final ledgerJson = workerResult['ledgerJson'] as String?;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Invitation sent'
              : 'Send timed out. Pull to refresh and check status.'),
        ),
      );
    }

    if (ok) {
      if (ledgerJson != null && ledgerJson.isNotEmpty) {
        widget.hivra.importLedger(ledgerJson);
        await _persistence.persistLedgerSnapshot(widget.hivra);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        await _refreshAfterLedgerMutation();
      }
    }
  }

  String _receiveErrorMessage(int code) {
    switch (code) {
      case -1:
        return 'Seed not found on receiver';
      case -2:
        return 'Receiver key derivation failed';
      case -3:
        return 'Capsule is not initialized';
      case -4:
        return 'Transport init failed';
      case -5:
        return 'Nostr receive failed';
      case -1002:
        return 'Receive API is not available in FFI';
      case -1003:
        return 'Fetch timed out';
      case -1004:
        return 'Active capsule bootstrap failed';
      default:
        return 'Receive failed (code $code)';
    }
  }

  String _acceptErrorMessage(int code) {
    switch (code) {
      case -1:
        return 'Invalid acceptance arguments';
      case -2:
        return 'Seed not found';
      case -3:
        return 'Failed to append InvitationAccepted';
      case -4:
        return 'Sender key derivation failed';
      case -5:
        return 'Capsule is not initialized';
      case -6:
        return 'Transport init failed';
      case -7:
        return 'Failed to send InvitationAccepted';
      case -8:
        return 'Matching incoming invitation not found in ledger';
      case -9:
        return 'No capacity to accept this invitation';
      case -10:
        return 'Failed to finalize local acceptance';
      case -1002:
        return 'Accept API is not available in FFI';
      default:
        return 'Failed to accept invitation (code $code)';
    }
  }

  Future<void> _fetchFromNostr() async {
    if (_isFetchingFromNostr) return;

    setState(() => _isFetchingFromNostr = true);
    int result = -1003;

    try {
      final bootstrap = await _loadWorkerBootstrap();
      if (bootstrap == null) {
        result = -1004;
      } else {
        final workerResult =
            await compute<Map<String, Object?>, Map<String, Object?>>(
          _receiveInvitationsInWorker,
          bootstrap,
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () => <String, Object?>{'result': -1003},
        );
        result = (workerResult['result'] as int?) ?? -1003;
        final ledgerJson = workerResult['ledgerJson'] as String?;
        if (result >= 0 && ledgerJson != null && ledgerJson.isNotEmpty) {
          widget.hivra.importLedger(ledgerJson);
          await _persistence.persistLedgerSnapshot(widget.hivra);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingFromNostr = false);
      }
    }

    if (!mounted) return;

    if (result >= 0) {
      await _refreshAfterLedgerMutation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fetched from Nostr: $result new event(s)')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_receiveErrorMessage(result))),
    );
  }

  Future<Map<String, Object?>?> _loadWorkerBootstrap() async {
    return _persistence.loadWorkerBootstrapArgs(widget.hivra);
  }

  Future<void> _acceptInvitation(Invitation invitation) async {
    setState(() => _processingId = invitation.id);

    final invitationId = _decodeB64_32(invitation.id);
    final fromPubkey = _decodeB64_32(invitation.fromPubkey);
    final placeholderStarterId = Uint8List(32);
    final acceptCode = invitationId != null && fromPubkey != null
        ? widget.hivra.acceptInvitationCode(
            invitationId, fromPubkey, placeholderStarterId)
        : -1;
    if (acceptCode != 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _acceptErrorMessage(acceptCode),
          ),
        ),
      );
    }
    if (acceptCode == 0) {
      await _persistence.persistLedgerSnapshot(widget.hivra);
    }
    await _refreshAfterLedgerMutation();
    if (mounted) setState(() => _processingId = null);
  }

  Future<void> _rejectInvitation(Invitation invitation) async {
    // Show confirmation dialog for empty slot case
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Invitation?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If you reject with an empty slot, the sender\'s starter will be BURNED permanently.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _processingId = invitation.id);

    final invitationId = _decodeB64_32(invitation.id);
    final ok = invitationId != null &&
        widget.hivra.rejectInvitation(
            invitationId, _rejectReasonForInvitation(invitation));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to reject invitation')),
      );
    }
    if (ok) {
      await _persistence.persistLedgerSnapshot(widget.hivra);
    }
    await _refreshAfterLedgerMutation();
    if (mounted) setState(() => _processingId = null);
  }

  Future<void> _cancelInvitation(Invitation invitation) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Invitation?'),
        content: const Text('This will unlock your starter.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _processingId = invitation.id);

    final invitationId = _decodeB64_32(invitation.id);
    final ok =
        invitationId != null && widget.hivra.expireInvitation(invitationId);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to cancel invitation')),
      );
    }
    if (ok) {
      await _persistence.persistLedgerSnapshot(widget.hivra);
    }
    await _refreshAfterLedgerMutation();
    if (mounted) setState(() => _processingId = null);
  }

  void _showSendInvitationDialog() {
    final controller = TextEditingController();
    final state = CapsuleStateManager(widget.hivra).state;
    final lockedSlots = state.lockedStarterSlots;
    final availableSlots = <int>[
      for (var i = 0; i < 5; i++)
        if (i < state.starterSlots.length &&
            state.starterSlots[i].occupied &&
            !lockedSlots.contains(i))
          i,
    ];
    int? selectedSlot = availableSlots.isNotEmpty ? availableSlots.first : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Send Invitation',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Recipient Public Key',
                    hintText: 'base64 / npub / hex',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Select Starter:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                if (availableSlots.isEmpty && lockedSlots.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded,
                          color: Colors.orange),
                      title: Text('No active starters'),
                      subtitle: Text(
                          'You need at least one active starter to send invitations.'),
                    ),
                  )
                else if (availableSlots.isEmpty && lockedSlots.isNotEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.lock_clock, color: Colors.orange),
                      title: Text('Starters are locked'),
                      subtitle: Text(
                          'Invitations lock starters for 24h. Cancel to unlock early.'),
                    ),
                  )
                else
                  ...availableSlots.map((slot) {
                    final kind = state.starterSlots[slot].kind;
                    final color = _starterColor(kind);
                    final selected = selectedSlot == slot;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setModalState(() => selectedSlot = slot),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: selected ? color : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(kind),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Slot ${slot + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                if (lockedSlots.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._lockedSlotRows(lockedSlots),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: selectedSlot == null
                        ? null
                        : () {
                            final pubkey = _decodePubkey(controller.text);
                            final slot = selectedSlot;
                            if (pubkey == null || slot == null) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Invalid recipient public key')),
                              );
                              return;
                            }

                            if (sheetContext.mounted) {
                              FocusScope.of(sheetContext).unfocus();
                              Navigator.of(sheetContext).pop();
                            }

                            unawaited(_sendInvitationAsync(pubkey, slot));
                          },
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ),
              ],
            ),
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

  int _rejectReasonForInvitation(Invitation invitation) {
    final state = CapsuleStateManager(widget.hivra).state;
    final hasMatchingStarter = state.starterSlots.any(
      (slot) => slot.occupied && _starterKindFromName(slot.kind) == invitation.kind,
    );
    final hasEmptySlot = state.starterSlots.any((slot) => !slot.occupied);
    return (!hasMatchingStarter && hasEmptySlot) ? 0 : 1;
  }

  List<Widget> _lockedSlotRows(Set<int> lockedSlots) {
    final state = CapsuleStateManager(widget.hivra).state;
    return lockedSlots.map((slot) {
      final kind =
          slot < state.starterSlots.length ? state.starterSlots[slot].kind : 'Unknown';
      final color = _starterColor(kind);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(Icons.lock, size: 16, color: color),
            const SizedBox(width: 8),
            Text('Slot ${slot + 1} ($kind) locked'),
            const Spacer(),
            const Text('Cancel to unlock',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }).toList();
  }

  StarterKind? _starterKindFromName(String name) {
    switch (name) {
      case 'Juice':
        return StarterKind.juice;
      case 'Spark':
        return StarterKind.spark;
      case 'Seed':
        return StarterKind.seed;
      case 'Pulse':
        return StarterKind.pulse;
      case 'Kick':
        return StarterKind.kick;
      default:
        return null;
    }
  }

  Color _starterColor(String kind) {
    switch (kind) {
      case 'Juice':
        return Colors.orange;
      case 'Spark':
        return Colors.red;
      case 'Seed':
        return Colors.green;
      case 'Pulse':
        return Colors.blue;
      case 'Kick':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  List<int>? _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;
    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) return null;
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) result.add((acc << (toBits - bits)) & maxv);
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      return null;
    }
    return result;
  }

  Uint8List? _decodePubkey(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    try {
      final bytes = base64.decode(value);
      if (bytes.length == 32) return Uint8List.fromList(bytes);
    } catch (_) {}
    if (value.startsWith('npub1')) {
      try {
        final decoded = bech32.decode(value);
        if (decoded.hrp == 'npub') {
          final data = _convertBits(decoded.data, 5, 8, false);
          if (data != null && data.length == 32) {
            return Uint8List.fromList(data);
          }
        }
      } catch (_) {}
    }
    try {
      final hex =
          value.replaceAll(':', '').replaceAll(' ', '').replaceAll('-', '');
      if (hex.length == 64) {
        final bytes = <int>[];
        for (var i = 0; i < hex.length; i += 2) {
          bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
        }
        return Uint8List.fromList(bytes);
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _invitations.where((inv) => inv.isIncoming).toList();
    final outgoing = _invitations.where((inv) => inv.isOutgoing).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showSendInvitationDialog,
          ),
          IconButton(
            icon: _isFetchingFromNostr
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download),
            onPressed: _isFetchingFromNostr ? null : _fetchFromNostr,
            tooltip: 'Fetch from Nostr',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvitations,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchFromNostr,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader('Incoming', incoming.length),
            const SizedBox(height: 8),
            if (incoming.isEmpty)
              _emptySectionCard(
                icon: Icons.inbox_outlined,
                title: 'No incoming invitations',
                subtitle: 'Incoming requests will appear here.',
              )
            else
              ...incoming.map((inv) => InvitationCard(
                    invitation: inv,
                    onAccept: () => _acceptInvitation(inv),
                    onReject: () => _rejectInvitation(inv),
                    isLoading: _processingId == inv.id,
                  )),
            const SizedBox(height: 20),
            _sectionHeader('Outgoing', outgoing.length),
            const SizedBox(height: 8),
            if (outgoing.isEmpty)
              _emptySectionCard(
                icon: Icons.outbox_outlined,
                title: 'No outgoing invitations',
                subtitle:
                    'Send invitations manually using recipient public keys.',
                onTap: _showSendInvitationDialog,
              )
            else
              ...outgoing.map((inv) => InvitationCard(
                    invitation: inv,
                    onCancel: () => _cancelInvitation(inv),
                    isLoading: _processingId == inv.id,
                  )),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _emptySectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Colors.grey.shade500),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
