import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/providers/agent_reply_provider.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/tts/tts_provider.dart';
import 'package:voice_agent/features/recording/domain/hands_free_session_state.dart';
import 'package:voice_agent/features/recording/domain/recording_state.dart';
import 'package:voice_agent/features/recording/presentation/mic_button.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

/// The conversation field at the bottom of Dziś (workspace discussion
/// 2026-11-va-meals-dashboard, 03 §5): the mic with the owner's rule, one line
/// of state, and the reply in place with the way to the whole conversation.
/// Its subject is Dzień, today's behaviour; subjects come with V3.
///
/// Typing opens the conversation, where typed turns already go into a voice
/// session (ADR-CORE-119 of personal-agent).
class ConversationField extends ConsumerWidget {
  const ConversationField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reply = ref.watch(latestAgentReplyProvider);
    final line = _stateLine(
      ref.watch(recordingControllerProvider),
      ref.watch(handsFreeControllerProvider),
      ref.watch(micModesEnabledProvider) ? ref.watch(micModeProvider) : null,
    );
    final micModes = ref.watch(micModesEnabledProvider);
    final mode = ref.watch(micModeProvider);
    final scheme = Theme.of(context).colorScheme;

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
                      },
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  const MicButton(key: Key('field-mic'), compact: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
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
                      child: const Text('Zakończ'),
                    ),
                  IconButton(
                    key: const Key('field-write'),
                    icon: const Icon(Icons.keyboard_outlined),
                    tooltip: 'Napisz',
                    onPressed: openConversation,
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

/// One line of the field's state: what the mic does now.
String _stateLine(
  RecordingState rec,
  HandsFreeSessionState hf,
  MicMode? mode,
) {
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
  return 'Powiedz albo napisz…';
}
