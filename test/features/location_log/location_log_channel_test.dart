import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/location_log/data/location_log_channel.dart';
import 'package:voice_agent/features/location_log/domain/location_log_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.voiceagent/location_log');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getState') {
        return <String, Object?>{
          'enabled': true,
          'mode': 'foreground',
          'foregroundIntervalSeconds': 10,
          'permission': 'while_in_use',
          'queueLength': 3,
          'lastReadingAtMs': 1000,
          'lastSentAtMs': 0,
          'lastError': 'HTTP 500',
          'alertsEnabled': true,
          'geofenceCount': 12,
          'geofencesAtMs': 2000,
          'triggerCount': 4,
          'triggersCheckedAtMs': 3000,
        };
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('getState reads the native map', () async {
    final state = await LocationLogChannel().getState();
    expect(state.enabled, isTrue);
    expect(state.mode, LocationLogMode.foreground);
    expect(state.foregroundIntervalSeconds, 10);
    expect(state.permission, LocationLogPermission.whileInUse);
    expect(state.queueLength, 3);
    expect(state.lastReadingAt, isNotNull);
    expect(state.lastSentAt, isNull);
    expect(state.lastError, 'HTTP 500');
    expect(state.alertsEnabled, isTrue);
    expect(state.geofenceCount, 12);
    expect(state.geofencesAt, DateTime.fromMillisecondsSinceEpoch(2000));
    expect(state.triggerCount, 4);
    expect(
      state.triggersCheckedAt,
      DateTime.fromMillisecondsSinceEpoch(3000),
    );
  });

  test('commands carry their arguments', () async {
    final port = LocationLogChannel();
    await port.setCredentials(apiUrl: 'https://x/api/v1', token: 't');
    await port.setEnabled(true);
    await port.setMode(LocationLogMode.background);
    await port.setForegroundInterval(60);
    await port.reconcile();
    await port.setAlertsEnabled(true);
    await port.appResumed();

    expect(calls.map((c) => c.method), [
      'setCredentials',
      'setEnabled',
      'setMode',
      'setForegroundInterval',
      'reconcile',
      'setAlertsEnabled',
      'appResumed',
    ]);
    expect(calls[0].arguments, {'apiUrl': 'https://x/api/v1', 'token': 't'});
    expect(calls[2].arguments, {'mode': 'background'});
    expect(calls[3].arguments, {'seconds': 60});
    expect(calls[5].arguments, {'enabled': true});
  });

  test('an unknown state falls back to the safest reading', () {
    final state = LocationLogState.fromMap(const {});
    expect(state.enabled, isFalse);
    expect(state.mode, LocationLogMode.background);
    expect(state.permission, LocationLogPermission.none);
    expect(state.alertsEnabled, isFalse);
    expect(state.geofenceCount, 0);
    expect(state.geofencesAt, isNull);
    expect(state.triggerCount, 0);
    expect(state.triggersCheckedAt, isNull);
  });
}
