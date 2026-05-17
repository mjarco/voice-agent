import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/notifications/domain/notification_service.dart';

/// Concrete [NotificationService] backed by `flutter_local_notifications`.
///
/// Foreground: app-scoped singleton (one instance per process lifetime).
/// Background isolate: constructed fresh per task spawn via `coreBoot()`
/// (ADR-PLATFORM-007); the in-memory snapshot starts empty and the first
/// reconcile re-schedules every desired entry — plugin replaces by ID, so
/// no user-visible flicker (ADR-NOTIF-001 "Cold-start rebuild").
class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final Map<int, ScheduledNotification> _scheduled = {};
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  bool _initialized = false;

  /// Stream of notification-tap payloads. Wired to the warm-path channel
  /// (`notificationTapStreamProvider`) by the provider layer in T3.
  Stream<String> get tapStream => _tapController.stream;

  @override
  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    final localName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localName));

    const initSettings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        // Permission is requested separately via requestPermission().
        // Init does not prompt — it just wires the callback.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _tapController.add(payload);
      },
    );

    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    final iosGranted = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;

    final androidGranted = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        false;

    // Either platform-resolver returns non-null at runtime; the other is null
    // (no-op). Granted-on-this-platform is the OR.
    return iosGranted || androidGranted;
  }

  @override
  Future<bool> isPermitted() async {
    final iosCheck = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.checkPermissions();
    if (iosCheck != null) {
      return iosCheck.isAlertEnabled;
    }
    final androidCheck = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    return androidCheck ?? false;
  }

  @override
  Future<void> schedule(ScheduledNotification n) async {
    // Summary IDs (1000–1003) use inexact scheduling (drift of minutes is
    // fine for daily summaries). Routine occurrence IDs (3M+) use exact
    // scheduling — the user expects the reminder near the appointment time.
    final scheduleMode = (n.id >= 1000 && n.id <= 1003)
        ? AndroidScheduleMode.inexactAllowWhileIdle
        : AndroidScheduleMode.exactAllowWhileIdle;

    await _plugin.zonedSchedule(
      n.id,
      n.title,
      n.body,
      n.fireAt,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        android: AndroidNotificationDetails(
          'agenda',
          'Agenda',
          channelDescription: 'Daily summaries and routine reminders',
          importance: Importance.defaultImportance,
        ),
      ),
      payload: n.payload,
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    _scheduled[n.id] = n;
  }

  @override
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
    _scheduled.remove(id);
  }

  @override
  Future<Map<int, ScheduledNotification>> currentlyScheduled() async {
    return Map<int, ScheduledNotification>.unmodifiable(_scheduled);
  }

  @override
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    _scheduled.clear();
  }
}
