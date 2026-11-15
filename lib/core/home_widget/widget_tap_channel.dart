import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a tap on the home-screen widget asks for (ADR-PLATFORM-015).
enum WidgetTap {
  /// The calories: the diet's day, over Dziś.
  food,

  /// The tasks: Dziś.
  tasks,

  /// The matters: the Sprawy tab.
  matters,

  /// The mic: Dziś, listening.
  listen;

  static WidgetTap? of(String? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// Taps on the widget, over `com.voiceagent/widget_tap`, in the pattern of
/// ADR-PLATFORM-008 (as the arrival alerts' taps): [takeInitialTap] gives the
/// tap that launched the app, and [taps] every tap after it, so one tap
/// reaches one of them. Kotlin drops a launch from recents, which would
/// otherwise repeat the last tap (and start listening again).
class WidgetTapChannel {
  WidgetTapChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.voiceagent/widget_tap');

  final MethodChannel _channel;

  /// Single subscription: a tap during boot waits for the app to listen.
  final _taps = StreamController<WidgetTap>();

  Stream<WidgetTap> get taps => _taps.stream;

  /// Call once, before `runApp`.
  Future<WidgetTap?> takeInitialTap() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return WidgetTap.of(await _channel.invokeMethod<String>('takeInitialTap'));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } finally {
      _channel.setMethodCallHandler(_onCall);
    }
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'tapped') return;
    final tap = WidgetTap.of(call.arguments as String?);
    if (tap != null) _taps.add(tap);
  }
}
