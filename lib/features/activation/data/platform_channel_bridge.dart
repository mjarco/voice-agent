import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstraction over SharedPreferences for platform bridge key-value access.
/// Production uses [SharedPreferencesBridgeStore]; tests can substitute a
/// synchronous in-memory implementation.
abstract class BridgeStore {
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

/// Production [BridgeStore] backed by [SharedPreferencesAsync].
class SharedPreferencesBridgeStore implements BridgeStore {
  SharedPreferencesBridgeStore([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<bool?> getBool(String key) => _prefs.getBool(key);

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<String?> getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
}

/// Bridges native platform controls (Android Quick Settings tile, iOS Control
/// Center) with the Flutter-side activation controller.
///
/// Communication paths:
/// 1. MethodChannel: `toggleFromIntent` -- tile tap when app was not alive
/// 2. SharedPreferences polling: `activation_toggle_requested` /
///    `activation_stop_requested` flags -- tile tap when app is alive
///
/// State is written to SharedPreferences so the native tile can read it.
class PlatformChannelBridge {
  PlatformChannelBridge({
    required this.onToggleRequested,
    required this.onStopRequested,
    MethodChannel? channel,
    BridgeStore? store,
  })  : _channel = channel ?? const MethodChannel('com.voiceagent/activation'),
        _store = store ?? SharedPreferencesBridgeStore();

  final void Function() onToggleRequested;
  final void Function() onStopRequested;
  final MethodChannel _channel;
  final BridgeStore _store;

  Timer? _pollTimer;

  static const _pollInterval = Duration(seconds: 10);

  static const _keyToggleRequested = 'activation_toggle_requested';
  static const _keyStopRequested = 'activation_stop_requested';
  static const _keyActivationState = 'activation_state';

  /// Start listening for platform activation requests.
  void start() {
    _channel.setMethodCallHandler(_handleMethodCall);
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => checkFlags());
    // Also check immediately on start (e.g. after lifecycle resume).
    unawaited(checkFlags());
  }

  /// Stop listening and cancel the poll timer.
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _channel.setMethodCallHandler(null);
  }

  /// Check SharedPreferences flags for pending activation requests.
  /// Exposed for testing and for lifecycle resume checks.
  Future<void> checkFlags() async {
    final toggleRequested =
        await _store.getBool(_keyToggleRequested) ?? false;
    if (toggleRequested) {
      await _store.setBool(_keyToggleRequested, false);
      onToggleRequested();
    }

    final stopRequested =
        await _store.getBool(_keyStopRequested) ?? false;
    if (stopRequested) {
      await _store.setBool(_keyStopRequested, false);
      onStopRequested();
    }
  }

  /// Write the current activation state so native tiles can read it.
  Future<void> writeActivationState(String state) async {
    await _store.setString(_keyActivationState, state);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'toggleFromIntent':
        onToggleRequested();
      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'Method ${call.method} not implemented',
        );
    }
  }
}
