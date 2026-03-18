import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';

class RecordPlaceholderScreen extends ConsumerWidget {
  const RecordPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isApiConfigured = ref.watch(apiUrlConfiguredProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: Column(
        children: [
          if (!isApiConfigured)
            MaterialBanner(
              content: const Text(
                'Set up your API endpoint in Settings to sync your transcripts.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.go('/settings'),
                  child: const Text('Go to Settings'),
                ),
              ],
            ),
          const Expanded(
            child: Center(
              child: Text('Record'),
            ),
          ),
        ],
      ),
    );
  }
}
