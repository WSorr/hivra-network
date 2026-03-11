import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/screens/first_launch_screen.dart';

void main() {
  testWidgets('first launch screen renders main actions', (WidgetTester tester) async {
    await tester.pumpWidget(const TestApp(child: FirstLaunchScreen()));

    expect(find.text('Welcome to Hivra'), findsOneWidget);
    expect(find.text('Choose your starting point'), findsOneWidget);
    expect(find.text('PROTO'), findsOneWidget);
    expect(find.text('GENESIS'), findsOneWidget);
    expect(find.text('Create Proto'), findsOneWidget);
    expect(find.text('Create Genesis'), findsOneWidget);
    expect(find.text('Recover Capsule'), findsOneWidget);
  });
}

class TestApp extends StatelessWidget {
  const TestApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: child);
  }
}
