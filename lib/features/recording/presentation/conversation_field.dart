import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/agent_action.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/presentation/mic_activity.dart';
import 'package:voice_agent/features/recording/presentation/mic_button.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

/// The conversation field at the bottom of Dziś (workspace discussion
/// 2026-11-va-meals-dashboard, 03 §5): the mic with the owner's rule, one line
/// of state, and the reply in place with the way to the whole conversation.
/// On a matter's screen ([matterId]) what is said there is about the matter
/// (the subject is read from the screen on top when an utterance ends,
/// ADR-NET-008), and Napisz opens a new thread on the matter.
///
/// Typing opens the conversation, where typed turns already go into a voice
/// session (ADR-CORE-119 of personal-agent).
///
/// Under the reply stand the cards of what it did ([actionCard], ADR-NET-009),
/// on a screen that knows them.
class ConversationField extends ConsumerWidget {
  const ConversationField({super.key, this.matterId, this.diet = false, this.actionCard});

  /// The matter whose screen the field sits on; null on Dziś and the diet.
  final String? matterId;

  /// On the diet's screens: Napisz opens a new thread in Jedzenie, as a
  /// matter's opens one on the matter (ADR-NET-009).
  final bool diet;

  /// The card of one thing the reply did; null shows none (the reply's text
  /// says what was done).
  final Widget Function(AgentAction action)? actionCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reply = ref.watch(latestAgentReplyProvider);
    // A card stands under a reply for a meal; a queued utterance waits for the evening's story.
    final actions = actionCard == null
        ? const <AgentAction>[]
        : [
            for (final a in ref.watch(latestAgentActionsProvider))
              if (a.kind == AgentActionKind.mealLogged) a,
          ];
    final line = _stateLine(
      ref.watch(recordingControllerProvider),
      ref.watch(handsFreeControllerProvider),
      ref.watch(micModesEnabledProvider) ? ref.watch(micModeProvider) : null,
      onMatter: matterId != null,
    );
    final micModes = ref.watch(micModesEnabledProvider);
    final mode = ref.watch(micModeProvider);
    final scheme = Theme.of(context).colorScheme;
    // The whole bar shows the mic's state: a held button is under the finger.
    final activity = ref.watch(micActivityProvider);
    final colors = AppColors.of(context);
    final barColor = activity.capturing
        ? micActivityColor(activity, colors)
        : activity == MicActivity.listening
            ? colors.micListening.withValues(alpha: 0.18)
            : null;
    final onBar = activity.capturing ? colors.onMic : null;

    void openConversation() {
      final id = ref.read(sessionIdCoordinatorProvider).currentConversationId;
      if (id != null && id.isNotEmpty) {
        unawaited(context.push('/conversation/$id'));
      } else {
        context.go('/chat');
      }
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reply != null)
              Padding(
                key: const Key('field-reply'),
                padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(reply, maxLines: 4, overflow: TextOverflow.ellipsis),
                          for (final a in actions) actionCard!(a),
                          TextButton(
                            key: const Key('field-open-conversation'),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: openConversation,
                            child: const Text('Otwórz rozmowę ›'),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('field-reply-dismiss'),
                      icon: const Icon(Icons.close),
                      tooltip: 'Zamknij odpowiedź',
                      onPressed: () {
                        unawaited(ref.read(ttsServiceProvider).stop());
                        ref.read(latestAgentReplyProvider.notifier).state = null;
                        ref.read(latestAgentActionsProvider.notifier).state = const [];
                      },
                    ),
                  ],
                ),
              ),
            AnimatedContainer(
              key: const Key('field-bar'),
              duration: const Duration(milliseconds: 150),
              color: barColor ?? Colors.transparent,
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  const MicButton(key: Key('field-mic'), compact: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: activity.capturing
                        ? _CaptureLine(
                            // A new capture starts the clock from zero.
                            key: ValueKey(activity),
                            text: activity == MicActivity.recording
                                ? 'Nagrywam'
                                : 'Słyszę',
                            hint: activity == MicActivity.recording
                                ? ' — puść, by wysłać'
                                : '',
                            color: onBar,
                          )
                        : Text(
                            line,
                            key: const Key('field-state'),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                  ),
                  if (micModes && mode != MicMode.off)
                    TextButton(
                      key: const Key('field-stop'),
                      onPressed: () => unawaited(
                        ref.read(handsFreeControllerProvider.notifier).stopSession(),
                      ),
                      style: TextButton.styleFrom(foregroundColor: onBar),
                      child: const Text('Zakończ'),
                    ),
                  IconButton(
                    key: const Key('field-write'),
                    color: onBar,
                    icon: const Icon(Icons.keyboard_outlined),
                    tooltip: 'Napisz',
                    onPressed: matterId != null
                        ? () => unawaited(context.push('/conversation/new?matter=$matterId'))
                        : diet
                            ? () => unawaited(context.push('/conversation/new?subject=diet'))
                            : openConversation,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Nagrywam 0:04 — puść, by wysłać": the state with the seconds since the
/// capture began, ticking once a second.
class _CaptureLine extends StatefulWidget {
  const _CaptureLine({super.key, required this.text, required this.hint, this.color});

  final String text;
  final String hint;
  final Color? color;

  @override
  State<_CaptureLine> createState() => _CaptureLineState();
}

class _CaptureLineState extends State<_CaptureLine> {
  /// Whole seconds since the capture began, one per tick of the timer.
  int _seconds = 0;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _seconds;
    final clock = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Text(
      '${widget.text} $clock${widget.hint}',
      key: const Key('field-state'),
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: widget.color,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

/// One line of the field's state: what the mic does now.
String _stateLine(
  RecordingState rec,
  HandsFreeSessionState hf,
  MicMode? mode, {
  bool onMatter = false,
}) {
  if (rec is RecordingActive) return 'Nagrywam…';
  if (rec is RecordingTranscribing) return 'Przetwarzam…';
  if (rec is RecordingPaused) return 'Nagrywanie wstrzymane';
  if (hf is HandsFreeSessionError) return hf.message;
  if (hf is HandsFreeListening) {
    return switch (hf.phase) {
      HandsFreeListeningPhase.capturing => 'Słyszę…',
      HandsFreeListeningPhase.stopping => 'Przetwarzam…',
      HandsFreeListeningPhase.listening => 'Słucham…',
    };
  }
  if (mode == MicMode.standby) return 'Wstrzymane — stuknij, by słuchać';
  return onMatter ? 'Powiedz albo napisz w tej sprawie…' : 'Powiedz albo napisz…';
}
