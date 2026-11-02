import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:voice_agent/core/providers/deep_link_providers.dart';

/// Text shared to the app on Android, over `com.voiceagent/share`
/// (ADR-PLATFORM-008): [takeInitialText] gives what launched the app, and
/// [texts] everything shared after it.
class SharedTextChannel {
  SharedTextChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.voiceagent/share');

  final MethodChannel _channel;

  /// Single subscription: a share during boot waits for the app to listen.
  final _texts = StreamController<SharedText>();

  Stream<SharedText> get texts => _texts.stream;

  /// Call once, before `runApp`. The warm path opens only after this read, so
  /// one share never reaches both channels.
  Future<String?> takeInitialText() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('takeInitialText');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } finally {
      _channel.setMethodCallHandler(_onCall);
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'sharedText') {
      _texts.add(SharedText(call.arguments as String));
    }
  }
}
