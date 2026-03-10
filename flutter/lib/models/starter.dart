import 'package:flutter/material.dart';

enum StarterKind {
  juice('Juice', Colors.orange),
  spark('Spark', Colors.red),
  seed('Seed', Colors.green),
  pulse('Pulse', Colors.blue),
  kick('Kick', Colors.purple);

  const StarterKind(this.displayName, this.color);
  final String displayName;
  final Color color;
}

enum StarterState {
  active('Active'),
  burned('Burned'),
  locked('Locked');

  const StarterState(this.displayName);
  final String displayName;
}

class Starter {
  final String id;
  final StarterKind kind;
  final StarterState state;
  final String owner;
  final int slotIndex;
  final DateTime createdAt;

  Starter({
    required this.id,
    required this.kind,
    required this.state,
    required this.owner,
    required this.slotIndex,
    required this.createdAt,
  });

  // Mock starter for preview and test scenarios
  static Starter mock(int index) {
    final kinds = StarterKind.values;
    return Starter(
      id: 'starter_$index',
      kind: kinds[index % kinds.length],
      state: index == 2 ? StarterState.burned : StarterState.active,
      owner: '0xAA...',
      slotIndex: index,
      createdAt: DateTime.now().subtract(Duration(days: index)),
    );
  }
}
