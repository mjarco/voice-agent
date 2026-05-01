import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voice_agent/core/audio/keep_alive_silent_player.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/media_button/media_button_port.dart';
import 'package:voice_agent/core/media_button/media_button_provider.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/domain/segment_job.dart';
import 'package:voice_agent/features/recording/presentation/recording_controller.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  StreamSubscription<MediaButtonEvent>? _mediaButtonSub;
  MediaButtonPort? _mediaButtonPort;
  KeepAliveSilentPlayer? _keepAlivePlayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(handsFreeControllerProvider.notifier).startSession();
        _activateMediaButton();
        _keepAlivePlayer = KeepAliveSilentPlayer();
      }
    });
  }

  void _activateMediaButton() {
    _mediaButtonPort = ref.read(mediaButtonProvider);
    unawaited(_mediaButtonPort!.activate());
    _mediaButtonSub = _mediaButtonPort!.events.listen(_onMediaButtonEvent);
  }

  void _onMediaButtonEvent(MediaButtonEvent event) {
    final ttsPlaying = ref.read(ttsPlayingProvider);
    final ttsIsSpeakingDirect = ref.read(ttsServiceProvider).isSpeaking.value;
    final recStateSnap = ref.read(recordingControllerProvider);
    final hfStateSnap = ref.read(handsFreeControllerProvider);
    debugPrint(
      '[MediaButtonDbg] _onMediaButtonEvent event=$event '
      'ttsPlayingProvider=$ttsPlaying ttsIsSpeaking.value=$ttsIsSpeakingDirect '
      'recState=${recStateSnap.runtimeType} hfState=${hfStateSnap.runtimeType}',
    );
    if (event != MediaButtonEvent.togglePlayPause) return;

    if (ttsPlaying) {
      debugPrint('[MediaButtonDbg] branch=stopTts');
      unawaited(ref.read(ttsServiceProvider).stop());
      return;
    }

    final recState = ref.read(recordingControllerProvider);
    final hfState = ref.read(handsFreeControllerProvider);
    final recCtrl = ref.read(recordingControllerProvider.notifier);
    final hfCtrl = ref.read(handsFreeControllerProvider.notifier);

    if (recState is RecordingActive) {
      debugPrint('[MediaButtonDbg] branch=pauseRecording');
      unawaited(recCtrl.pauseRecording());
    } else if (recState is RecordingPaused) {
      debugPrint('[MediaButtonDbg] branch=resumeRecording');
      unawaited(recCtrl.resumeRecording());
    } else if (hfState is HandsFreeListening ||
        hfState is HandsFreeWithBacklog ||
        hfState is HandsFreeCapturing) {
      debugPrint('[MediaButtonDbg] branch=hfSuspend');
      unawaited(hfCtrl.toggleUserSuspend().then((_) {
        ref.read(toasterProvider).show('Paused');
        ref.read(hapticServiceProvider).lightImpact();
      }));
    } else if (hfState is HandsFreeSuspendedByUser) {
      debugPrint('[MediaButtonDbg] branch=hfResume');
      unawaited(hfCtrl.toggleUserSuspend().then((_) {
        ref.read(toasterProvider).show('Resumed');
        ref.read(hapticServiceProvider).lightImpact();
      }));
    } else {
      debugPrint('[MediaButtonDbg] branch=noop');
    }
  }

  @override
  void dispose() {
    _mediaButtonSub?.cancel();
    unawaited(_mediaButtonPort?.deactivate());
    unawaited(_keepAlivePlayer?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RecordingState>(recordingControllerProvider, (prev, next) {
      if (next is RecordingIdle) {
        final hfCtrl = ref.read(handsFreeControllerProvider.notifier);
        if (hfCtrl.isSuspendedForManualRecording) {
          unawaited(hfCtrl.resumeAfterManualRecording());
        }
      }
    });

    ref.listen(appConfigProvider.select((c) => c.vadConfig), (prev, next) {
      unawaited(ref.read(handsFreeControllerProvider.notifier).reloadVadConfig());
    });

    // Clear agent reply when hands-free starts capturing
    ref.listen<HandsFreeSessionState>(handsFreeControllerProvider, (prev, next) {
      if (next is HandsFreeCapturing) {
        ref.read(latestAgentReplyProvider.notifier).state = null;
      }
    });

    // Pause VAD while TTS is playing to avoid mic picking up speaker output.
    ref.listen<bool>(ttsPlayingProvider, (prev, next) {
      final hfCtrl = ref.read(handsFreeControllerProvider.notifier);
      if (next) {
        unawaited(hfCtrl.suspendForTts());
      } else {
        unawaited(hfCtrl.resumeAfterTts());
      }
    });

    // P034 follow-up: keep a silent loop playing while hands-free is in
    // listening / capture / suspended-by-user states so iOS treats this
    // app as actively producing audio output. Without this, AirPods
    // hardware-button presses are rejected during listening (no playback
    // → no media-button routing). Stopped during TTS (the TTS audio is
    // already real output).
    ref.listen<HandsFreeSessionState>(handsFreeControllerProvider, (prev, next) {
      final ttsPlaying = ref.read(ttsPlayingProvider);
      final shouldKeepAlive = !ttsPlaying &&
          (next is HandsFreeListening ||
              next is HandsFreeWithBacklog ||
              next is HandsFreeCapturing ||
              next is HandsFreeSuspendedByUser);
      if (shouldKeepAlive) {
        unawaited(_keepAlivePlayer?.start());
      } else {
        unawaited(_keepAlivePlayer?.stop());
      }
    });
    ref.listen<bool>(ttsPlayingProvider, (prev, next) {
      // When TTS starts, silence loop must yield to TTS output.
      // When TTS finishes and hands-free is listening, resume silence.
      if (next) {
        unawaited(_keepAlivePlayer?.stop());
      } else {
        final hfState = ref.read(handsFreeControllerProvider);
        if (hfState is HandsFreeListening ||
            hfState is HandsFreeWithBacklog ||
            hfState is HandsFreeCapturing ||
            hfState is HandsFreeSuspendedByUser) {
          unawaited(_keepAlivePlayer?.start());
        }
      }
    });

    final recState = ref.watch(recordingControllerProvider);
    final hfState = ref.watch(handsFreeControllerProvider);
    final recCtrl = ref.read(recordingControllerProvider.notifier);
    final hfCtrl = ref.read(handsFreeControllerProvider.notifier);
    final isApiConfigured = ref.watch(apiUrlConfiguredProvider);
    final agentReply = ref.watch(latestAgentReplyProvider);

    final isNewConversationDisabled = recState is RecordingActive ||
        recState is RecordingPaused ||
        recState is RecordingTranscribing ||
        hfState is HandsFreeCapturing ||
        hfState is HandsFreeStopping;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record'),
        actions: [
          IconButton(
            key: const Key('new-conversation-button'),
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New conversation',
            onPressed: isNewConversationDisabled
                ? null
                : () {
                    ref.read(sessionIdCoordinatorProvider).resetSession();
                    ref.read(toasterProvider).show('New conversation');
                    ref.read(hapticServiceProvider).lightImpact();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/record/history'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!isApiConfigured)
            MaterialBanner(
              content: const Text(
                'Set up your API endpoint in Settings to sync your transcripts.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.push('/settings'),
                  child: const Text('Go to Settings'),
                ),
              ],
            ),
          Expanded(
            child: Center(
              child: _buildRecordingArea(context, recState, recCtrl),
            ),
          ),
          _AgentReplyCard(
            reply: agentReply,
            isSpeaking: ref.watch(ttsPlayingProvider),
            onStop: () => ref.read(ttsServiceProvider).stop(),
            onDismiss: () {
              unawaited(ref.read(ttsServiceProvider).stop());
              ref.read(latestAgentReplyProvider.notifier).state = null;
            },
          ),
          _HandsFreeSection(
            hfState: hfState,
            onRetry: () => hfCtrl.startSession(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingArea(
    BuildContext context,
    RecordingState state,
    RecordingController controller,
  ) {
    return switch (state) {
      RecordingIdle() ||
      RecordingActive() ||
      RecordingPaused() ||
      RecordingTranscribing() =>
        const _MicButton(),
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
                onPressed: () => context.push('/settings'),
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

// ── Agent reply card ─────────────────────────────────────────────────────────

class _AgentReplyCard extends StatelessWidget {
  const _AgentReplyCard({
    required this.reply,
    required this.isSpeaking,
    required this.onStop,
    required this.onDismiss,
  });

  final String? reply;
  final bool isSpeaking;
  final VoidCallback onStop;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: reply != null
          ? Card(
              key: const Key('agent-reply-card'),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(reply!)),
                      if (isSpeaking)
                        IconButton(
                          key: const Key('agent-reply-stop'),
                          icon: const Icon(Icons.stop_circle),
                          onPressed: onStop,
                          tooltip: 'Stop speaking',
                        ),
                      IconButton(
                        key: const Key('agent-reply-dismiss'),
                        icon: const Icon(Icons.close),
                        onPressed: onDismiss,
                        tooltip: 'Dismiss agent reply',
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

// ── Hands-free section ────────────────────────────────────────────────────────

class _HandsFreeSection extends StatelessWidget {
  const _HandsFreeSection({
    required this.hfState,
    required this.onRetry,
  });

  final HandsFreeSessionState hfState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isOn = hfState is! HandsFreeIdle;
    final jobs = _jobsOf(hfState);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        if (isOn) ...[
          _HfStatusStrip(hfState: hfState, onRetry: onRetry),
          if (jobs.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: _SegmentList(jobs: jobs),
            ),
        ],
        const _VadParamsStrip(),
      ],
    );
  }

  static List<SegmentJob> _jobsOf(HandsFreeSessionState s) => switch (s) {
        HandsFreeListening(:final jobs) => jobs,
        HandsFreeWithBacklog(:final jobs) => jobs,
        HandsFreeCapturing(:final jobs) => jobs,
        HandsFreeStopping(:final jobs) => jobs,
        HandsFreeSuspendedByUser(:final jobs) => jobs,
        HandsFreeSessionError(:final jobs) => jobs,
        HandsFreeIdle() => const [],
      };
}

class _HfStatusStrip extends StatelessWidget {
  const _HfStatusStrip({required this.hfState, required this.onRetry});

  final HandsFreeSessionState hfState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (hfState) {
      HandsFreeSessionError(
        :final message,
        :final requiresSettings,
        :final requiresAppSettings,
      ) =>
        _ErrorStrip(
          message: message,
          requiresSettings: requiresSettings,
          requiresAppSettings: requiresAppSettings,
          onRetry: onRetry,
        ),
      HandsFreeListening() => const _StatusText('Listening...'),
      HandsFreeCapturing() => const _StatusText('Capturing...'),
      HandsFreeStopping() => const _StatusText('Processing segment...'),
      HandsFreeWithBacklog() => const _StatusText('Listening (jobs pending)...'),
      HandsFreeSuspendedByUser() => const _StatusText('Listening paused'),
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
    required this.onRetry,
  });

  final String message;
  final bool requiresSettings;
  final bool requiresAppSettings;
  final VoidCallback onRetry;

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
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
          Row(
            children: [
              OutlinedButton(
                key: const Key('hf-retry-button'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
              if (requiresAppSettings)
                TextButton(
                  onPressed: () => context.push('/settings'),
                  child: const Text('Go to Settings'),
                )
              else if (requiresSettings)
                TextButton(
                  onPressed: openAppSettings,
                  child: const Text('Open Settings'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Mic button ────────────────────────────────────────────────────────────────

class _MicButton extends ConsumerStatefulWidget {
  const _MicButton();

  @override
  ConsumerState<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends ConsumerState<_MicButton> {
  /// True between [_onLongPressStart] and [_onLongPressEnd].
  /// Prevents the trailing [onTap] that Flutter fires after a long press.
  bool _longPressActive = false;

  /// True when the current recording was started by a long press.
  /// Drives the orange button colour. Cleared when state returns to idle or error.
  bool _isPressAndHold = false;

  Future<void> _onTap() async {
    if (_longPressActive) return; // trailing tap from a long press — ignore

    final recState = ref.read(recordingControllerProvider);
    final hfState = ref.read(handsFreeControllerProvider);
    final recCtrl = ref.read(recordingControllerProvider.notifier);
    final hfCtrl = ref.read(handsFreeControllerProvider.notifier);

    if (recState is RecordingIdle) {
      if (hfState is HandsFreeStopping) return; // no-op — wait for stop
      ref.read(latestAgentReplyProvider.notifier).state = null;
      await ref.read(ttsServiceProvider).stop();
      await hfCtrl.suspendForManualRecording();
      await recCtrl.startRecording();
    } else if (recState is RecordingActive) {
      await recCtrl.stopAndTranscribe();
    } else if (recState is RecordingPaused) {
      await recCtrl.resumeRecording();
    }
    // RecordingTranscribing → no-op
    // RecordingError → handled by error view in _buildRecordingArea
  }

  Future<void> _onLongPressStart(LongPressStartDetails _) async {
    final recState = ref.read(recordingControllerProvider);
    final hfState = ref.read(handsFreeControllerProvider);

    // Only start if idle and engine not stopping.
    if (recState is! RecordingIdle) return;
    if (hfState is HandsFreeStopping) return;

    _longPressActive = true;
    setState(() => _isPressAndHold = true);

    ref.read(latestAgentReplyProvider.notifier).state = null;
    final recCtrl = ref.read(recordingControllerProvider.notifier);
    final hfCtrl = ref.read(handsFreeControllerProvider.notifier);
    await ref.read(ttsServiceProvider).stop();
    await hfCtrl.suspendForManualRecording();
    await recCtrl.startRecording();
  }

  Future<void> _onLongPressEnd(LongPressEndDetails _) async {
    _longPressActive = false;

    final recState = ref.read(recordingControllerProvider);
    if (recState is! RecordingActive) return;

    await ref
        .read(recordingControllerProvider.notifier)
        .stopAndTranscribe(silentOnEmpty: true);
  }

  @override
  Widget build(BuildContext context) {
    final recState = ref.watch(recordingControllerProvider);
    final hfState = ref.watch(handsFreeControllerProvider);
    final isRecording = recState is RecordingActive;
    final isPaused = recState is RecordingPaused;
    final isTranscribing = recState is RecordingTranscribing;
    final isHfCapturing = hfState is HandsFreeCapturing;

    // Clear press-and-hold flag when recording returns to idle or errors out.
    ref.listen<RecordingState>(recordingControllerProvider, (_, next) {
      if ((next is RecordingIdle || next is RecordingError) && _isPressAndHold) {
        setState(() => _isPressAndHold = false);
      }
    });

    final color = isTranscribing
        ? Colors.grey
        : isPaused
            ? Colors.orange
            : isRecording && _isPressAndHold
                ? Colors.orange
                : (isRecording || isHfCapturing)
                    ? Colors.red
                    : Colors.green;

    final label = isPaused
        ? 'Paused — tap to resume'
        : isRecording
            ? (_isPressAndHold ? 'Release to stop' : 'Tap to stop')
            : isTranscribing
                ? 'Transcribing...'
                : 'Tap to record';

    return GestureDetector(
      onTap: _onTap,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            key: const Key('record-button'),
            duration: const Duration(milliseconds: 150),
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: isTranscribing
                ? const Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : isPaused
                    ? const Icon(Icons.pause, color: Colors.white, size: 48)
                    : const Icon(Icons.mic, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
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

// ── VAD params strip ─────────────────────────────────────────────────────────

/// Compact read-only summary of current VAD config shown at the bottom of the
/// screen. Always visible. Tapping navigates to Advanced Settings.
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

