import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_persistence_service.dart';

class BackupScreen extends StatefulWidget {
  final Uint8List seed;
  final bool isNewWallet;
  final bool isGenesis;

  const BackupScreen({
    super.key,
    required this.seed,
    this.isNewWallet = true,
    this.isGenesis = false,
  });

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final HivraBindings _hivra = HivraBindings();
  String? _mnemonic;
  String? _backupPath;

  @override
  void initState() {
    super.initState();
    _generateMnemonic();
  }

  void _generateMnemonic() {
    try {
      final phrase = _hivra.seedToMnemonic(widget.seed, wordCount: 24);
      setState(() {
        _mnemonic = phrase;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _copyToClipboard() {
    if (_mnemonic != null) {
      Clipboard.setData(ClipboardData(text: _mnemonic!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard!')),
      );
    }
  }

  Future<void> _exportBackup() async {
    try {
      final path = await CapsulePersistenceService().exportBackupEnvelope(_hivra);
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to export capsule backup')),
        );
        return;
      }
      setState(() {
        _backupPath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capsule backup saved: ${path.split('/').last}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup export failed: $e')),
      );
    }
  }

  Future<void> _continue() async {
    if (widget.isNewWallet) {
      await CapsulePersistenceService().persistAfterCreate(
        hivra: _hivra,
        seed: widget.seed,
        isGenesis: widget.isGenesis,
        isNeste: true,
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mnemonic == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final words = _mnemonic!.split(' ');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNewWallet ? 'Backup Your Capsule' : 'Seed Phrase'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Your Seed Phrase',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'This phrase is the ONLY way to restore your capsule.\n'
              'Store it securely. Never share it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(words.length, (index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${index + 1}. ${words[index]}'),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            if (_backupPath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Backup file: $_backupPath',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _copyToClipboard,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _exportBackup,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Backup'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _continue,
                    icon: const Icon(Icons.done),
                    label: Text(widget.isNewWallet ? 'Continue' : 'Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
