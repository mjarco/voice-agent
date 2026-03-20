import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/audio/audioplayers_audio_feedback_service.dart';

// ── FakeAudioPlayer ──────────────────────────────────────────────────────────

class FakeAudioPlayer implements AudioPlayer {
  final List<String> playedPaths = [];
  final _onCompleteController = StreamController<void>.broadcast();
  int stopCount = 0;
  int disposeCount = 0;
  ReleaseMode currentReleaseMode = ReleaseMode.release;

  /// Trigger the player-complete event (simulates end of a sound).
  void completePlayer() => _onCompleteController.add(null);

  @override
  Stream<void> get onPlayerComplete => _onCompleteController.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {
    currentReleaseMode = releaseMode;
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    if (source is AssetSource) {
      playedPaths.add(source.path);
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    unawaited(_onCompleteController.close());
  }

  // All other AudioPlayer members are unused — delegate via noSuchMethod.
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AudioplayersAudioFeedbackService', () {
    group('startProcessingFeedback', () {
      test('does nothing when disabled', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => false,
        );

        await svc.startProcessingFeedback();

        expect(player.playedPaths, isEmpty);
      });

      test('plays start jingle in release mode when enabled', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        await svc.startProcessingFeedback();

        expect(player.playedPaths, ['audio/processing_start.mp3']);
        expect(player.currentReleaseMode, ReleaseMode.release);
      });

      test('starts loop after start jingle completes', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        await svc.startProcessingFeedback();
        player.completePlayer();
        await Future.delayed(Duration.zero);

        expect(player.playedPaths, [
          'audio/processing_start.mp3',
          'audio/processing_loop.mp3',
        ]);
        expect(player.currentReleaseMode, ReleaseMode.loop);
      });

      test('does not start loop when disabled at callback time', () async {
        bool enabled = true;
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => enabled,
        );

        await svc.startProcessingFeedback();
        enabled = false;
        player.completePlayer();
        await Future.delayed(Duration.zero);

        expect(player.playedPaths, ['audio/processing_start.mp3']);
      });
    });

    group('stopLoop', () {
      test('calls player.stop()', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        await svc.stopLoop();

        expect(player.stopCount, 1);
      });

      test('prevents loop from starting after start jingle', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        await svc.startProcessingFeedback();
        await svc.stopLoop();

        player.completePlayer();
        await Future.delayed(Duration.zero);

        // Only the start jingle — no loop
        expect(player.playedPaths, ['audio/processing_start.mp3']);
      });
    });

    group('playSuccess', () {
      test('always calls stop regardless of enabled state', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => false,
        );

        await svc.playSuccess();

        expect(player.stopCount, greaterThanOrEqualTo(1));
      });

      test('plays success jingle in release mode when enabled', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        await svc.playSuccess();

        expect(player.stopCount, greaterThanOrEqualTo(1));
        expect(player.playedPaths, ['audio/processing_success.mp3']);
        expect(player.currentReleaseMode, ReleaseMode.release);
      });

      test('does not play jingle when disabled', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => false,
        );

        await svc.playSuccess();

        expect(player.playedPaths, isEmpty);
      });

      test('prevents pending loop callback from firing', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        await svc.startProcessingFeedback();
        await svc.playSuccess();

        player.completePlayer();
        await Future.delayed(Duration.zero);

        // start + success; no loop
        expect(
          player.playedPaths,
          ['audio/processing_start.mp3', 'audio/processing_success.mp3'],
        );
      });
    });

    group('playError', () {
      test('always calls stop regardless of enabled state', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => false,
        );

        await svc.playError();

        expect(player.stopCount, greaterThanOrEqualTo(1));
      });

      test('plays error jingle in release mode when enabled', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        await svc.playError();

        expect(player.playedPaths, ['audio/processing_error.mp3']);
        expect(player.currentReleaseMode, ReleaseMode.release);
      });

      test('does not play jingle when disabled', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => false,
        );

        await svc.playError();

        expect(player.playedPaths, isEmpty);
      });
    });

    group('dispose', () {
      test('calls player.dispose()', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        svc.dispose();

        // Allow async dispose() on FakeAudioPlayer to complete
        await Future.delayed(Duration.zero);

        expect(player.disposeCount, 1);
      });

      test('prevents loop from starting after start jingle', () async {
        final player = FakeAudioPlayer();
        final svc = AudioplayersAudioFeedbackService(
          player: player,
          getEnabled: () => true,
        );

        await svc.startProcessingFeedback();
        svc.dispose();

        // Stream close triggers StateError on the .first future;
        // catchError in startProcessingFeedback swallows it — no loop starts.
        await Future.delayed(Duration.zero);

        expect(player.playedPaths, ['audio/processing_start.mp3']);
      });
    });
  });
}
