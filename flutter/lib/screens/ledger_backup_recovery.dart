import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ffi/hivra_bindings.dart';

class LedgerBackupRecovery {
  final HivraBindings _hivra = HivraBindings();

  /// Exports the Ledger to a local file
  Future<String?> exportLedgerToFile() async {
    final ledgerJson = _hivra.exportLedger();
    if (ledgerJson == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ledger.json');
    await file.writeAsString(ledgerJson);
    return file.path;
  }

  /// Imports the Ledger from a local file if it exists
  Future<bool> importLedgerFromFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ledger.json');
    if (!await file.exists()) return false;

    final ledgerJson = await file.readAsString();
    return _hivra.importLedger(ledgerJson);
  }

  /// Restores capsule with seed phrase and then tries to import Ledger.
  Future<void> restoreCapsule(String mnemonic) async {
    final seed = _hivra.mnemonicToSeed(mnemonic);
    final created = _hivra.createCapsule(seed);
    if (!created) {
      throw Exception('Failed to create capsule from provided mnemonic');
    }

    await importLedgerFromFile();
  }
}
