import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/agent_action.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/widgets/glass.dart';
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
/// The line next to the mic is a text field: it takes the cursor and the
/// keyboard in place, its hint is the mic's state. Sending (the send key or
/// the arrow) opens the conversation with the text, and the thread sends it
/// there, where typed turns already go into a voice session (ADR-CORE-119 of
/// personal-agent): one way to send, the thread's.
///
/// Under the reply stand the cards of what it did ([actionCard], ADR-NET-009),
/// on a screen that knows them.
class ConversationField extends ConsumerStatefulWidget {
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
  ConsumerState<ConversationField> createState() => _ConversationFieldState();
}

class _ConversationFieldState extends ConsumerState<ConversationField> {
  final _text = TextEditingController();

  String? get matterId => widget.matterId;
  bool get diet => widget.diet;
  Widget Function(AgentAction action)? get actionCard => widget.actionCard;

  @override
  void initState() {
    super.initState();
    // The arrow shows only while there is something to send.
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Where a typed text goes, and Napisz with nothing typed: on a matter or
  /// the diet a new thread there; on Dziś the conversation of the voice
  /// session, or a new one when there is none.
  String _threadRoute() {
    if (matterId != null) return '/conversation/new?matter=$matterId';
    if (diet) return '/conversation/new?subject=diet';
    final id = ref.read(sessionIdCoordinatorProvider).currentConversationId;
    return id != null && id.isNotEmpty ? '/conversation/$id' : '/conversation/new';
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    FocusScope.of(context).unfocus();
    unawaited(context.push(_threadRoute(), extra: text));
  }

  @override
  Widget build(BuildContext context) {
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

    // The floating input of Aurora (off-roadmap S2): a glass pill over the
    // page, the round mic at its right end; the whole pill takes the mic's
    // colour while sound is captured.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: GlassSurface(
          key: const Key('field-glass'),
          radius: 28,
          blur: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                if (reply != null)
                  Padding(
                    key: const Key('field-reply'),
                    padding: const EdgeInsets.fromLTRB(20, 12, 4, 0),
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
                decoration: BoxDecoration(
                  color: barColor ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(28),
                ),
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.fromLTRB(20, 5, 5, 5),
                child: Row(
                  children: [
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
                          : TextField(
                              key: const Key('field-text'),
                              controller: _text,
                              minLines: 1,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15),
                              decoration: InputDecoration(
                                // The mic's state stands where the text goes.
                                hint: Text(
                                  line,
                                  key: const Key('field-state'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        fontSize: 15,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
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
                    if (_text.text.trim().isNotEmpty)
                      IconButton(
                        key: const Key('field-send'),
                        color: scheme.primary,
                        icon: const Icon(Icons.send),
                        tooltip: 'Wyślij',
                        onPressed: _send,
                      )
                    else
                      IconButton(
                        key: const Key('field-write'),
                        color: onBar ?? scheme.onSurfaceVariant,
                        // Not the Rozmowy tab's icon: this opens the
                        // conversation of the field, not the list.
                        icon: const Icon(Icons.chat_bubble_outline),
                        tooltip: 'Rozmowa',
                        onPressed: matterId != null || diet
                            ? () => unawaited(context.push(_threadRoute()))
                            : openConversation,
                      ),
                    const SizedBox(width: 4),
                    const MicButton(key: Key('field-mic'), compact: true),
                  ],
                ),
              ),
            ],
          ),
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
