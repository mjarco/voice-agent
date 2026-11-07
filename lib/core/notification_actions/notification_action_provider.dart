import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:voice_agent/core/notification_actions/notification_action_port.dart';
import 'package:voice_agent/core/notification_actions/notification_action_service.dart';

/// The notification's buttons exist on Android only.
final notificationActionProvider = Provider<NotificationActionPort>((ref) {
  return Platform.isAndroid
      ? NotificationActionService()
      : const NoNotificationActions();
});
