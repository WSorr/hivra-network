import 'package:flutter/material.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_state_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final HivraBindings _hivra = HivraBindings();
  bool _isNeste = true;
  bool _isRelay = false;

  @override
  void initState() {
    super.initState();
    final state = CapsuleStateManager(_hivra).state;
    _isNeste = state.isNeste;
  }

  void _showSeedPhrase() async {
    final seed = _hivra.loadSeed();
    if (seed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No seed found')),
      );
      return;
    }

    Navigator.pushNamed(
      context,
      '/backup',
      arguments: {
        'seed': seed,
        'isNewWallet': false,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          const SizedBox(height: 16),
          
          _buildSection(
            title: 'Security',
            children: [
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Switch capsule'),
                subtitle: const Text('Choose a different capsule'),
                onTap: () {
                  Navigator.pushReplacementNamed(
                    context,
                    '/',
                    arguments: {'autoSelectSingle': false},
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Show seed phrase'),
                subtitle: const Text('View your backup phrase'),
                onTap: _showSeedPhrase,
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Ledger inspector'),
                subtitle: const Text('View owner, hash and recent ledger events'),
                onTap: () => Navigator.pushNamed(context, '/ledger_inspector'),
              ),
            ],
          ),

          const Divider(),

          _buildSection(
            title: 'Network',
            children: [
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Network'),
                subtitle: Text(_isNeste ? 'Neste (main)' : 'Hood (test)'),
                trailing: Switch(
                  value: _isNeste,
                  onChanged: (value) {
                    setState(() {
                      _isNeste = value;
                    });
                  },
                ),
              ),
            ],
          ),

          const Divider(),

          if (Theme.of(context).platform == TargetPlatform.android) ...[
            _buildSection(
              title: 'Role',
              children: [
                ListTile(
                  leading: const Icon(Icons.sensors),
                  title: const Text('Relay mode'),
                  subtitle: Text(
                    _isRelay
                        ? 'Active (stores messages for trusted peers)'
                        : 'Inactive (leaf node only)'
                  ),
                  trailing: Switch(
                    value: _isRelay,
                    onChanged: (value) {
                      setState(() {
                        _isRelay = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const Divider(),
          ],

          _buildSection(
            title: 'Trusted Peers',
            children: [
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Add trusted peer'),
                subtitle: const Text('Manually add a peer to trust'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.list),
                title: const Text('View trusted peers'),
                subtitle: const Text('0 peers'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Coming soon')),
                  );
                },
              ),
            ],
          ),

          const Divider(),

          _buildSection(
            title: 'About',
            children: [
              const ListTile(
                leading: Icon(Icons.info),
                title: Text('Version'),
                subtitle: Text('Hivra v3.2 (dev)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade400,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}
