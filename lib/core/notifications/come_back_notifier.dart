import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// PoC notifier — see docs/proposals/POC-come-back-notification.md.
/// iOS only for now. Singleton on purpose; if this graduates, refactor to a
/// Riverpod provider.
class ComeBackNotifier {
  ComeBackNotifier._();
  static final ComeBackNotifier instance = ComeBackNotifier._();

  static const int _notificationId = 1;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    // PoC: stay on UTC. zonedSchedule treats `now(local).add(delay)` as an
    // absolute instant, so the wall-clock offset is identical regardless of
    // which IANA zone is "local".

    const initSettings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _plugin.initialize(initSettings);
    _initialized = true;

    if (kDebugMode) {
      debugPrint('[ComeBackNotifier] initialized');
    }
  }

  Future<void> scheduleComeBack({
    Duration delay = const Duration(seconds: 30),
  }) async {
    if (!_initialized) return;

    final fireAt = tz.TZDateTime.now(tz.local).add(delay);

    await _plugin.zonedSchedule(
      _notificationId,
      'Come back',
      'You left voice-agent ${delay.inSeconds}s ago.',
      fireAt,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    if (kDebugMode) {
      debugPrint('[ComeBackNotifier] scheduled for $fireAt');
    }
  }

  Future<void> cancelComeBack() async {
    if (!_initialized) return;
    await _plugin.cancel(_notificationId);
    if (kDebugMode) {
      debugPrint('[ComeBackNotifier] cancelled');
    }
  }
}
