import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vad/vad.dart';
import 'package:voice_agent/features/recording/domain/vad_service.dart';

/// Production [VadService] backed by Silero VAD v5 via ONNX Runtime FFI.
///
/// Frame size is 512 samples (1024 bytes) at 16 kHz = 32 ms per frame.
/// The orchestrator accumulates PCM chunks into 1024-byte frames before each
/// [classify] call.
///
/// The Silero ONNX model is bundled as a Flutter asset at
/// `assets/models/silero_vad_v5.onnx` and extracted to the app temp directory
/// on first [init]. Subsequent calls reuse the cached file.
class VadServiceImpl implements VadService {
  static const _assetPath = 'assets/models/silero_vad_v5.onnx';
  static const _frameSamples = 512; // 32 ms at 16 kHz

  VadIterator? _iterator;

  /// Result captured from the most recent [VadEventType.frameProcessed] event.
  VadLabel? _lastLabel;

  @override
  int get frameSize => _frameSamples * 2; // 1024 bytes

  @override
  Future<void> init() async {
    final tempDir = await getTemporaryDirectory();
    final modelDir = '${tempDir.path}/silero_vad/';
    await Directory(modelDir).create(recursive: true);

    final modelFile = File('${modelDir}silero_vad_v5.onnx');
    if (!modelFile.existsSync()) {
      final data = await rootBundle.load(_assetPath);
      await modelFile.writeAsBytes(data.buffer.asUint8List());
    }

    try {
      _iterator = await VadIterator.create(
        isDebug: false,
        sampleRate: 16000,
        frameSamples: _frameSamples,
        positiveSpeechThreshold: 0.5,
        negativeSpeechThreshold: 0.35,
        // Let VadIterator manage its own buffers with short thresholds so
        // internal speech buffers don't grow unbounded. The orchestrator owns
        // all segmentation state; we use only the frameProcessed events.
        redemptionFrames: 10,
        preSpeechPadFrames: 1,
        minSpeechFrames: 1,
        model: 'v5',
        baseAssetPath: modelDir,
      );
      _iterator!.setVadEventCallback(_onEvent);
    } catch (e) {
      throw VadException('Failed to initialise Silero VAD: $e');
    }
  }

  void _onEvent(VadEvent event) {
    if (event.type == VadEventType.frameProcessed) {
      final prob = event.probabilities?.isSpeech ?? 0.0;
      _lastLabel = prob >= 0.5 ? VadLabel.speech : VadLabel.nonSpeech;
    }
  }

  @override
  Future<VadLabel> classify(Uint8List pcmFrame) async {
    final iterator = _iterator;
    if (iterator == null) {
      throw VadException('classify() called before init()');
    }
    if (pcmFrame.length != frameSize) {
      throw VadException(
        'pcmFrame must be exactly $frameSize bytes, got ${pcmFrame.length}',
      );
    }

    _lastLabel = null;

    // processAudioData accumulates bytes and calls _processFrame when a full
    // 512-sample (1024-byte) frame is ready. The frameProcessed callback fires
    // synchronously inside processAudioData before it returns, so _lastLabel
    // is set by the time the await completes.
    await iterator.processAudioData(pcmFrame);

    return _lastLabel ?? VadLabel.nonSpeech;
  }

  @override
  void dispose() {
    if (_iterator != null) {
      unawaited(_iterator!.release());
      _iterator = null;
    }
  }
}
