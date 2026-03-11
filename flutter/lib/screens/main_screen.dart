import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_persistence_service.dart';
import '../services/capsule_state_manager.dart';
import 'starters_screen.dart';
import 'invitations_screen.dart';
import 'relationships_screen.dart';
import 'settings_screen.dart';

Map<String, Object?> _receiveTransportMessagesInWorker(
    Map<String, Object?> args) {
  final hivra = HivraBindings();
  final seed = args['seed'] as Uint8List;
  final isGenesis = args['isGenesis'] as bool;
  final isNeste = args['isNeste'] as bool;
  final ledgerJson = args['ledgerJson'] as String?;

  if (!hivra.saveSeed(seed)) return <String, Object?>{'result': -1004};
  if (!hivra.createCapsule(seed, isGenesis: isGenesis, isNeste: isNeste)) {
    return <String, Object?>{'result': -1004};
  }
  if (ledgerJson != null &&
      ledgerJson.isNotEmpty &&
      !hivra.importLedger(ledgerJson)) {
    return <String, Object?>{'result': -1004};
  }
  final result = hivra.receiveTransportMessages();
  return <String, Object?>{
    'result': result,
    'ledgerJson': hivra.exportLedger(),
  };
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final HivraBindings _hivra = HivraBindings();
  late final CapsuleStateManager _stateManager;
  final CapsulePersistenceService _persistence = CapsulePersistenceService();

  Timer? _ledgerWatcher;
  int _lastObservedLedgerVersion = 0;
  int _lastPromptedLedgerVersion = 0;
  bool _isBackupPromptOpen = false;
  bool _ledgerBaselineInitialized = false;
  bool _ledgerWatcherTickInProgress = false;
  bool _bootstrapping = true;

  String _publicKeyHex = '';
  int _starterCount = 0;
  int _relationshipCount = 0;
  int _pendingInvitations = 0;
  bool _isNeste = true;
  String _ledgerHashHex = '0';
  int _ledgerVersion = 0;

  String get _shortPublicKey {
    if (_publicKeyHex.isEmpty) return 'No key';
    if (_publicKeyHex.length <= 18) return _publicKeyHex;
    return '${_publicKeyHex.substring(0, 10)}...${_publicKeyHex.substring(_publicKeyHex.length - 6)}';
  }

  String get _shortLedgerHash {
    if (_ledgerHashHex.isEmpty) return '0';
    if (_ledgerHashHex.length <= 14) return _ledgerHashHex;
    return '${_ledgerHashHex.substring(0, 8)}...${_ledgerHashHex.substring(_ledgerHashHex.length - 4)}';
  }

  final List<String> _titles = const [
    'Starters',
    'Invitations',
    'Relationships',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stateManager = CapsuleStateManager(_hivra);
    Future.microtask(_bootstrapActiveRuntime);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ledgerWatcher?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _snapshotLedger();
    }
  }

  Future<void> _snapshotLedger() async {
    await _persistence.persistLedgerSnapshot(_hivra);
    await _persistence.exportBackupEnvelope(_hivra);
  }

  void _startLedgerWatcher() {
    _ledgerWatcher?.cancel();
    _ledgerWatcher = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _ledgerWatcherTickInProgress) return;
      _ledgerWatcherTickInProgress = true;

      try {
        final bootstrap = await _loadWorkerBootstrap();
        if (bootstrap != null) {
          final workerResult =
              await compute<Map<String, Object?>, Map<String, Object?>>(
            _receiveTransportMessagesInWorker,
            bootstrap,
          );
          final result = workerResult['result'] as int?;
          final ledgerJson = workerResult['ledgerJson'] as String?;
          if (ledgerJson != null && ledgerJson.isNotEmpty) {
            _hivra.importLedger(ledgerJson);
            if ((result ?? -1) >= 0) {
              await _persistence.persistLedgerSnapshot(_hivra);
            }
          }
        }

        _stateManager.refreshWithFullState();
        final nextVersion = _stateManager.state.version;
        if (nextVersion != _lastObservedLedgerVersion) {
          _lastObservedLedgerVersion = nextVersion;
          _loadCapsuleData();
        }
        if (nextVersion > _lastPromptedLedgerVersion) {
          _lastPromptedLedgerVersion = nextVersion;
          await _showBackupPrompt(nextVersion);
        }
      } catch (_) {
        // Ignore transient polling failures; UI must stay responsive.
      } finally {
        _ledgerWatcherTickInProgress = false;
      }
    });
  }

  Future<Map<String, Object?>?> _loadWorkerBootstrap() async {
    final activeHex = await _persistence.resolveActiveCapsuleHex(_hivra);
    CapsuleRuntimeBootstrap? bootstrap;
    if (activeHex != null && activeHex.isNotEmpty) {
      bootstrap = await _persistence.loadRuntimeBootstrap(activeHex);
    }
    bootstrap ??= await _persistence.loadRuntimeBootstrapForCurrent(_hivra);
    if (bootstrap == null) return null;

    return <String, Object?>{
      'seed': bootstrap.seed,
      'isGenesis': bootstrap.isGenesis,
      'isNeste': bootstrap.isNeste,
      'ledgerJson': bootstrap.ledgerJson,
    };
  }

  Future<void> _showBackupPrompt(int version) async {
    if (!mounted || _isBackupPromptOpen) return;
    _isBackupPromptOpen = true;
    try {
      final backupNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Capsule Changed'),
          content: Text(
            'Ledger updated to v$version. Export a backup now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Backup now'),
            ),
          ],
        ),
      );
      if (backupNow == true) {
        final path = await _persistence.exportBackupEnvelope(_hivra);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(path == null
                ? 'Backup export failed'
                : 'Backup exported: ${path.split('/').last}'),
          ),
        );
      }
    } finally {
      _isBackupPromptOpen = false;
    }
  }

  void _loadCapsuleData() {
    _stateManager.refreshWithFullState();
    final state = _stateManager.state;

    setState(() {
      _starterCount = state.starterCount;
      _relationshipCount = state.relationshipCount;
      _pendingInvitations = state.pendingInvitations;
      _isNeste = state.isNeste;
      _ledgerHashHex = state.ledgerHashHex;
      _ledgerVersion = state.version;
      _publicKeyHex =
          state.publicKey.isEmpty ? '' : base64.encode(state.publicKey);
      if (!_ledgerBaselineInitialized) {
        _lastObservedLedgerVersion = state.version;
        _lastPromptedLedgerVersion = state.version;
        _ledgerBaselineInitialized = true;
      }
    });
  }

  Future<void> _bootstrapActiveRuntime() async {
    final ok = await _persistence.bootstrapActiveCapsuleRuntime(_hivra);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _bootstrapping = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to bootstrap active capsule')),
      );
      return;
    }

    _loadCapsuleData();
    _startLedgerWatcher();
    setState(() {
      _bootstrapping = false;
    });
  }

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return StartersScreen(
          key: ValueKey('starters-$_ledgerVersion'),
          hivra: _hivra,
        );
      case 1:
        return InvitationsScreen(
          key: ValueKey('invitations-$_ledgerVersion'),
          hivra: _hivra,
        );
      case 2:
        return RelationshipsScreen(
          key: ValueKey('relationships-$_ledgerVersion'),
          hivra: _hivra,
        );
      case 3:
        return SettingsScreen(hivra: _hivra);
      default:
        return StartersScreen(
          key: ValueKey('starters-$_ledgerVersion'),
          hivra: _hivra,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(98),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _isNeste
                                  ? Colors.green.shade900
                                  : Colors.orange.shade900,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _isNeste ? 'NESTE' : 'HOOD',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isNeste
                                    ? Colors.green.shade300
                                    : Colors.orange.shade300,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _shortPublicKey,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            splashRadius: 16,
                            tooltip: 'Copy public key',
                            onPressed: _publicKeyHex.isEmpty
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: _publicKeyHex));
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Public key copied')),
                                    );
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildStatItem(
                            icon: Icons.grid_3x3,
                            value: _starterCount.toString(),
                            label: 'Starters',
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 16),
                          _buildStatItem(
                            icon: Icons.people,
                            value: _relationshipCount.toString(),
                            label: 'Relationships',
                            color: Colors.green,
                          ),
                          const SizedBox(width: 16),
                          _buildStatItem(
                            icon: Icons.mail,
                            value: _pendingInvitations.toString(),
                            label: 'Pending',
                            color: Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ledger v$_ledgerVersion · hash $_shortLedgerHash',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadCapsuleData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildCurrentScreen(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_3x3),
            label: 'Starters',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mail),
            label: 'Invitations',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Relationships',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
