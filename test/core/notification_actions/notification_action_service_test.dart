import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/notification_actions/notification_action_port.dart';
import 'package:voice_agent/core/notification_actions/notification_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventChannel =
      EventChannel('com.voiceagent/notification_actions/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockStreamHandler(eventChannel, null));

  test('the button ids map to actions, unknown ones are dropped', () async {
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, events) {
        events.success('pause');
        events.success('play');
        events.success('resume');
        events.success('stop');
        events.endOfStream();
      }),
    );

    final service = NotificationActionService(eventChannel: eventChannel);
    expect(await service.actions.toList(), [
      NotificationAction.pause,
      NotificationAction.resume,
      NotificationAction.stop,
    ]);
  });

  test('without buttons nothing is ever pressed', () async {
    expect(await const NoNotificationActions().actions.toList(), isEmpty);
  });
}
