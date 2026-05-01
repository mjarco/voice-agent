import 'package:voice_agent/core/background/background_service.dart';

/// No-op [BackgroundService] for tests. Avoids platform dependency on
/// `flutter_foreground_task`.
class StubBackgroundService implements BackgroundService {
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Future<void> startService() async => _running = true;

  @override
  Future<void> stopService({
    AudioSessionTarget target = AudioSessionTarget.playback,
  }) async =>
      _running = false;

  @override
  Future<void> updateNotification({
    required String title,
    required String body,
  }) async {}
}
