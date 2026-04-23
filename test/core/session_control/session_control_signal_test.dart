import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/session_control/session_control_signal.dart';

void main() {
  group('SessionControlSignal.fromBody', () {
    test('full payload with both true returns non-null, both true, isNoop false',
        () {
      final body = <String, dynamic>{
        'message': 'Goodbye.',
        'session_control': {
          'reset_session': true,
          'stop_recording': true,
        },
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNotNull);
      expect(signal!.resetSession, isTrue);
      expect(signal.stopRecording, isTrue);
      expect(signal.isNoop, isFalse);
    });

    test('absent session_control key returns null', () {
      final body = <String, dynamic>{
        'message': 'Hello.',
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNull);
    });

    test('session_control value is not a Map (string) returns null', () {
      final body = <String, dynamic>{
        'session_control': 'not-a-map',
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNull);
    });

    test('session_control value is not a Map (list) returns null', () {
      final body = <String, dynamic>{
        'session_control': [1, 2, 3],
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNull);
    });

    test('session_control value is not a Map (null) returns null', () {
      final body = <String, dynamic>{
        'session_control': null,
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNull);
    });

    test('both false returns non-null with isNoop true', () {
      final body = <String, dynamic>{
        'session_control': {
          'reset_session': false,
          'stop_recording': false,
        },
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNotNull);
      expect(signal!.resetSession, isFalse);
      expect(signal.stopRecording, isFalse);
      expect(signal.isNoop, isTrue);
    });

    test('missing keys inside map default to false, returns non-null', () {
      final body = <String, dynamic>{
        'session_control': <String, dynamic>{},
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNotNull);
      expect(signal!.resetSession, isFalse);
      expect(signal.stopRecording, isFalse);
      expect(signal.isNoop, isTrue);
    });

    test('missing reset_session defaults to false', () {
      final body = <String, dynamic>{
        'session_control': {
          'stop_recording': true,
        },
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNotNull);
      expect(signal!.resetSession, isFalse);
      expect(signal.stopRecording, isTrue);
    });

    test('missing stop_recording defaults to false', () {
      final body = <String, dynamic>{
        'session_control': {
          'reset_session': true,
        },
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNotNull);
      expect(signal!.resetSession, isTrue);
      expect(signal.stopRecording, isFalse);
    });

    test('extra unknown keys are ignored, returns non-null', () {
      final body = <String, dynamic>{
        'session_control': {
          'reset_session': true,
          'stop_recording': false,
          'future_signal': true,
          'another_field': 42,
        },
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNotNull);
      expect(signal!.resetSession, isTrue);
      expect(signal.stopRecording, isFalse);
      expect(signal.isNoop, isFalse);
    });

    test('non-boolean truthy values are not treated as true', () {
      final body = <String, dynamic>{
        'session_control': {
          'reset_session': 1,
          'stop_recording': 'yes',
        },
      };

      final signal = SessionControlSignal.fromBody(body);

      expect(signal, isNotNull);
      expect(signal!.resetSession, isFalse);
      expect(signal.stopRecording, isFalse);
    });
  });

  group('SessionControlSignal', () {
    test('isNoop is true when both booleans are false', () {
      const signal = SessionControlSignal(
        resetSession: false,
        stopRecording: false,
      );

      expect(signal.isNoop, isTrue);
    });

    test('isNoop is false when resetSession is true', () {
      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );

      expect(signal.isNoop, isFalse);
    });

    test('isNoop is false when stopRecording is true', () {
      const signal = SessionControlSignal(
        resetSession: false,
        stopRecording: true,
      );

      expect(signal.isNoop, isFalse);
    });

    test('equality by value', () {
      const a = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );
      const b = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when fields differ', () {
      const a = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );
      const b = SessionControlSignal(
        resetSession: false,
        stopRecording: true,
      );

      expect(a, isNot(equals(b)));
    });

    test('toString includes field values', () {
      const signal = SessionControlSignal(
        resetSession: true,
        stopRecording: false,
      );

      expect(signal.toString(), contains('resetSession: true'));
      expect(signal.toString(), contains('stopRecording: false'));
    });
  });
}
