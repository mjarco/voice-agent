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

  @override
  Future<LocationLogState> getState() async => state;
  @override
  Future<void> setCredentials({String? apiUrl, String? token}) async {}
  @override
  Future<void> setEnabled(bool enabled) async => calls.add('setEnabled:$enabled');
  @override
  Future<void> setMode(LocationLogMode mode) async =>
      calls.add('setMode:${mode.wire}');
  @override
  Future<void> setForegroundInterval(int seconds) async =>
      calls.add('interval:$seconds');
  @override
  Future<void> setServerOverride(String? url) async => calls.add('server:$url');
  @override
  Future<void> reconcile() async {}
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
}) =>
    LocationLogState(
      enabled: enabled,
      mode: mode,
      foregroundIntervalSeconds: 30,
      permission: permission,
      queueLength: queue,
      lastError: lastError,
    );

Future<void> _pump(WidgetTester tester, _FakePort port) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [locationLogPortProvider.overrideWithValue(port)],
    child: const MaterialApp(home: LocationLogScreen()),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the state: permission, queue and the last error',
      (tester) async {
    await _pump(
      tester,
      _FakePort(_state(
        permission: LocationLogPermission.whileInUse,
        queue: 7,
        lastError: 'HTTP 503',
      )),
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

  testWidgets('the mode can be changed; the interval shows in foreground only',
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
  });
}
