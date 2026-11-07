import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'package:voice_agent/core/notification_actions/notification_action_port.dart';

/// [NotificationActionPort] over the `NotificationActionBridge` of
/// `MainActivity.kt`, which catches the plugin's button broadcast
/// (ADR-AUDIO-015). Unknown ids are dropped.
class NotificationActionService implements NotificationActionPort {
  NotificationActionService({EventChannel? eventChannel})
    : _eventChannel =
          eventChannel ??
          const EventChannel('com.voiceagent/notification_actions/events');

  final EventChannel _eventChannel;

  /// One stream for every listener: a second `receiveBroadcastStream`
  /// would replace the native handler, and its cancel would unregister
  /// the receiver of the first.
  @override
  late final Stream<NotificationAction> actions = _eventChannel
      .receiveBroadcastStream()
      .map<NotificationAction?>((dynamic event) {
        for (final action in NotificationAction.values) {
          if (action.name == event) return action;
        }
        developer.log(
          'Unknown notification action: $event',
          name: 'NotificationActionService',
        );
        return null;
      })
      .where((a) => a != null)
      .cast<NotificationAction>();
}
