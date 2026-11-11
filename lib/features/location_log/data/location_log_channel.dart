import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voice_agent/features/location_log/domain/location_log_port.dart';
import 'package:voice_agent/features/location_log/domain/location_log_state.dart';

/// [LocationLogPort] over `com.voiceagent/location_log` (ADR-PLATFORM-005).
class LocationLogChannel implements LocationLogPort {
  LocationLogChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.voiceagent/location_log');

  final MethodChannel _channel;

  @override
  Future<LocationLogState> getState() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('getState');
    return LocationLogState.fromMap(map ?? const {});
  }

  @override
  Future<void> setCredentials({String? apiUrl, String? token}) => _channel
      .invokeMethod('setCredentials', {'apiUrl': apiUrl, 'token': token});

  @override
  Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod('setEnabled', {'enabled': enabled});

  @override
  Future<void> setAlertsEnabled(bool enabled) =>
      _channel.invokeMethod('setAlertsEnabled', {'enabled': enabled});

  @override
  Future<void> setMode(LocationLogMode mode) =>
      _channel.invokeMethod('setMode', {'mode': mode.wire});

  @override
  Future<void> setForegroundInterval(int seconds) =>
      _channel.invokeMethod('setForegroundInterval', {'seconds': seconds});

  @override
  Future<void> reconcile() => _channel.invokeMethod('reconcile');

  @override
  Future<void> appResumed() => _channel.invokeMethod('appResumed');

  @override
  Future<void> openAppSettings() => _channel.invokeMethod('openAppSettings');

  @override
  Future<bool> requestMotionPermission() async =>
      (await Permission.activityRecognition.request()).isGranted;

  /// The while-in-use dialog first: Android 11+ refuses "all the time" until
  /// that is granted, and then shows it on a settings page, not in a dialog.
  @override
  Future<void> requestPermissions() async {
    final foreground = await Permission.locationWhenInUse.request();
    if (!foreground.isGranted) return;
    await Permission.notification.request();
    await Permission.locationAlways.request();
  }
}
