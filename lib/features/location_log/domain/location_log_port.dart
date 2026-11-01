import 'package:voice_agent/features/location_log/domain/location_log_state.dart';

/// The native location pipeline (ADR-PLATFORM-009). It runs without Flutter;
/// this is only how Settings controls and reads it.
abstract class LocationLogPort {
  Future<LocationLogState> getState();
  Future<void> setCredentials({String? apiUrl, String? token});
  Future<void> setEnabled(bool enabled);
  Future<void> setMode(LocationLogMode mode);
  Future<void> setForegroundInterval(int seconds);
  Future<void> reconcile();
  Future<void> openAppSettings();
  Future<void> requestPermissions();
}
