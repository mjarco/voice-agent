import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'package:voice_agent/core/glasses_control/glasses_control_port.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';

/// [GlassesControlPort] over `GlassesControlBridge` of `MainActivity.kt`
/// (ADR-AUDIO-016). Unknown commands are dropped.
class GlassesControlService implements GlassesControlPort {
  GlassesControlService({EventChannel? eventChannel, MethodChannel? methodChannel})
    : _eventChannel =
          eventChannel ??
          const EventChannel('com.voiceagent/glasses_control/events'),
      _methodChannel =
          methodChannel ?? const MethodChannel('com.voiceagent/glasses_control');

  final EventChannel _eventChannel;
  final MethodChannel _methodChannel;

  /// One stream for every listener, as in NotificationActionService.
  @override
  late final Stream<GlassesCommand> commands = _eventChannel
      .receiveBroadcastStream()
      .map<GlassesCommand?>((dynamic event) {
        for (final command in GlassesCommand.values) {
          if (command.name == event) return command;
        }
        developer.log(
          'Unknown glasses command: $event',
          name: 'GlassesControlService',
        );
        return null;
      })
      .where((c) => c != null)
      .cast<GlassesCommand>();

  @override
  Future<void> reportMode(MicMode mode) async {
    try {
      await _methodChannel.invokeMethod<void>('reportMode', {'mode': mode.name});
    } on PlatformException catch (e) {
      developer.log('reportMode failed: $e', name: 'GlassesControlService');
    } on MissingPluginException {
      // No bridge (a test, an engine without the activity): nothing to tell.
    }
  }
}
