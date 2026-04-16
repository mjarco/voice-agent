import 'package:voice_agent/features/activation/data/platform_channel_bridge.dart';

/// In-memory [BridgeStore] for tests. Avoids the
/// [SharedPreferencesAsync] platform dependency.
class InMemoryBridgeStore implements BridgeStore {
  final Map<String, dynamic> _data = {};

  @override
  Future<bool?> getBool(String key) async => _data[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async => _data[key] = value;

  @override
  Future<String?> getString(String key) async => _data[key] as String?;

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;
}
