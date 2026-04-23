import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/session_control/hands_free_control_port.dart';
import 'package:voice_agent/core/session_control/session_control_provider.dart';
import 'package:voice_agent/core/session_control/toaster.dart';

/// No-op [HandsFreeControlPort] for tests that render the full app widget
/// tree. Prevents `UnimplementedError` from `handsFreeControlPortProvider`.
class StubHandsFreeControlPort implements HandsFreeControlPort {
  @override
  bool get isSuspendedForManualRecording => false;

  @override
  Future<void> stopSession() async {}
}

/// No-op [Toaster] for tests. Does not show any toasts.
class StubToaster extends Toaster {
  StubToaster() : super(GlobalKey<ScaffoldMessengerState>());

  @override
  void show(String message, {Duration duration = const Duration(seconds: 2)}) {
    // No-op in tests.
  }
}

/// Provider overrides for tests that build the full widget tree (via [App]).
///
/// These are required because `handsFreeControlPortProvider` and
/// `toasterProvider` throw by default and must be overridden.
List<Override> get sessionControlTestOverrides => [
      handsFreeControlPortProvider
          .overrideWithValue(StubHandsFreeControlPort()),
      toasterProvider.overrideWithValue(StubToaster()),
    ];
