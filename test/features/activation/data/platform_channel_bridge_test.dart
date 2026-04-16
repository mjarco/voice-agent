import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/activation/data/platform_channel_bridge.dart';

// ---------------------------------------------------------------------------
// In-memory BridgeStore for tests
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late InMemoryBridgeStore store;
  late int toggleCount;
  late int stopCount;
  late PlatformChannelBridge bridge;

  setUp(() {
    channel = const MethodChannel('com.voiceagent/activation.test');
    store = InMemoryBridgeStore();
    toggleCount = 0;
    stopCount = 0;
    bridge = PlatformChannelBridge(
      onToggleRequested: () => toggleCount++,
      onStopRequested: () => stopCount++,
      channel: channel,
      store: store,
    );
  });

  tearDown(() {
    bridge.stop();
  });

  group('PlatformChannelBridge', () {
    group('MethodChannel', () {
      test('toggleFromIntent calls onToggleRequested', () async {
        bridge.start();

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'com.voiceagent/activation.test',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('toggleFromIntent'),
          ),
          (ByteData? reply) {},
        );

        expect(toggleCount, 1);
        expect(stopCount, 0);
      });

      test('unknown method throws PlatformException', () async {
        bridge.start();

        final completer = Completer<ByteData?>();
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'com.voiceagent/activation.test',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('unknownMethod'),
          ),
          (ByteData? reply) {
            completer.complete(reply);
          },
        );

        final response = await completer.future;
        expect(response, isNotNull);
        expect(
          () => const StandardMethodCodec().decodeEnvelope(response!),
          throwsA(isA<PlatformException>()),
        );
      });
    });

    group('SharedPreferences polling', () {
      test('checkFlags detects toggle request and clears flag', () async {
        await store.setBool('activation_toggle_requested', true);

        await bridge.checkFlags();

        expect(toggleCount, 1);
        expect(stopCount, 0);
        expect(await store.getBool('activation_toggle_requested'), false);
      });

      test('checkFlags detects stop request and clears flag', () async {
        await store.setBool('activation_stop_requested', true);

        await bridge.checkFlags();

        expect(toggleCount, 0);
        expect(stopCount, 1);
        expect(await store.getBool('activation_stop_requested'), false);
      });

      test('checkFlags handles both flags simultaneously', () async {
        await store.setBool('activation_toggle_requested', true);
        await store.setBool('activation_stop_requested', true);

        await bridge.checkFlags();

        expect(toggleCount, 1);
        expect(stopCount, 1);
      });

      test('checkFlags is no-op when no flags set', () async {
        await bridge.checkFlags();

        expect(toggleCount, 0);
        expect(stopCount, 0);
      });
    });

    group('state writing', () {
      test('writeActivationState persists to store', () async {
        await bridge.writeActivationState('listening');

        expect(await store.getString('activation_state'), 'listening');
      });

      test('writeActivationState overwrites previous value', () async {
        await bridge.writeActivationState('listening');
        await bridge.writeActivationState('idle');

        expect(await store.getString('activation_state'), 'idle');
      });
    });

    group('lifecycle', () {
      test('stop cancels poll timer', () async {
        bridge.start();
        bridge.stop();

        // Set a flag after stop — should not be detected
        await store.setBool('activation_toggle_requested', true);

        // Wait a tick
        await Future.delayed(Duration.zero);

        expect(toggleCount, 0);
      });
    });
  });
}
