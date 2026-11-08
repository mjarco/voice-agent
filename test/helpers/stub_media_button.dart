import 'dart:async';

import 'package:voice_agent/core/media_button/media_button_port.dart';

/// No-op [MediaButtonPort] for tests. Never emits events.
class StubMediaButtonPort implements MediaButtonPort {
  final _controller = StreamController<MediaButtonEvent>.broadcast();

  @override
  Stream<MediaButtonEvent> get events => _controller.stream;

  /// Every activate / deactivate / claim, in order.
  final List<String> calls = [];

  @override
  Future<void> activate() async => calls.add('activate');

  @override
  Future<void> deactivate() async => calls.add('deactivate');

  @override
  Future<void> claim() async => calls.add('claim');

  /// Emits an event for testing.
  void emit(MediaButtonEvent event) => _controller.add(event);

  void dispose() => _controller.close();
}
