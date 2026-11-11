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
    this.triggerCount = 0,
    this.triggersCheckedAt,
    this.effectiveMode = LocationLogMode.background,
    this.intervalSeconds = 300,
    this.motionPermission = false,
    this.motionActivity,
    this.motionAt,
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
      triggerCount: map['triggerCount'] as int? ?? 0,
      triggersCheckedAt: time(map['triggersCheckedAtMs']),
      effectiveMode: LocationLogMode.fromWire(map['effectiveMode'] as String?),
      intervalSeconds: map['intervalSeconds'] as int? ?? 300,
      motionPermission: map['motionPermission'] == true,
      motionActivity: MotionActivity.fromWire(map['motionActivity'] as String?),
      motionAt: time(map['motionAtMs']),
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

  /// Armed triggers in the set last pulled (ADR-NET-007); Dart sees only the count.
  final int triggerCount;

  /// When personal-agent last answered a pull, with a new set or "unchanged".
  final DateTime? triggersCheckedAt;

  /// What the subscription is now, foreground or background; in motion mode
  /// it follows the phone's motion (ADR-PLATFORM-014).
  final LocationLogMode effectiveMode;

  /// The interval asked for now, in seconds.
  final int intervalSeconds;

  /// "Physical activity", needed by motion mode.
  final bool motionPermission;

  /// The last activity transition, and when it happened.
  final MotionActivity? motionActivity;
  final DateTime? motionAt;
}

/// The activities motion mode reacts to (ADR-PLATFORM-014).
enum MotionActivity {
  still('still'),
  walking('walking'),
  running('running'),
  onBicycle('on_bicycle'),
  inVehicle('in_vehicle');

  const MotionActivity(this.wire);

  final String wire;

  static MotionActivity? fromWire(String? wire) {
    for (final a in values) {
      if (a.wire == wire) return a;
    }
    return null;
  }
}

enum LocationLogMode {
  background('background'),
  foreground('foreground'),

  /// Background, and foreground while the phone recognises motion.
  motion('motion');

  const LocationLogMode(this.wire);

  final String wire;

  static LocationLogMode fromWire(String? wire) => switch (wire) {
    'foreground' => foreground,
    'motion' => motion,
    _ => background,
  };
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
