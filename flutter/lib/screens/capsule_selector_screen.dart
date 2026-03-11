import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_persistence_service.dart';
import 'main_screen.dart';
import 'first_launch_screen.dart';

class CapsuleSelectorScreen extends StatefulWidget {
  final bool autoSelectSingle;

  const CapsuleSelectorScreen({super.key, this.autoSelectSingle = true});

  @override
  State<CapsuleSelectorScreen> createState() => _CapsuleSelectorScreenState();
}

class _CapsuleSelectorScreenState extends State<CapsuleSelectorScreen> {
  final HivraBindings _hivra = HivraBindings();
  List<CapsuleInfo> _capsules = [];
  bool _isLoading = true;
  final TextEditingController _seedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadCapsules);
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _loadCapsules() async {
    final persistence = CapsulePersistenceService();
    final entries = await persistence.listCapsules(hivra: _hivra);
    _capsules = [];
    for (final entry in entries) {
      var summary = await persistence.loadCapsuleSummary(entry.pubKeyHex);
      if (summary.ledgerHashHex == '7fffffffffffffff') {
        final hasSeed = await persistence.hasStoredSeed(entry.pubKeyHex);
        if (hasSeed) {
          final refreshed = await persistence.refreshCapsuleSnapshot(
            _hivra,
            entry.pubKeyHex,
          );
          if (refreshed) {
            summary = await persistence.loadCapsuleSummary(entry.pubKeyHex);
          }
        }
      }
      _capsules.add(
        CapsuleInfo(
          id: entry.pubKeyHex,
          publicKeyHex: entry.pubKeyHex,
          network: entry.isNeste ? 'NESTE' : 'HOOD',
          starterCount: summary.starterCount,
          relationshipCount: summary.relationshipCount,
          pendingInvitations: summary.pendingInvitations,
          ledgerVersion: summary.ledgerVersion,
          ledgerHashHex: summary.ledgerHashHex,
          lastActive: entry.lastActive,
          createdAt: entry.createdAt,
        ),
      );
    }

    if (_capsules.isEmpty && _hivra.seedExists()) {
      // If we still don't have an index, stay empty and let user create/recover.
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    if (widget.autoSelectSingle && _capsules.length == 1 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectCapsule(_capsules.first);
      });
    }
  }

  Future<void> _selectCapsule(CapsuleInfo capsule) async {
    final persistence = CapsulePersistenceService();
    try {
      await persistence.activateCapsule(_hivra, capsule.publicKeyHex);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to activate capsule: $e')),
      );
      return;
    }

    final bootstrapped =
        await persistence.bootstrapActiveCapsuleRuntime(_hivra);
    if (!bootstrapped && mounted) {
      final reason = await persistence.diagnoseActiveCapsuleBootstrap(_hivra);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason == null
                ? 'Failed to load capsule into runtime'
                : 'Failed to load capsule: $reason',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  void _createNewCapsule() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FirstLaunchScreen()),
    );
  }

  Future<void> _importCapsule() async {
    final persistence = CapsulePersistenceService();
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;

      final raw = await File(file.path).readAsString();
      final importedHex = await persistence.importCapsuleFromBackupJson(raw);
      if (importedHex == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed: invalid backup')),
        );
        return;
      }
      await _loadCapsules();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  Future<void> _exportCapsule(CapsuleInfo capsule) async {
    final persistence = CapsulePersistenceService();
    try {
      final location = await getSaveLocation(
        suggestedName:
            'capsule-backup-${capsule.publicKeyHex.substring(0, 8)}.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (location == null) return;

      final path = await persistence.exportCapsuleBackupToPath(
        capsule.publicKeyHex,
        location.path,
      );
      if (path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported: ${path.split('/').last}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _deleteCapsule(CapsuleInfo capsule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PANIC: Irreversible Delete'),
        content: const Text(
          'This will PERMANENTLY DELETE the capsule, seed, and local ledger/backup files.\n\n'
          'THIS ACTION IS IRREVERSIBLE.\n'
          'If you do not have the seed phrase and backup, recovery is impossible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final persistence = CapsulePersistenceService();
    await persistence.deleteCapsule(
      capsule.publicKeyHex,
      deleteLocalData: true,
    );
    if (!mounted) return;
    await _loadCapsules();
  }

  Future<void> _restoreSeedForCapsule(CapsuleInfo capsule) async {
    _seedController.clear();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Restore Seed'),
          content: TextField(
            controller: _seedController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Enter seed phrase (12 or 24 words)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    final phrase = _seedController.text.trim();
    if (!_hivra.validateMnemonic(phrase)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid seed phrase')),
      );
      return;
    }

    final seed = _hivra.mnemonicToSeed(phrase);
    final persistence = CapsulePersistenceService();
    final matches = await persistence.seedMatchesCapsule(
      _hivra,
      seed,
      capsule.publicKeyHex,
    );
    if (!matches) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seed does not match capsule')),
      );
      return;
    }

    await persistence.saveSeedForCapsule(capsule.publicKeyHex, seed);
    await _loadCapsules();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_capsules.isEmpty) {
      // No capsules, go to first launch
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const FirstLaunchScreen()),
        );
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Capsule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewCapsule,
            tooltip: 'Create new capsule',
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _importCapsule,
            tooltip: 'Import capsule',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _capsules.length,
        itemBuilder: (ctx, index) {
          final capsule = _capsules[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: capsule.network == 'NESTE'
                      ? Colors.green.shade900
                      : Colors.orange.shade900,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    capsule.starterCount.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              title: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: capsule.network == 'NESTE'
                          ? Colors.green.shade900
                          : Colors.orange.shade900,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      capsule.network,
                      style: TextStyle(
                        fontSize: 10,
                        color: capsule.network == 'NESTE'
                            ? Colors.green.shade300
                            : Colors.orange.shade300,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatPubKeyHex(capsule.publicKeyHex),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                'Last active: ${_formatDate(capsule.lastActive)} · '
                'Starters ${capsule.starterCount} · '
                'Relationships ${capsule.relationshipCount} · '
                'Pending ${capsule.pendingInvitations} · '
                'v${capsule.ledgerVersion}\n'
                'hash ${capsule.ledgerHashHex}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async => _selectCapsule(capsule),
              onLongPress: () => _showCapsuleMenu(capsule),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCapsuleMenu(CapsuleInfo capsule) async {
    final persistence = CapsulePersistenceService();
    final hasSeed = await persistence.hasStoredSeed(capsule.publicKeyHex);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.vpn_key),
                title: Text(hasSeed ? 'Replace Seed' : 'Restore Seed'),
                onTap: () => Navigator.pop(ctx, 'restore'),
              ),
              ListTile(
                leading: const Icon(Icons.save),
                title: const Text('Export Backup'),
                onTap: () => Navigator.pop(ctx, 'export'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete Capsule'),
                subtitle: const Text('Permanently remove all local data'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        );
      },
    );
    if (action == 'export') {
      await _exportCapsule(capsule);
    } else if (action == 'restore') {
      await _restoreSeedForCapsule(capsule);
    } else if (action == 'delete') {
      await _deleteCapsule(capsule);
    }
  }

  String _formatPubKeyHex(String hex) {
    if (hex.isEmpty) return 'No key';
    if (hex.length <= 18) return hex;
    return '${hex.substring(0, 10)}...${hex.substring(hex.length - 6)}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }

  String _bytesToHex(Uint8List bytes) {
    final b = StringBuffer();
    for (final byte in bytes) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }
}

class CapsuleInfo {
  final String id;
  final String publicKeyHex;
  final String network;
  final int starterCount;
  final int relationshipCount;
  final int pendingInvitations;
  final int ledgerVersion;
  final String ledgerHashHex;
  final DateTime lastActive;
  final DateTime createdAt;

  CapsuleInfo({
    required this.id,
    required this.publicKeyHex,
    required this.network,
    required this.starterCount,
    required this.relationshipCount,
    required this.pendingInvitations,
    required this.ledgerVersion,
    required this.ledgerHashHex,
    required this.lastActive,
    required this.createdAt,
  });
}
