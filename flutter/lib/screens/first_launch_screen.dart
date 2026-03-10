import 'package:flutter/material.dart';
import '../ffi/hivra_bindings.dart';

class FirstLaunchScreen extends StatefulWidget {
  const FirstLaunchScreen({super.key});

  @override
  State<FirstLaunchScreen> createState() => _FirstLaunchScreenState();
}

class _FirstLaunchScreenState extends State<FirstLaunchScreen> {
  final HivraBindings _hivra = HivraBindings();

  void _createCapsule(String type) async {
    try {
      final seed = _hivra.generateRandomSeed();
      final isGenesis = type == 'genesis';
      final success = _hivra.createCapsule(
        seed, 
        isNeste: true, 
        isGenesis: isGenesis,
      );
      
      if (!success) throw Exception('Failed to create capsule');
      
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/backup',
          arguments: {
            'seed': seed,
            'isNewWallet': true,
            'isGenesis': isGenesis,
          },
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _recoverCapsule() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recovery'),
        content: const Text(
          'Recovery from Ledger will be implemented when Ledger is ready.\n\n'
          'For now, use seed phrase recovery.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/recovery');
            },
            child: const Text('Use Seed Phrase'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Hivra'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const Text(
                    'Choose your starting point',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // PROTO
                  _buildOptionCard(
                    title: 'PROTO',
                    icon: Icons.circle_outlined,
                    iconColor: Colors.grey,
                    description: 'Empty capsule\n5 empty slots\nReceive invitations only',
                    buttonText: 'Create Proto',
                    buttonColor: Colors.grey,
                    onPressed: () => _createCapsule('proto'),
                  ),

                  const SizedBox(height: 14),

                  // GENESIS
                  _buildOptionCard(
                    title: 'GENESIS',
                    icon: Icons.star,
                    iconColor: Colors.orange,
                    description: 'Full capsule\n5 starters (Juice, Spark, Seed, Pulse, Kick)\nSend and receive invitations',
                    buttonText: 'Create Genesis',
                    buttonColor: Colors.orange,
                    onPressed: () => _createCapsule('genesis'),
                  ),

                  const SizedBox(height: 18),

                  // RECOVER
                  OutlinedButton.icon(
                    onPressed: _recoverCapsule,
                    icon: const Icon(Icons.restore),
                    label: const Text('Recover Capsule'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String description,
    required String buttonText,
    required Color buttonColor,
    required VoidCallback onPressed,
  }) {
    return Card(
      elevation: 4,
      color: iconColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: iconColor),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, height: 1.35),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 42),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}
