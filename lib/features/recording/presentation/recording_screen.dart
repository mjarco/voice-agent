import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';
import 'package:voice_agent/features/recording/presentation/hands_free_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recState = ref.watch(recordingControllerProvider);
    final hfState = ref.watch(handsFreeControllerProvider);
    final recCtrl = ref.read(recordingControllerProvider.notifier);
    final hfCtrl = ref.read(handsFreeControllerProvider.notifier);
    final isApiConfigured = ref.watch(apiUrlConfiguredProvider);

    final isHfActive = hfState is! HandsFreeIdle;
    final isRecActive = recState is RecordingActive;

    ref.listen<RecordingState>(recordingControllerProvider, (prev, next) {
      if (next is RecordingCompleted) {
        context.push('/record/review', extra: next.result);
        recCtrl.resetToIdle();
      }
    });

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
              child: _buildRecordingArea(context, recState, recCtrl, isHfActive, hfState),
            ),
          ),
          _HandsFreeSection(
            hfState: hfState,
            hfCtrl: hfCtrl,
            isRecActive: isRecActive,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingArea(
    BuildContext context,
    RecordingState state,
    RecordingController controller,
    bool isHfActive,
    HandsFreeSessionState hfState,
  ) {
    return switch (state) {
      RecordingIdle() => isHfActive
          ? _HfMicIndicator(hfState: hfState)
          : _IdleView(onRecord: controller.startRecording),
      RecordingActive() => _RecordingView(
          elapsed: controller.currentElapsed,
          onStop: controller.stopAndTranscribe,
          onCancel: controller.cancelRecording,
        ),
      RecordingTranscribing() => const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Transcribing...'),
          ],
        ),
      RecordingCompleted() => const SizedBox.shrink(),
      RecordingError(
        :final message,
        :final requiresSettings,
        :final requiresAppSettings,
      ) =>
        Column(
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
            if (requiresAppSettings)
              FilledButton.icon(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings),
                label: const Text('Go to Settings'),
              )
            else if (requiresSettings)
              FilledButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              )
            else
              FilledButton(
                onPressed: controller.resetToIdle,
                child: const Text('Try Again'),
              ),
          ],
        ),
    };
  }
}

// ── Hands-free section ────────────────────────────────────────────────────────

class _HandsFreeSection extends StatelessWidget {
  const _HandsFreeSection({
    required this.hfState,
    required this.hfCtrl,
    required this.isRecActive,
  });

  final HandsFreeSessionState hfState;
  final HandsFreeController hfCtrl;
  final bool isRecActive;

  @override
  Widget build(BuildContext context) {
    final isOn = hfState is! HandsFreeIdle;
    final jobs = _jobsOf(hfState);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        SwitchListTile(
          key: const Key('hf-toggle'),
          title: const Text('Hands-free'),
          value: isOn,
          onChanged: isRecActive
              ? null
              : (on) =>
                  on ? hfCtrl.startSession() : hfCtrl.stopSession(),
        ),
        const _VadParamsStrip(),
        if (isOn) ...[
          _HfStatusStrip(hfState: hfState),
          if (jobs.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: _SegmentList(jobs: jobs),
            ),
        ],
      ],
    );
  }

  static List<SegmentJob> _jobsOf(HandsFreeSessionState s) => switch (s) {
        HandsFreeListening(:final jobs) => jobs,
        HandsFreeWithBacklog(:final jobs) => jobs,
        HandsFreeCapturing(:final jobs) => jobs,
        HandsFreeStopping(:final jobs) => jobs,
        HandsFreeSessionError(:final jobs) => jobs,
        HandsFreeIdle() => const [],
      };
}

class _HfStatusStrip extends StatelessWidget {
  const _HfStatusStrip({required this.hfState});

  final HandsFreeSessionState hfState;

