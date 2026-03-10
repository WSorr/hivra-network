import 'dart:io';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../ffi/hivra_bindings.dart';
import '../services/capsule_backup_codec.dart';
import '../services/capsule_persistence_service.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final HivraBindings _hivra = HivraBindings();
  final TextEditingController _phraseController = TextEditingController();
  String? _errorMessage;
  String? _selectedBackupName;
  String? _selectedBackupLedgerJson;
  bool? _selectedBackupIsGenesis;
  bool _isValid = false;
  bool _isRecovering = false;

  @override
  void initState() {
    super.initState();
    _phraseController.addListener(_validatePhrase);
  }

  void _validatePhrase() {
    final phrase = _phraseController.text.trim();
    if (phrase.isEmpty) {
      setState(() {
        _isValid = false;
        _errorMessage = null;
      });
      return;
    }

    final isValid = _hivra.validateMnemonic(phrase);
    setState(() {
      _isValid = isValid;
      _errorMessage = isValid ? null : 'Invalid seed phrase';
    });
  }

  Future<void> _recover() async {
    if (!_isValid) return;

    setState(() {
      _isRecovering = true;
      _errorMessage = null;
    });

    try {
      final phrase = _phraseController.text.trim();
      final seed = _hivra.mnemonicToSeed(phrase);
      bool isGenesisRecovered = _selectedBackupIsGenesis ?? false;

      // Start from backup hint when available; otherwise Proto fallback.
      if (!_hivra.createCapsule(seed, isGenesis: isGenesisRecovered)) {
        throw Exception('Failed to create capsule from seed');
      }

      if (_selectedBackupLedgerJson != null) {
        final expectedOwner = _extractOwnerHexFromLedger(_selectedBackupLedgerJson!);
        final currentPubKey = _hivra.capsulePublicKey();
        final currentOwner = currentPubKey == null ? null : _bytesToHex(currentPubKey);
        if (expectedOwner != null && currentOwner != null && expectedOwner != currentOwner) {
          throw Exception('Selected backup does not match this seed phrase');
        }
      }

      final importedLedger = _selectedBackupLedgerJson != null
          ? _hivra.importLedger(_selectedBackupLedgerJson!)
          : await CapsulePersistenceService().importLedgerIfExists(_hivra);

      if (_selectedBackupLedgerJson != null && !importedLedger) {
        throw Exception('Failed to import selected backup ledger');
      }

      // If ledger was imported, re-create runtime with inferred type and replay ledger.
      if (importedLedger) {
        final inferredFromLedger = _inferGenesisFromLedgerJson(_hivra.exportLedger());
        isGenesisRecovered = inferredFromLedger ?? (_countOccupiedStarters() > 0);

        if (!_hivra.createCapsule(seed, isGenesis: isGenesisRecovered)) {
          throw Exception('Failed to re-create capsule with inferred type');
        }
        if (_selectedBackupLedgerJson != null) {
          if (!_hivra.importLedger(_selectedBackupLedgerJson!)) {
            throw Exception('Failed to import selected backup');
          }
        } else {
          await CapsulePersistenceService().importLedgerIfExists(_hivra);
        }
      }

      await CapsulePersistenceService().persistAfterCreate(
        hivra: _hivra,
        seed: seed,
        isGenesis: isGenesisRecovered,
        isNeste: true,
      );

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Recovery failed: $e';
        _isRecovering = false;
      });
    }
  }

  Future<void> _pickBackupFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;

      final raw = await File(file.path).readAsString();
      final ledgerJson = CapsuleBackupCodec.tryExtractLedgerJson(raw);
      if (ledgerJson == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Invalid backup file format';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _selectedBackupLedgerJson = ledgerJson;
        _selectedBackupName = file.name;
        _selectedBackupIsGenesis = _extractGenesisHintFromBackupJson(raw);
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Backup file read failed: $e';
      });
    }
  }

  int _countOccupiedStarters() {
    final raw = _hivra.exportLedger();
    if (raw == null || raw.trim().isEmpty) return 0;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return 0;
      final ledger = Map<String, dynamic>.from(decoded);
      final eventsRaw = ledger['events'];
      final events = eventsRaw is List ? eventsRaw : const [];

      final byKind = <int, String>{};

      for (final eventRaw in events) {
        if (eventRaw is! Map) continue;
        final event = Map<String, dynamic>.from(eventRaw);
        final kindCode = _eventKindCode(event['kind']);
        final payload = _decodePayloadBytes(event['payload']);
        if (payload == null) continue;

        if (kindCode == 5) {
          if (payload.length < 66) continue;
          final starterIdHex = _bytesToHex(payload.sublist(0, 32));
          final slot = payload[64];
          if (slot >= 0 && slot < 5) {
            byKind[slot] = starterIdHex;
          }
        } else if (kindCode == 6) {
          if (payload.length < 32) continue;
          final burnedHex = _bytesToHex(payload.sublist(0, 32));
          final toRemove = <int>[];
          byKind.forEach((slot, idHex) {
            if (idHex == burnedHex) {
              toRemove.add(slot);
            }
          });
          for (final slot in toRemove) {
            byKind.remove(slot);
          }
        }
      }

      return byKind.length;
    } catch (_) {
      return 0;
    }
  }

  String? _extractOwnerHexFromLedger(String ledgerJson) {
    try {
      final decoded = jsonDecode(ledgerJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final ownerBytes = _decodePayloadBytes(map['owner']);
      if (ownerBytes == null || ownerBytes.length != 32) return null;
      return _bytesToHex(ownerBytes);
    } catch (_) {
      return null;
    }
  }

  bool? _extractGenesisHintFromBackupJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final meta = map['meta'];
      if (meta is! Map) return null;
      final isGenesis = meta['is_genesis'];
      if (isGenesis is bool) return isGenesis;
    } catch (_) {
      // no-op
    }
    return null;
  }

  bool? _inferGenesisFromLedgerJson(String? ledgerJson) {
    if (ledgerJson == null || ledgerJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(ledgerJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final eventsRaw = map['events'];
      if (eventsRaw is! List) return null;

      for (final eventRaw in eventsRaw) {
        if (eventRaw is! Map) continue;
        final event = Map<String, dynamic>.from(eventRaw);
        final kindCode = _eventKindCode(event['kind']);
        if (kindCode != 0) continue;

        final payload = _decodePayloadBytes(event['payload']);
        if (payload == null || payload.length < 2) return null;
        final capsuleType = payload[1];
        if (capsuleType == 1) return true;
        if (capsuleType == 0) return false;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  int _eventKindCode(dynamic rawKind) {
    if (rawKind is num) return rawKind.toInt();
    if (rawKind is! String) return -1;
    switch (rawKind) {
      case 'CapsuleCreated':
        return 0;
      case 'StarterCreated':
        return 5;
      case 'StarterBurned':
        return 6;
      default:
        return -1;
    }
  }

  List<int>? _decodePayloadBytes(dynamic raw) {
    if (raw is List) {
      final out = <int>[];
      for (final item in raw) {
        if (item is! num) return null;
        final value = item.toInt();
        if (value < 0 || value > 255) return null;
        out.add(value);
      }
      return out;
    }

    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;

      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(trimmed) && trimmed.length.isEven) {
        final out = <int>[];
        for (int i = 0; i < trimmed.length; i += 2) {
          out.add(int.parse(trimmed.substring(i, i + 2), radix: 16));
        }
        return out;
      }

      try {
        return base64Decode(trimmed);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  String _bytesToHex(List<int> bytes) {
    final b = StringBuffer();
    for (final byte in bytes) {
      b.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recover Capsule'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter your seed phrase',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Type or paste your 12 or 24 word seed phrase to restore your capsule.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'Capsule type will be inferred automatically from recovered state.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'If local backup files exist (ledger.json or capsule-backup.v1.json), they will be imported automatically.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phraseController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter seed phrase...',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                suffixIcon: _isValid
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickBackupFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose Backup File (Optional)'),
            ),
            if (_selectedBackupName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Selected backup: $_selectedBackupName',
                style: const TextStyle(color: Colors.greenAccent),
              ),
            ],
            const SizedBox(height: 16),
            if (_isRecovering)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _isValid ? _recover : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Recover Capsule'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }
}
