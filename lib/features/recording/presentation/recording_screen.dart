import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recordingControllerProvider);
    final controller = ref.read(recordingControllerProvider.notifier);
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
          Expanded(
            child: Center(
              child: _buildBody(context, state, controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    RecordingState state,
    RecordingController controller,
  ) {
    return switch (state) {
      RecordingIdle() => _IdleView(onRecord: controller.startRecording),
      RecordingActive() => _RecordingView(
          elapsed: controller.currentElapsed,
          onStop: controller.stopRecording,
          onCancel: controller.cancelRecording,
        ),
      RecordingCompleted(:final result) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              'Recording saved: ${result.duration.inSeconds}s',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: controller.resetToIdle,
              child: const Text('New Recording'),
            ),
          ],
        ),
      RecordingError(:final message) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: controller.resetToIdle,
              child: const Text('Try Again'),
            ),
          ],
        ),
    };
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onRecord});

  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onRecord,
          icon: const Icon(Icons.mic),
          iconSize: 64,
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(24),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap to record',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _RecordingView extends StatelessWidget {
  const _RecordingView({
    required this.elapsed,
    required this.onStop,
    required this.onCancel,
  });

  final Duration elapsed;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<Duration>(
          stream: Stream.periodic(
            const Duration(milliseconds: 200),
            (_) => elapsed,
          ),
          initialData: elapsed,
          builder: (context, snapshot) {
            final d = snapshot.data ?? Duration.zero;
            final minutes = d.inMinutes.toString().padLeft(2, '0');
            final seconds =
                (d.inSeconds % 60).toString().padLeft(2, '0');
            return Text(
              '$minutes:$seconds',
              style: Theme.of(context).textTheme.displayMedium,
            );
          },
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
            const SizedBox(width: 24),
            FilledButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ],
        ),
      ],
    );
  }
}
