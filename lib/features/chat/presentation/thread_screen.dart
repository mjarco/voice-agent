import 'package:flutter/material.dart';

// Stub replaced by T3 with full thread screen implementation.
class ThreadScreen extends StatelessWidget {
  const ThreadScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thread')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
