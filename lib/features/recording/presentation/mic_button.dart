import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

// ── Mic button ────────────────────────────────────────────────────────────────

/// The voice button, the same on every screen with a mic (the owner's rule,
/// workspace discussion 2026-11-va-meals-dashboard, 06 §3): a tap switches
/// listening on and off, a long press records only while held. [compact] is
/// the field's small button, without its label; the field says the state.
class MicButton extends ConsumerStatefulWidget {
  const MicButton({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends ConsumerState<MicButton> {
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

    // Tap-driven hands-free engagement (P038): mirror the Volume Up
    // gesture so the on-screen button is a UI parity affordance.
    // Idle (or in error state) → engage. Listening → suspend. The
    // legacy push-to-talk path stays on long-press; tapping here used
    // to start manual recording, but with always-on capture in place
    // long-press is the cleaner gesture for that intent.
    if (recState is RecordingIdle && ref.read(micModesEnabledProvider)) {
      // Android (ADR-AUDIO-013): the tap follows the mode.
      switch (ref.read(micModeProvider)) {
        case MicMode.off:
          ref.read(latestAgentReplyProvider.notifier).state = null;
          await ref.read(ttsServiceProvider).stop();
          await hfCtrl.startSession();
        case MicMode.listening:
          // Let a segment being written finish first; it is short.
          if (hfState is HandsFreeListening &&
              hfState.phase == HandsFreeListeningPhase.stopping) {
            return;
          }
          await hfCtrl.pauseSession();
        case MicMode.standby:
          await hfCtrl.resumeSession();
      }
    } else if (recState is RecordingIdle) {
      if (hfState is HandsFreeListening) {
        if (hfState.phase == HandsFreeListeningPhase.stopping) return;
        await hfCtrl.suspendByUser();
      } else if (hfState is HandsFreeIdle ||
          hfState is HandsFreeSessionError) {
        ref.read(latestAgentReplyProvider.notifier).state = null;
        await ref.read(ttsServiceProvider).stop();
        await hfCtrl.startSession();
      }
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
    if (hfState is HandsFreeListening &&
        hfState.phase == HandsFreeListeningPhase.stopping) {
      return;
    }

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
    final isHfCapturing = hfState is HandsFreeListening &&
        hfState.phase == HandsFreeListeningPhase.capturing;
    final isHfListeningQuiet = hfState is HandsFreeListening &&
        hfState.phase == HandsFreeListeningPhase.listening;
    final micModes = ref.watch(micModesEnabledProvider);
    final micMode = ref.watch(micModeProvider);
    final isStandby = micModes && micMode == MicMode.standby;
    final isModeListening = micModes && micMode == MicMode.listening;

    // Clear press-and-hold flag when recording returns to idle or errors out.
    // A held recording is felt (the finger hides the button, the owner's
    // remark of 2026-11-15): a firm tap when it has really started, two light
    // ones when it is sent. Only the button held fires them.
    ref.listen<RecordingState>(recordingControllerProvider, (prev, next) {
      if (_isPressAndHold) {
        final haptic = ref.read(hapticServiceProvider);
        if (next is RecordingActive && prev is! RecordingActive) {
          unawaited(haptic.mediumImpact());
        } else if (prev is RecordingActive && next is RecordingTranscribing) {
          unawaited(haptic.doubleTap());
        }
      }
      if ((next is RecordingIdle || next is RecordingError) && _isPressAndHold) {
        setState(() => _isPressAndHold = false);
      }
    });

    // Color reflects what the next tap does + what is currently going
    // on under the hood. Red = audio is actively being captured (manual
    // record OR VAD mid-utterance). Amber = engaged but quiet (gate
    // open, manual paused, or press-and-hold mid-recording). Grey =
    // transcribing in progress (button is non-interactive). Teal =
    // idle / available — tap to engage. Slate = paused by the owner.
    final colors = AppColors.of(context);
    final color = isTranscribing
        ? colors.micProcessing
        : isPaused
            ? colors.micListening
            : isRecording && _isPressAndHold
                ? colors.micListening
                : (isRecording || isHfCapturing)
                    ? colors.micRecording
                    : (isHfListeningQuiet || isModeListening)
                        ? colors.micListening
                        : isStandby
                            ? colors.micStandby
                            : colors.micIdle;

    final label = isPaused
        ? 'Pauza — stuknij, by wznowić'
        : isRecording
            ? (_isPressAndHold ? 'Puść, by wysłać' : 'Stuknij, by zakończyć')
            : isTranscribing
                ? 'Przetwarzam…'
                : isModeListening
                    ? 'Słucham — stuknij, by wstrzymać'
                    : isStandby
                        ? 'Wstrzymane — stuknij, by słuchać'
                        : isHfListeningQuiet
                            ? 'Słucham — stuknij, by przerwać'
                            : 'Stuknij, by słuchać';
    final size = widget.compact ? 46.0 : 96.0;
    final iconSize = widget.compact ? 26.0 : 48.0;

    final micButton = GestureDetector(
      onTap: _onTap,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            key: const Key('record-button'),
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              // Aurora's orb glows in its own colour (off-roadmap S2).
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 18)],
            ),
            child: isTranscribing
                ? Padding(
                    padding: EdgeInsets.all(size * 0.29),
                    child: CircularProgressIndicator(
                      color: colors.onMic,
                      strokeWidth: 3,
                    ),
                  )
                : (isPaused || (isStandby && !isRecording))
                    ? Icon(Icons.pause, color: colors.onMic, size: iconSize)
                    : Icon(Icons.mic, color: colors.onMic, size: iconSize),
          ),
          if (!widget.compact) ...[
            const SizedBox(height: 16),
            Text(
              label,
              key: const Key('record-button-label'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ],
      ),
    );

    // Android (ADR-AUDIO-013): Off from the app is a separate Stop, shown
    // whenever the mode is not Off. It sits outside the mic's gesture
    // detector so a long press on it is not push-to-talk.
    if (widget.compact || !micModes || micMode == MicMode.off) {
      return Semantics(label: label, button: true, child: micButton);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        micButton,
        const SizedBox(height: 8),
        TextButton(
          key: const Key('hf-stop-button'),
          onPressed: () async {
            await ref.read(handsFreeControllerProvider.notifier).stopSession();
            ref.read(toasterProvider).show('Rozmowa zakończona');
            await ref.read(hapticServiceProvider).lightImpact();
          },
          child: const Text('Zakończ'),
        ),
      ],
    );
  }
}

