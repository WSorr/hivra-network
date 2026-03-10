import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../ffi/hivra_bindings.dart';

class BackupScreen extends StatefulWidget {
  final Uint8List seed;
  final bool isNewWallet;
  const BackupScreen({super.key, required this.seed, this.isNewWallet = true});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final HivraBindings _hivra = HivraBindings();
  String? _ledgerJson;
  String? _statusMessage;
  String? _ledgerPath;
  String? _mnemonic;

  @override
  void initState() {
    super.initState();
    _generateMnemonic();
    _exportLedger();
  }

  void _generateMnemonic() {
    try {
      final phrase = _hivra.seedToMnemonic(widget.seed, wordCount: 24);
      setState(() => _mnemonic = phrase);
    } catch (_) {
      setState(() => _mnemonic = null);
    }
  }

  void _exportLedger() {
    try {
      final result = _hivra.exportLedger();
      setState(() {
        _ledgerJson = result;
        _statusMessage = result == null ? 'Failed to export ledger' : 'Ledger exported successfully';
      });
    } catch (e) {
      setState(() {
        _ledgerJson = null;
        _statusMessage = 'Failed to export ledger: $e';
      });
    }
  }

  Future<File?> _writeLedgerFile(String json, {String? forcedPath}) async {
    final path = forcedPath ??
        '${(await getApplicationDocumentsDirectory()).path}/hivra-ledger-${DateTime.now().toIso8601String()}.json';
    final file = File(path);
    await file.writeAsString(json);
    if (!mounted) return file;
    setState(() {
      _ledgerPath = file.path;
      _statusMessage = 'Ledger saved as ${file.uri.pathSegments.last}';
    });
    return file;
  }

  Future<void> _saveLedgerWithPicker() async {
    if (_ledgerJson == null) return;
    try {
      final initialName = 'hivra-ledger-${DateTime.now().toIso8601String()}.json';
      final location = await getSaveLocation(
        suggestedName: initialName,
        acceptedTypeGroups: [
          XTypeGroup(label: 'JSON', mimeTypes: ['application/json']),
        ],
      );
      if (location == null) return;
      await _writeLedgerFile(_ledgerJson!, forcedPath: location.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ledger saved to selected folder')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  void _showLedgerQr() {
    if (_ledgerJson == null) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Backup QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: _ledgerJson!,
                version: QrVersions.auto,
                size: 220,
                gapless: true,
              ),
              const SizedBox(height: 12),
              const Text(
                'Scan this QR code to import the backup on another device.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Seed (keep safe):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(
              _mnemonic ?? 'Generating seed phrase…',
              style: const TextStyle(letterSpacing: 1.2),
            ),
            const SizedBox(height: 16),
            const Text('Ledger JSON:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(
              _ledgerJson ?? 'Ledger export failed',
              style: TextStyle(
                color: _ledgerJson == null ? Colors.redAccent : Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (_statusMessage != null)
              Text(
                _statusMessage!,
                style: TextStyle(color: _ledgerJson == null ? Colors.redAccent : Colors.greenAccent),
              ),
            if (_ledgerPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Backup file: $_ledgerPath',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _ledgerJson != null
                      ? () {
                          final ledgerText = _ledgerJson!;
                          Clipboard.setData(ClipboardData(text: ledgerText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ledger copied to clipboard')),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Ledger'),
                ),
                ElevatedButton.icon(
                  onPressed: _ledgerJson != null ? _saveLedgerWithPicker : null,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Save backup'),
                ),
                ElevatedButton.icon(
                  onPressed: _ledgerJson != null
                      ? () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final ledgerText = _ledgerJson!;
                            final file = await _writeLedgerFile(ledgerText);
                            if (file == null) throw Exception('Failed to write backup file');
                            if (!mounted) return;
                            await SharePlus.instance.share(
                              ShareParams(
                                files: [XFile(file.path)],
                                text: 'Hivra Ledger backup',
                              ),
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Share failed: $e')),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
                ElevatedButton.icon(
                  onPressed: _ledgerJson != null ? _showLedgerQr : null,
                  icon: const Icon(Icons.qr_code),
                  label: const Text('QR'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final HivraBindings _hivra = HivraBindings();
  final TextEditingController _seedController = TextEditingController();
  final TextEditingController _ledgerController = TextEditingController();
  String? _status;

  void _recover() {
    try {
      final seedText = _seedController.text.trim();
      final ledgerJson = _ledgerController.text.trim();

      if (seedText.isEmpty) throw Exception('Seed required');

      final seedBytes = Uint8List.fromList(seedText.split(',').map((e) => int.parse(e)).toList());
      _hivra.createCapsule(seedBytes);

      if (ledgerJson.isNotEmpty) {
        final ok = _hivra.importLedger(ledgerJson);
        if (!ok) throw Exception('Failed to import ledger');
      }

      setState(() { _status = ledgerJson.isNotEmpty ? 'Recovery + ledger import successful' : 'Recovery successful'; });
    } catch (e) {
      setState(() { _status = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter Seed:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _seedController, decoration: const InputDecoration(hintText: 'Comma-separated bytes')),
            const SizedBox(height: 16),
            const Text('Ledger JSON (optional):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _ledgerController, decoration: const InputDecoration(hintText: 'Paste Ledger JSON'), maxLines: 5),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _recover, child: const Text('Recover')),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(
                _status!,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _status!.startsWith('Error') ? Colors.redAccent : Colors.greenAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
