import 'package:flutter_test/flutter_test.dart';
import 'package:porcupine_flutter/porcupine.dart' as pv;
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:voice_agent/features/activation/data/porcupine_wake_word_service.dart';
import 'package:voice_agent/features/activation/domain/wake_word_service.dart';

void main() {
  group('toSdkKeyword', () {
    test('maps all domain keywords to SDK keywords', () {
      expect(toSdkKeyword(BuiltInKeyword.jarvis), pv.BuiltInKeyword.JARVIS);
      expect(toSdkKeyword(BuiltInKeyword.computer), pv.BuiltInKeyword.COMPUTER);
      expect(toSdkKeyword(BuiltInKeyword.alexa), pv.BuiltInKeyword.ALEXA);
      expect(toSdkKeyword(BuiltInKeyword.americano), pv.BuiltInKeyword.AMERICANO);
      expect(toSdkKeyword(BuiltInKeyword.blueberry), pv.BuiltInKeyword.BLUEBERRY);
      expect(toSdkKeyword(BuiltInKeyword.bumblebee), pv.BuiltInKeyword.BUMBLEBEE);
      expect(toSdkKeyword(BuiltInKeyword.grapefruit), pv.BuiltInKeyword.GRAPEFRUIT);
      expect(
          toSdkKeyword(BuiltInKeyword.grasshopper), pv.BuiltInKeyword.GRASSHOPPER);
      expect(toSdkKeyword(BuiltInKeyword.picovoice), pv.BuiltInKeyword.PICOVOICE);
      expect(toSdkKeyword(BuiltInKeyword.porcupine), pv.BuiltInKeyword.PORCUPINE);
    });

    test('terminator falls back to JARVIS', () {
      expect(
          toSdkKeyword(BuiltInKeyword.terminator), pv.BuiltInKeyword.JARVIS);
    });
  });

  group('classifyPorcupineError', () {
    test('classifies access key error', () {
      final result =
          classifyPorcupineError(PorcupineException('Invalid access key'));
      expect(result, isA<InvalidAccessKey>());
    });

    test('classifies AccessKey variant', () {
      final result =
          classifyPorcupineError(PorcupineException('Bad AccessKey provided'));
      expect(result, isA<InvalidAccessKey>());
    });

    test('classifies corrupt .ppn file error', () {
      final result = classifyPorcupineError(
          PorcupineException('Failed to load /path/to/model.ppn'));
      expect(result, isA<CorruptModel>());
      expect((result as CorruptModel).path,
          contains('.ppn'));
    });

    test('classifies keyword file error', () {
      final result = classifyPorcupineError(
          PorcupineException('Invalid keyword file format'));
      expect(result, isA<CorruptModel>());
    });

    test('classifies audio capture error', () {
      final result = classifyPorcupineError(
          PorcupineException('Failed to start audio capture'));
      expect(result, isA<AudioCaptureFailed>());
      expect((result as AudioCaptureFailed).reason, contains('audio'));
    });

    test('classifies recording error', () {
      final result = classifyPorcupineError(
          PorcupineException('recording device not available'));
      expect(result, isA<AudioCaptureFailed>());
    });

    test('classifies unknown error', () {
      final result = classifyPorcupineError(
          PorcupineException('something unexpected'));
      expect(result, isA<UnknownWakeWordError>());
      expect((result as UnknownWakeWordError).message,
          'something unexpected');
    });

    test('handles null message', () {
      final result = classifyPorcupineError(PorcupineException());
      expect(result, isA<UnknownWakeWordError>());
      expect((result as UnknownWakeWordError).message, '');
    });
  });

  group('PorcupineWakeWordService', () {
    late PorcupineWakeWordService service;

    setUp(() {
      service = PorcupineWakeWordService();
    });

    tearDown(() {
      service.dispose();
    });

    test('initial state is not listening', () {
      expect(service.isListening, isFalse);
    });

    test('detections stream is broadcast', () {
      // Should not throw — broadcast streams allow multiple listeners
      service.detections.listen((_) {});
      service.detections.listen((_) {});
    });

    test('errors stream is broadcast', () {
      service.errors.listen((_) {});
      service.errors.listen((_) {});
    });

    test('stop when not listening is a no-op', () async {
      // Should not throw or change state
      await service.stop();
      expect(service.isListening, isFalse);
    });

    test('dispose prevents subsequent startBuiltIn', () async {
      service.dispose();

      // startBuiltIn should be a no-op after dispose
      await service.startBuiltIn(
        accessKey: 'test-key',
        keywords: [BuiltInKeyword.jarvis],
        sensitivities: [0.5],
      );
      expect(service.isListening, isFalse);
    });

    test('dispose prevents subsequent startCustom', () async {
      service.dispose();

      await service.startCustom(
        accessKey: 'test-key',
        keywordPaths: ['/path/to/model.ppn'],
        sensitivities: [0.5],
      );
      expect(service.isListening, isFalse);
    });

    test('dispose closes detection stream', () async {
      service.dispose();
      // Stream should complete (close) after dispose
      expect(service.detections, emitsDone);
    });

    test('dispose closes error stream', () async {
      service.dispose();
      expect(service.errors, emitsDone);
    });
  });
}
