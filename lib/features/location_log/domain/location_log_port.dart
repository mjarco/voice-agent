import 'package:voice_agent/features/location_log/domain/location_log_state.dart';

/// The native location pipeline (ADR-PLATFORM-009). It runs without Flutter;
/// this is only how Settings controls and reads it.
abstract class LocationLogPort {
  Future<LocationLogState> getState();
  Future<void> setCredentials({String? apiUrl, String? token});
  Future<void> setEnabled(bool enabled);

  /// "Alerty w sklepach": the geofences of places (ADR-PLATFORM-010), apart
  /// from the log's own switch.
  Future<void> setAlertsEnabled(bool enabled);

  Future<void> setMode(LocationLogMode mode);
  Future<void> setForegroundInterval(int seconds);
  Future<void> reconcile();

  /// The app came back to the foreground: the native side registers the
  /// geofences again if the location permission changed meanwhile.
  Future<void> appResumed();
  Future<void> openAppSettings();
  Future<void> requestPermissions();

  /// "Physical activity" for motion mode (ADR-PLATFORM-014); true when granted.
  Future<bool> requestMotionPermission();
}
