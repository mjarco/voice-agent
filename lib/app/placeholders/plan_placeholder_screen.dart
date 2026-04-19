import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PlanPlaceholderScreen extends StatelessWidget {
  const PlanPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
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
            Icon(Icons.checklist, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Plan', style: TextStyle(fontSize: 20)),
            SizedBox(height: 8),
            Text(
              'Action items and goals',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
