import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RoutinesPlaceholderScreen extends StatelessWidget {
  const RoutinesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Routines', style: TextStyle(fontSize: 20)),
            SizedBox(height: 8),
            Text(
              'Recurring habits and schedules',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
