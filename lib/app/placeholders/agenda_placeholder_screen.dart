import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AgendaPlaceholderScreen extends StatelessWidget {
  const AgendaPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
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
            Icon(Icons.calendar_today, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Agenda', style: TextStyle(fontSize: 20)),
            SizedBox(height: 8),
            Text(
              'Daily tasks and routine schedule',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
