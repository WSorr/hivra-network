import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'screens/capsule_selector_screen.dart';
import 'screens/first_launch_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/recovery_screen.dart';
import 'screens/main_screen.dart';
import 'screens/ledger_inspector_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hivra',
      theme: ThemeData.dark(),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            final args = settings.arguments as Map<String, dynamic>?;
            final autoSelect = args?['autoSelectSingle'] as bool? ?? true;
            return MaterialPageRoute(
              builder: (_) => CapsuleSelectorScreen(autoSelectSingle: autoSelect),
            );
          case '/first_launch':
            return MaterialPageRoute(builder: (_) => const FirstLaunchScreen());
          case '/recovery':
            return MaterialPageRoute(builder: (_) => const RecoveryScreen());
          case '/backup':
            final args = settings.arguments as Map<String, dynamic>?;
            return MaterialPageRoute(
              builder: (_) => BackupScreen(
                seed: args?['seed'] ?? Uint8List(0),
                isNewWallet: args?['isNewWallet'] ?? false,
                isGenesis: args?['isGenesis'] ?? false,
              ),
            );
          case '/main':
            return MaterialPageRoute(builder: (_) => const MainScreen());
          case '/ledger_inspector':
            return MaterialPageRoute(builder: (_) => const LedgerInspectorScreen());
          default:
            return MaterialPageRoute(builder: (_) => const CapsuleSelectorScreen());
        }
      },
    );
  }
}
