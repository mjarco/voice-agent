import 'dart:async';

import 'package:voice_agent/core/media_button/media_button_port.dart';

/// No-op [MediaButtonPort] for tests. Never emits events.
class StubMediaButtonPort implements MediaButtonPort {
  final _controller = StreamController<MediaButtonEvent>.broadcast();

  @override
  Stream<MediaButtonEvent> get events => _controller.stream;

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  /// Emits an event for testing.
  void emit(MediaButtonEvent event) => _controller.add(event);

  void dispose() => _controller.close();
}
