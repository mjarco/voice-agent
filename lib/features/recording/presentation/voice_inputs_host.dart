import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/audio/ambient_loop_player.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/media_button/media_button_port.dart';
import 'package:voice_agent/core/media_button/media_button_provider.dart';
import 'package:voice_agent/core/observability/telemetry.dart';
import 'package:voice_agent/core/volume_button/volume_button_port.dart';
import 'package:voice_agent/core/volume_button/volume_button_provider.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

/// The voice inputs that live as long as the app's shell: the headset's and
/// the volume keys' gestures, and the listeners the mic's gestures need (a
/// long press resuming hands-free after it, the speech settings reloaded, the
/// last reply cleared when a new utterance starts). They lived on Record
/// until Record stopped being a tab (V1 of the redesign); the shell holds
/// them now, so every screen with a mic shares one set.
class VoiceInputsHost extends ConsumerStatefulWidget {
  const VoiceInputsHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VoiceInputsHost> createState() => _VoiceInputsHostState();
}

class _VoiceInputsHostState extends ConsumerState<VoiceInputsHost> {
  StreamSubscription<MediaButtonEvent>? _mediaButtonSub;
  MediaButtonPort? _mediaButtonPort;
  StreamSubscription<VolumeButtonEvent>? _volumeButtonSub;
  VolumeButtonPort? _volumeButtonPort;
  AmbientLoopPlayer? _ambientPlayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // P037 v2: app opens in Idle. User engages explicitly via
        // AirPods short-click (handled in _onMediaButtonEvent) or the
        // mic UI button. The previous auto-startSession in initState
        // is removed — that was the continuous-listening contract from
        // the pre-v2 model.
        _activateMediaButton();
        _activateVolumeButton();
        // EXPERIMENT: AmbientLoopPlayer disabled. `audioplayers` package
        // takes ownership of the AVAudioSession on play/stop, which tears
        // down the recorder's I/O unit and kills the mic — exactly the
        // failure mode the always-on capture model is trying to avoid.
        // Without this player there is no listening tone; will be added
        // back via a different audio path once gate semantics are stable.
        // _ambientPlayer = AmbientLoopPlayer();
        // unawaited(_ambientPlayer!.setMode(AmbientMode.idle));
      }
    });
  }

  void _activateMediaButton() {
    _mediaButtonPort = ref.read(mediaButtonProvider);
    // Android (ADR-AUDIO-015): the hands-free controller owns the media
    // session, from entering Listening to Off; the screen only listens.
    _ownsMediaSession = !ref.read(micModesEnabledProvider);
    if (_ownsMediaSession) unawaited(_mediaButtonPort!.activate());
    _mediaButtonSub = _mediaButtonPort!.events.listen(_onMediaButtonEvent);
  }

  bool _ownsMediaSession = false;

  void _activateVolumeButton() {
    _volumeButtonPort = ref.read(volumeButtonProvider);
    unawaited(_volumeButtonPort!.activate());
    _volumeButtonSub = _volumeButtonPort!.events.listen(_onVolumeButtonEvent);
  }

  /// Volume UP → engage (start hands-free listening). Volume DOWN →
  /// suspend (close gate / disengage). Used as a fallback hardware
  /// gesture for lock-screen capture, since `MPRemoteCommand` events
  /// are blocked by iOS while `.playAndRecord` has an active mic
  /// engine. Volume buttons travel a different routing path that is
  /// not gated by the call-mode rule.
  void _onVolumeButtonEvent(VolumeButtonEvent event) {
    final hfState = ref.read(handsFreeControllerProvider);
    final hfCtrl = ref.read(handsFreeControllerProvider.notifier);
    final ttsPlaying = ref.read(ttsPlayingProvider);
    // P039 T6 — record the press; downstream effect is driven by the
    // existing switch below.
    Telemetry.instance.event('input.volume_button', attrs: {
      'direction': event.name,
      'tts_playing': ttsPlaying,
      'hf_state': hfState.runtimeType.toString(),
    });
    debugPrint(
      '[VolumeBtnDbg] _onVolumeButtonEvent event=$event hfState=${hfState.runtimeType} ttsPlaying=$ttsPlaying',
    );

    switch (event) {
      case VolumeButtonEvent.up:
        if (hfState is HandsFreeIdle || hfState is HandsFreeSessionError) {
          debugPrint('[VolumeBtnDbg] branch=engage');
          unawaited(hfCtrl.startSession().then((_) {
            ref.read(toasterProvider).show('Listening');
            ref.read(hapticServiceProvider).lightImpact();
          }));
        } else {
          debugPrint('[VolumeBtnDbg] branch=up-noop (already engaged)');
        }
      case VolumeButtonEvent.down:
        if (ttsPlaying) {
          // Volume-down during TTS: interrupt the agent's reply but
          // keep the listening gate open. resumeAfterTts (wired to
          // ttsPlayingProvider flipping to false) will reopen the
          // gate automatically.
          debugPrint('[VolumeBtnDbg] branch=stopTts');
          unawaited(ref.read(ttsServiceProvider).stop());
        } else if (hfState is HandsFreeListening) {
          debugPrint('[VolumeBtnDbg] branch=suspend');
          unawaited(hfCtrl.suspendByUser().then((_) {
            ref.read(toasterProvider).show('Paused');
            ref.read(hapticServiceProvider).lightImpact();
          }));
        } else {
          debugPrint('[VolumeBtnDbg] branch=down-noop (not engaged, no TTS)');
        }
    }
  }

  void _onMediaButtonEvent(MediaButtonEvent event) {
    final ttsPlaying = ref.read(ttsPlayingProvider);
    final ttsIsSpeakingDirect = ref.read(ttsServiceProvider).isSpeaking.value;
    final recStateSnap = ref.read(recordingControllerProvider);
    final hfStateSnap = ref.read(handsFreeControllerProvider);
    // P039 T6 — record the press. Only togglePlayPause has a behavior
    // path today, but emit for all event kinds so unrecognised hardware
    // events are still observable.
    Telemetry.instance.event('input.media_button', attrs: {
      'button': event.name,
      'tts_playing': ttsPlaying,
      'rec_state': recStateSnap.runtimeType.toString(),
      'hf_state': hfStateSnap.runtimeType.toString(),
    });
    debugPrint(
      '[MediaButtonDbg] _onMediaButtonEvent event=$event '
      'ttsPlayingProvider=$ttsPlaying ttsIsSpeaking.value=$ttsIsSpeakingDirect '
      'recState=${recStateSnap.runtimeType} hfState=${hfStateSnap.runtimeType}',
    );
    if (event != MediaButtonEvent.togglePlayPause) return;

    if (ref.read(micModesEnabledProvider)) {
      _onMediaButtonToggleMicModes(ttsPlaying: ttsPlaying);
      return;
    }

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
    } else if (hfState is HandsFreeIdle) {
      // P037 v2: AirPods short-click in Idle → engage to Listening.
      // This is the new entry point that replaces the legacy
      // toggleUserSuspend "resume" branch.
      debugPrint('[MediaButtonDbg] branch=engage');
      unawaited(hfCtrl.startSession().then((_) {
        ref.read(toasterProvider).show('Listening');
        ref.read(hapticServiceProvider).lightImpact();
      }));
    } else if (hfState is HandsFreeListening) {
      // iOS blocks media buttons during .playAndRecord with active mic, so
      // this branch rarely fires in production. Kept as a no-op fallthrough
      // for completeness — the listening session ends naturally via VAD or
      // the 30 s auto-disengage timer (T6).
      debugPrint('[MediaButtonDbg] branch=listening-noop (iOS-blocked path)');
    } else {
      debugPrint('[MediaButtonDbg] branch=noop');
    }
  }

  /// Android (ADR-AUDIO-013): the headset toggles Listening ↔ Standby, like
  /// play/pause in a media player. A manual recording keeps its own
  /// pause/resume. In Off the press only stops a reply being spoken: the
  /// session starts from the mic button alone.
  void _onMediaButtonToggleMicModes({required bool ttsPlaying}) {
    final recState = ref.read(recordingControllerProvider);
    final recCtrl = ref.read(recordingControllerProvider.notifier);
    final hfCtrl = ref.read(handsFreeControllerProvider.notifier);
    if (recState is RecordingActive) {
      unawaited(recCtrl.pauseRecording());
      return;
    }
    if (recState is RecordingPaused) {
      unawaited(recCtrl.resumeRecording());
      return;
    }
    switch (ref.read(micModeProvider)) {
      case MicMode.listening:
        unawaited(hfCtrl.pauseSession().then((_) {
          ref.read(toasterProvider).show('Standby');
          ref.read(hapticServiceProvider).lightImpact();
        }));
      case MicMode.standby:
        unawaited(hfCtrl.resumeSession().then((_) {
          ref.read(toasterProvider).show('Listening');
          ref.read(hapticServiceProvider).lightImpact();
        }));
      case MicMode.off:
        if (ttsPlaying) unawaited(ref.read(ttsServiceProvider).stop());
    }
  }

  @override
  void dispose() {
    _mediaButtonSub?.cancel();
    if (_ownsMediaSession) unawaited(_mediaButtonPort?.deactivate());
    _volumeButtonSub?.cancel();
    unawaited(_volumeButtonPort?.deactivate());
    unawaited(_ambientPlayer?.dispose());
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
      if (next is HandsFreeListening &&
          next.phase == HandsFreeListeningPhase.capturing) {
        ref.read(latestAgentReplyProvider.notifier).state = null;
      }
    });

    // TTS suspend/resume is wired at the controller level (in
    // HandsFreeController's constructor). Doing it in this widget via
    // `ref.listen` does not survive the lock-screen UI pause —
    // controller-level listeners are bound to the provider scope and
    // fire reliably whether the widget tree is visible or not.

    // P037 v2: AmbientLoopPlayer drives the audible engagement state.
    //   Idle (no TTS)       → silence_loop.wav (volume 0) — keeps iOS
    //                         treating us as active media participant.
    //   Listening (no TTS)  → listening_loop.wav (low volume) — audible
    //                         "I'm listening" cue.
    //   TTS playing         → off (TTS is its own output).
    void syncAmbient() {
      final ttsPlaying = ref.read(ttsPlayingProvider);
      final hfState = ref.read(handsFreeControllerProvider);
      AmbientMode target;
      if (ttsPlaying) {
        target = AmbientMode.off;
      } else if (hfState is HandsFreeListening) {
        target = AmbientMode.listening;
      } else {
        target = AmbientMode.idle;
      }
      unawaited(_ambientPlayer?.setMode(target));
    }
    ref.listen<HandsFreeSessionState>(handsFreeControllerProvider, (_, _) => syncAmbient());
    ref.listen<bool>(ttsPlayingProvider, (_, _) => syncAmbient());

    return widget.child;
  }
}
