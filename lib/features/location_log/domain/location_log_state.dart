/// What the phone's location log is doing, as the native pipeline reports it.
class LocationLogState {
  const LocationLogState({
    required this.enabled,
    required this.mode,
    required this.foregroundIntervalSeconds,
    required this.permission,
    required this.queueLength,
    this.lastReadingAt,
    this.lastSentAt,
    this.lastError,
    this.alertsEnabled = false,
    this.geofenceCount = 0,
    this.geofencesAt,
  });

  factory LocationLogState.fromMap(Map<Object?, Object?> map) {
    DateTime? time(Object? ms) =>
        ms is int && ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    return LocationLogState(
      enabled: map['enabled'] == true,
      mode: LocationLogMode.fromWire(map['mode'] as String?),
      foregroundIntervalSeconds: map['foregroundIntervalSeconds'] as int? ?? 30,
      permission: LocationLogPermission.fromWire(map['permission'] as String?),
      queueLength: map['queueLength'] as int? ?? 0,
      lastReadingAt: time(map['lastReadingAtMs']),
      lastSentAt: time(map['lastSentAtMs']),
      lastError: map['lastError'] as String?,
      alertsEnabled: map['alertsEnabled'] == true,
      geofenceCount: map['geofenceCount'] as int? ?? 0,
      geofencesAt: time(map['geofencesAtMs']),
    );
  }

  final bool enabled;
  final LocationLogMode mode;
  final int foregroundIntervalSeconds;
  final LocationLogPermission permission;
  final int queueLength;
  final DateTime? lastReadingAt;
  final DateTime? lastSentAt;
  final String? lastError;

  /// The "Alerty w sklepach" switch, off by default.
  final bool alertsEnabled;

  /// Geofences registered now; 0 when off or when the last try failed.
  final int geofenceCount;

  /// When they were last registered.
  final DateTime? geofencesAt;
}

enum LocationLogMode {
  background('background'),
  foreground('foreground');

  const LocationLogMode(this.wire);

  final String wire;

  static LocationLogMode fromWire(String? wire) =>
      wire == foreground.wire ? foreground : background;
}

enum LocationLogPermission {
  none,
  approximate,
  whileInUse,
  always;

  static LocationLogPermission fromWire(String? wire) => switch (wire) {
    'approximate' => approximate,
    'while_in_use' => whileInUse,
    'always' => always,
    _ => none,
  };
}
