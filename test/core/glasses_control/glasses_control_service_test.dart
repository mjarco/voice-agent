import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/glasses_control/glasses_control_port.dart';
import 'package:voice_agent/core/glasses_control/glasses_control_service.dart';
import 'package:voice_agent/core/session_control/mic_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventChannel = EventChannel('com.voiceagent/glasses_control/events');
  const methodChannel = MethodChannel('com.voiceagent/glasses_control');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockStreamHandler(eventChannel, null);
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('the commands map to modes, unknown ones are dropped', () async {
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, events) {
        events.success('listening');
        events.success('status');
        events.success('standby');
        events.success('off');
        events.endOfStream();
      }),
    );

    final service = GlassesControlService(
      eventChannel: eventChannel,
      methodChannel: methodChannel,
    );
    expect(await service.commands.toList(), [
      GlassesCommand.listening,
      GlassesCommand.standby,
      GlassesCommand.off,
    ]);
  });

  test('a mode is reported by its name', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return null;
    });

    final service = GlassesControlService(
      eventChannel: eventChannel,
      methodChannel: methodChannel,
    );
    await service.reportMode(MicMode.standby);
    expect(calls.single.method, 'reportMode');
    expect(calls.single.arguments, {'mode': 'standby'});
  });

  test('a missing bridge is not an error', () async {
    final service = GlassesControlService(
      eventChannel: eventChannel,
      methodChannel: methodChannel,
    );
    await service.reportMode(MicMode.listening);
  });

  test('without glass-native nothing comes in', () async {
    expect(await const NoGlassesControl().commands.toList(), isEmpty);
  });
}
