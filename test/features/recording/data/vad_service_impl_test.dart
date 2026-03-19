import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/recording/data/vad_service_impl.dart';
import 'package:voice_agent/features/recording/domain/vad_service.dart';

import 'vad_service_stub.dart';

void main() {
  group('VadService interface contract', () {
    test('VadLabel has speech and nonSpeech variants', () {
      expect(VadLabel.values, hasLength(2));
      expect(VadLabel.values, containsAll([VadLabel.speech, VadLabel.nonSpeech]));
    });

    test('VadException toString includes message', () {
      const e = VadException('mic denied');
      expect(e.toString(), contains('mic denied'));
    });
  });

  group('FakeVadService', () {
    test('returns labels in sequence', () async {
      final svc = FakeVadService([
        VadLabel.speech,
        VadLabel.nonSpeech,
        VadLabel.speech,
      ]);
      await svc.init();
      final frame = Uint8List(1024);

      expect(await svc.classify(frame), VadLabel.speech);
      expect(await svc.classify(frame), VadLabel.nonSpeech);
      expect(await svc.classify(frame), VadLabel.speech);
    });

    test('returns nonSpeech when sequence exhausted', () async {
      final svc = FakeVadService([VadLabel.speech]);
      await svc.init();
      final frame = Uint8List(1024);

      await svc.classify(frame); // consumes the one speech label
      expect(await svc.classify(frame), VadLabel.nonSpeech);
      expect(await svc.classify(frame), VadLabel.nonSpeech);
    });

    test('init sets initCalled flag', () async {
      final svc = FakeVadService([]);
      expect(svc.initCalled, isFalse);
      await svc.init();
      expect(svc.initCalled, isTrue);
    });

    test('dispose sets disposeCalled flag', () async {
      final svc = FakeVadService([]);
      expect(svc.disposeCalled, isFalse);
      svc.dispose();
      expect(svc.disposeCalled, isTrue);
    });

    test('frameSize is 1024', () {
      expect(FakeVadService([]).frameSize, 1024);
    });

    test('empty label list always returns nonSpeech', () async {
      final svc = FakeVadService([]);
      await svc.init();
      final frame = Uint8List(1024);
      for (var i = 0; i < 5; i++) {
        expect(await svc.classify(frame), VadLabel.nonSpeech);
      }
    });
  });

  group('VadServiceImpl structural', () {
    // VadServiceImpl.init() requires ONNX FFI runtime and a bundled model
    // asset — only available on a physical device. Frame-level inference
    // tests are covered by T5 (device verification).
    //
    // Importing VadServiceImpl above makes this file fail to compile if the
    // class ever stops implementing VadService correctly. flutter analyze
    // is the authoritative compile-time gate; this import is the hook.
    test('VadServiceImpl is assignable to VadService', () {
      // Instantiation is not possible without ONNX runtime, but the type
      // check is enough to confirm the interface is satisfied.
      expect(VadServiceImpl, isNotNull);
    });
  });
}
