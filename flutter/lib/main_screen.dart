import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ffi/hivra_bindings.dart';
import 'screens/invitations_screen.dart';
import 'screens/relationships_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/starters_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final HivraBindings _hivra = HivraBindings();

  String _publicKeyHex = '';
  int _starterCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCapsuleData();
  }

  void _loadCapsuleData() {
    try {
      int count = 0;
      for (int i = 0; i < 5; i++) {
        if (_hivra.starterExists(i)) count++;
      }

      final firstStarter = _hivra.getStarterId(0);
      String pub = '';
      if (firstStarter != null) {
        pub = base64.encode(firstStarter.sublist(0, 16));
      }

      setState(() {
        _starterCount = count;
        _publicKeyHex = pub;
      });
    } catch (_) {
      setState(() {
        _publicKeyHex = 'Unavailable';
      });
    }
  }

  bool get _isGenesis => _starterCount == 5;

  static const List<Widget> _screens = <Widget>[
    StartersScreen(),
    InvitationsScreen(),
    RelationshipsScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isGenesis
                      ? Colors.green.withOpacity(0.15)
                      : Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isGenesis ? Colors.green : Colors.orange,
                  ),
                ),
                child: Text(
                  _isGenesis ? 'GENESIS' : 'PROTO',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: _isGenesis ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loadCapsuleData,
              )
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Public Key',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              if (_publicKeyHex.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: _publicKeyHex));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Public key copied')),
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _publicKeyHex.isEmpty ? 'Loading...' : _publicKeyHex,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Starter Slots',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(5, (index) {
              final filled = index < _starterCount;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: index < 4 ? 8 : 0),
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: filled ? Colors.blue : Colors.grey.shade800,
                    ),
                    color: filled
                        ? Colors.blue.withOpacity(0.15)
                        : Colors.transparent,
                  ),
                  child: Center(
                    child: Icon(
                      filled ? Icons.check : Icons.add,
                      size: 18,
                      color: filled ? Colors.blue : Colors.grey,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1),
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_3x3),
            label: 'Starters',
          ),
          NavigationDestination(
            icon: Icon(Icons.mail_outline),
            label: 'Invitations',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Relationships',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
