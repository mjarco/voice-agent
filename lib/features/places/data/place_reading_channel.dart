import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voice_agent/features/places/domain/place.dart';
import 'package:voice_agent/features/places/domain/places_ports.dart';

/// [PlaceReadingPort] over `com.voiceagent/place_reading`. While-in-use is
/// enough: the screen is open when it reads.
class PlaceReadingChannel implements PlaceReadingPort {
  PlaceReadingChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.voiceagent/place_reading');

  final MethodChannel _channel;

  @override
  Future<PlaceReadingResult> read() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted && !status.isLimited) {
        return const PlaceReadingResult.none(PlaceReadingProblem.permission);
      }
      final map = await _channel.invokeMapMethod<String, Object?>(
        'currentReading',
      );
      if (map == null) {
        return const PlaceReadingResult.none(PlaceReadingProblem.noFix);
      }
      return PlaceReadingResult.found(
        PlaceReading(
          latitude: map['latitude']! as double,
          longitude: map['longitude']! as double,
          accuracyM: map['accuracyM'] as double?,
          age: Duration(milliseconds: (map['ageMs']! as num).toInt()),
        ),
      );
    } on MissingPluginException {
      return const PlaceReadingResult.none(PlaceReadingProblem.unavailable);
    } on PlatformException {
      return const PlaceReadingResult.none(PlaceReadingProblem.noFix);
    }
  }

  @override
  Future<void> openSettings() => openAppSettings();
}