  @override
  Widget build(BuildContext context) {
    return switch (hfState) {
      HandsFreeSessionError(:final message, :final requiresSettings, :final requiresAppSettings) =>
        _ErrorStrip(
          message: message,
          requiresSettings: requiresSettings,
          requiresAppSettings: requiresAppSettings,
        ),
      HandsFreeListening() => const _StatusText('Listening...'),
      HandsFreeCapturing() => const _StatusText('Capturing...'),
      HandsFreeStopping() => const _StatusText('Processing segment...'),
      HandsFreeWithBacklog() => const _StatusText('Listening (jobs pending)...'),
      HandsFreeIdle() => const SizedBox.shrink(),
    };
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        key: const Key('hf-status-text'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({
    required this.message,
    required this.requiresSettings,
    required this.requiresAppSettings,
  });

  final String message;
  final bool requiresSettings;
  final bool requiresAppSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            key: const Key('hf-error-message'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
          if (requiresAppSettings)
            TextButton(
              onPressed: () => context.go('/settings'),
              child: const Text('Go to Settings'),
            )
          else if (requiresSettings)
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }
}

// ── Segment list ──────────────────────────────────────────────────────────────

class _SegmentList extends StatelessWidget {
  const _SegmentList({required this.jobs});

  final List<SegmentJob> jobs;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('hf-segment-list'),
      shrinkWrap: true,
      itemCount: jobs.length,
      itemBuilder: (context, index) {
        // index 0 = most recent segment
        final job = jobs[jobs.length - 1 - index];
        return _SegmentTile(job: job);
      },
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({required this.job});

  final SegmentJob job;

  @override
  Widget build(BuildContext context) {
    final (icon, subtitle, color) = _renderJob(job.state);
    return ListTile(
      dense: true,
      leading: icon,
      title: Text(job.label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      iconColor: color,
      textColor: color,
    );
  }

  (Widget, String?, Color?) _renderJob(SegmentJobState s) {
    return switch (s) {
      QueuedForTranscription() => (
          const Icon(Icons.hourglass_empty),
          'Queued',
          Colors.grey,
        ),
      Transcribing() => (
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          'Transcribing...',
          null,
        ),
      Persisting() => (
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          'Saving...',
          null,
        ),
      Completed() => (
          const Icon(Icons.check_circle),
          'Saved',
          Colors.green,
        ),
      Rejected(:final reason) => (
          const Icon(Icons.not_interested),
          'Skipped: $reason',
          Colors.grey,
        ),
      JobFailed(:final message) => (
          const Icon(Icons.error_outline),
          'Failed: $message',
          Colors.red,
        ),
    };
  }
}

// ── Recording area sub-widgets ────────────────────────────────────────────────

/// Mic button shown in place of the normal record button during a HF session.
/// Green = listening for speech; red = speech detected (with 300ms release debounce).
class _HfMicIndicator extends StatefulWidget {
  const _HfMicIndicator({required this.hfState});

  final HandsFreeSessionState hfState;

  @override
  State<_HfMicIndicator> createState() => _HfMicIndicatorState();
}

class _HfMicIndicatorState extends State<_HfMicIndicator> {
  static const _releaseDebounce = Duration(milliseconds: 300);

  bool _capturing = false;
  Timer? _releaseTimer;

  @override
  void didUpdateWidget(_HfMicIndicator old) {
    super.didUpdateWidget(old);
    final nowCapturing = widget.hfState is HandsFreeCapturing;
    if (nowCapturing == _capturing) return;

    if (nowCapturing) {
      _releaseTimer?.cancel();
      setState(() => _capturing = true);
    } else {
      _releaseTimer?.cancel();
      _releaseTimer = Timer(_releaseDebounce, () {
        if (mounted) setState(() => _capturing = false);
      });
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _capturing ? Colors.red : Colors.green;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          key: const Key('record-button'),
          onPressed: null,
          icon: const Icon(Icons.mic),
          iconSize: 64,
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(24),
            backgroundColor: color,
            disabledBackgroundColor: color,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Hands-free active',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onRecord});

  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          key: const Key('record-button'),
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

// ── VAD params strip ─────────────────────────────────────────────────────────

/// Compact read-only summary of current VAD config shown below the Hands-free
/// toggle. Always visible (not gated on isOn) so the user can see the active
/// settings even when hands-free is off. Tapping navigates to Advanced Settings.
class _VadParamsStrip extends ConsumerWidget {
  const _VadParamsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vad = ref.watch(appConfigProvider.select((c) => c.vadConfig));
    final label =
        'thr ${vad.positiveSpeechThreshold.toStringAsFixed(2)} · '
        'hang ${vad.hangoverMs}ms · '
        'min ${vad.minSpeechMs}ms · '
        'pre ${vad.preRollMs}ms';
    return InkWell(
      key: const Key('vad-params-strip'),
      onTap: () => context.push('/settings/advanced'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                key: const Key('vad-params-text'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Icon(
              Icons.tune,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
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
