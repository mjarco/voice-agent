import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/location_log/domain/location_log_port.dart';
import 'package:voice_agent/features/location_log/domain/location_log_state.dart';
import 'package:voice_agent/features/location_log/presentation/location_log_providers.dart';
import 'package:voice_agent/features/location_log/presentation/location_log_screen.dart';

class _FakePort implements LocationLogPort {
  _FakePort(this.state);

  LocationLogState state;
  final calls = <String>[];
  Object? alertsFailure;

  @override
  Future<LocationLogState> getState() async => state;
  @override
  Future<void> setCredentials({String? apiUrl, String? token}) async {}
  @override
  Future<void> setEnabled(bool enabled) async =>
      calls.add('setEnabled:$enabled');
  @override
  Future<void> setAlertsEnabled(bool enabled) async {
    calls.add('setAlertsEnabled:$enabled');
    if (alertsFailure != null) throw alertsFailure!;
  }

  @override
  Future<void> setMode(LocationLogMode mode) async =>
      calls.add('setMode:${mode.wire}');
  @override
  Future<void> setForegroundInterval(int seconds) async =>
      calls.add('interval:$seconds');
  @override
  Future<void> reconcile() async {}
  @override
  Future<void> appResumed() async {}
  @override
  Future<void> openAppSettings() async => calls.add('openAppSettings');
  @override
  Future<void> requestPermissions() async => calls.add('requestPermissions');
}

LocationLogState _state({
  bool enabled = false,
  LocationLogMode mode = LocationLogMode.background,
  LocationLogPermission permission = LocationLogPermission.always,
  int queue = 0,
  String? lastError,
  bool alerts = false,
  int geofences = 0,
  DateTime? geofencesAt,
}) => LocationLogState(
  enabled: enabled,
  mode: mode,
  foregroundIntervalSeconds: 30,
  permission: permission,
  queueLength: queue,
  lastError: lastError,
  alertsEnabled: alerts,
  geofenceCount: geofences,
  geofencesAt: geofencesAt,
);

bool _switchValue(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

Future<void> _pump(WidgetTester tester, _FakePort port) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [locationLogPortProvider.overrideWithValue(port)],
      child: const MaterialApp(home: LocationLogScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the state: permission, queue and the last error', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakePort(
        _state(
          permission: LocationLogPermission.whileInUse,
          queue: 7,
          lastError: 'HTTP 503',
        ),
      ),
    );
    expect(find.text('Uprawnienie: tylko podczas używania'), findsOneWidget);
    expect(find.textContaining('W kolejce: 7'), findsOneWidget);
    expect(find.textContaining('Ostatni odczyt: jeszcze nie'), findsOneWidget);
    expect(find.text('HTTP 503'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the switch starts and pauses', (tester) async {
    final port = _FakePort(_state());
    await _pump(tester, port);
    await tester.tap(find.byKey(const Key('location-log-switch')));
    await tester.pump();
    expect(port.calls, ['setEnabled:true']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('starting with no permission asks for it first', (tester) async {
    final port = _FakePort(_state(permission: LocationLogPermission.none));
    await _pump(tester, port);
    await tester.tap(find.byKey(const Key('location-log-switch')));
    await tester.pump();
    expect(port.calls, ['requestPermissions', 'setEnabled:true']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the mode can be changed; the interval shows in foreground only',
    (tester) async {
      final port = _FakePort(_state());
      await _pump(tester, port);
      expect(find.byKey(const Key('location-log-interval')), findsNothing);

      // What the native side reports once the mode is set.
      port.state = _state(mode: LocationLogMode.foreground);
      await tester.tap(find.byKey(const Key('location-log-mode-foreground')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(port.calls, ['setMode:foreground']);
      expect(find.byKey(const Key('location-log-interval')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  group('Alerty w sklepach', () {
    testWidgets('is off by default and apart from the log switch', (
      tester,
    ) async {
      await _pump(tester, _FakePort(_state(enabled: true)));
      expect(find.text('Alerty w sklepach'), findsOneWidget);
      expect(_switchValue(tester, 'location-log-switch'), isTrue);
      expect(_switchValue(tester, 'arrival-alerts-switch'), isFalse);
      expect(find.textContaining('obszary: 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('turning it on asks for permissions, then switches', (
      tester,
    ) async {
      final port = _FakePort(_state(permission: LocationLogPermission.none));
      await _pump(tester, port);
      await tester.tap(find.byKey(const Key('arrival-alerts-switch')));
      await tester.pump();
      expect(port.calls, ['requestPermissions', 'setAlertsEnabled:true']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with location always it still runs the flow, which asks '
        'for notifications', (tester) async {
      final port = _FakePort(_state());
      await _pump(tester, port);
      await tester.tap(find.byKey(const Key('arrival-alerts-switch')));
      await tester.pump();
      expect(port.calls, ['requestPermissions', 'setAlertsEnabled:true']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('turning it off asks for nothing', (tester) async {
      final port = _FakePort(_state(alerts: true, geofences: 3));
      await _pump(tester, port);
      expect(find.textContaining('obszary: 3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('arrival-alerts-switch')));
      await tester.pump();
      expect(port.calls, ['setAlertsEnabled:false']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows the count and when they were registered', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakePort(
          _state(
            alerts: true,
            geofences: 14,
            geofencesAt: DateTime(2026, 11, 5, 9, 7, 3),
          ),
        ),
      );
      expect(find.textContaining('obszary: 14'), findsOneWidget);
      expect(
        find.textContaining('Zarejestrowane: 5.11 09:07:03'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failure to switch shows the error', (tester) async {
      final port = _FakePort(_state())..alertsFailure = Exception('boom');
      await _pump(tester, port);
      await tester.tap(find.byKey(const Key('arrival-alerts-switch')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('location-log-error')), findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
