import 'dart:typed_data';

import 'package:voice_agent/core/config/vad_config.dart';
import 'package:voice_agent/features/recording/domain/vad_service.dart';

/// Deterministic [VadService] stub for unit tests.
///
/// Returns [labels] in sequence; once exhausted, returns [VadLabel.nonSpeech].
/// Tracks [initCalled] and [disposeCalled] for verification.
class FakeVadService implements VadService {
  FakeVadService(this._labels);

  final List<VadLabel> _labels;
  int _index = 0;
  bool initCalled = false;
  bool disposeCalled = false;

  @override
  final int frameSize = 1024;

  @override
  Future<void> init(VadConfig config) async {
    initCalled = true;
  }

  @override
  Future<VadLabel> classify(Uint8List pcmFrame) async {
    if (_index >= _labels.length) return VadLabel.nonSpeech;
    return _labels[_index++];
  }

  @override
  void dispose() {
    disposeCalled = true;
  }
}
