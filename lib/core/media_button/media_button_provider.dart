import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voice_agent/core/media_button/media_button_port.dart';
import 'package:voice_agent/core/media_button/media_button_service.dart';

/// Provides a [MediaButtonPort] backed by platform channels.
final mediaButtonProvider = Provider<MediaButtonPort>((ref) {
  return MediaButtonService();
});
