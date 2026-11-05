import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/places/data/place_geofences_channel.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.voiceagent/place_geofences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('setPlaces sends id, name, position and radius in order', () async {
    await PlaceGeofencesChannel().setPlaces([
      place('a', name: 'Castorama'),
      place('b', name: 'Dom'),
    ]);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setPlaces');
    expect(calls.single.arguments, [
      {
        'id': 'a',
        'name': 'Castorama',
        'lat': 52.25,
        'lon': 21.01,
        'radius_m': 150,
      },
      {'id': 'b', 'name': 'Dom', 'lat': 52.25, 'lon': 21.01, 'radius_m': 150},
    ]);
  });

  test('an empty list is sent as one, so every geofence goes', () async {
    await PlaceGeofencesChannel().setPlaces(const []);
    expect(calls.single.arguments, isEmpty);
  });
}
