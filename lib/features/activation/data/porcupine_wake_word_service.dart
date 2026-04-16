import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:porcupine_flutter/porcupine.dart' as pv;
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:voice_agent/features/activation/domain/wake_word_service.dart';

/// Maps domain [BuiltInKeyword] to the Porcupine SDK's [pv.BuiltInKeyword].
@visibleForTesting
pv.BuiltInKeyword toSdkKeyword(BuiltInKeyword keyword) {
  switch (keyword) {
    case BuiltInKeyword.jarvis:
      return pv.BuiltInKeyword.JARVIS;
    case BuiltInKeyword.computer:
      return pv.BuiltInKeyword.COMPUTER;
    case BuiltInKeyword.alexa:
      return pv.BuiltInKeyword.ALEXA;
    case BuiltInKeyword.americano:
      return pv.BuiltInKeyword.AMERICANO;
    case BuiltInKeyword.blueberry:
      return pv.BuiltInKeyword.BLUEBERRY;
    case BuiltInKeyword.bumblebee:
      return pv.BuiltInKeyword.BUMBLEBEE;
    case BuiltInKeyword.grapefruit:
      return pv.BuiltInKeyword.GRAPEFRUIT;
    case BuiltInKeyword.grasshopper:
      return pv.BuiltInKeyword.GRASSHOPPER;
    case BuiltInKeyword.picovoice:
      return pv.BuiltInKeyword.PICOVOICE;
    case BuiltInKeyword.porcupine:
      return pv.BuiltInKeyword.PORCUPINE;
    case BuiltInKeyword.terminator:
      // Terminator is not in porcupine_flutter 3.x; fallback to JARVIS
      return pv.BuiltInKeyword.JARVIS;
  }
}

/// Classifies a [PorcupineException] into a typed [WakeWordError].
@visibleForTesting
WakeWordError classifyPorcupineError(PorcupineException e) {
  final msg = e.message ?? '';
  if (msg.contains('access key') || msg.contains('AccessKey')) {
    return const InvalidAccessKey();
  }
  if (msg.contains('.ppn') || msg.contains('keyword file')) {
    return CorruptModel(path: msg);
  }
  if (msg.contains('audio') || msg.contains('recording')) {
    return AudioCaptureFailed(reason: msg);
  }
  return UnknownWakeWordError(message: msg);
}

/// [WakeWordService] implementation using Picovoice Porcupine.
class PorcupineWakeWordService implements WakeWordService {
  PorcupineManager? _manager;
  bool _listening = false;
  bool _disposed = false;

  final _detectionsController = StreamController<int>.broadcast();
  final _errorsController = StreamController<WakeWordError>.broadcast();

  @override
  Stream<int> get detections => _detectionsController.stream;

  @override
  Stream<WakeWordError> get errors => _errorsController.stream;

  @override
  bool get isListening => _listening;

  @override
  Future<void> startBuiltIn({
    required String accessKey,
    required List<BuiltInKeyword> keywords,
    required List<double> sensitivities,
  }) async {
    if (_disposed) return;
    if (_listening) return;

    try {
      _manager = await PorcupineManager.fromBuiltInKeywords(
        accessKey,
        keywords.map(toSdkKeyword).toList(),
        _onWakeWord,
        sensitivities: sensitivities,
        errorCallback: _onError,
      );
      await _manager!.start();
      _listening = true;
    } on PorcupineException catch (e) {
      _errorsController.add(classifyPorcupineError(e));
    }
  }

  @override
  Future<void> startCustom({
    required String accessKey,
    required List<String> keywordPaths,
    required List<double> sensitivities,
  }) async {
    if (_disposed) return;
    if (_listening) return;

    try {
      _manager = await PorcupineManager.fromKeywordPaths(
        accessKey,
        keywordPaths,
        _onWakeWord,
        sensitivities: sensitivities,
        errorCallback: _onError,
      );
      await _manager!.start();
      _listening = true;
    } on PorcupineException catch (e) {
      _errorsController.add(classifyPorcupineError(e));
    }
  }

  @override
  Future<void> stop() async {
    if (!_listening) return;
    try {
      await _manager?.delete();
    } catch (_) {
      // Best effort cleanup
    }
    _manager = null;
    _listening = false;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _detectionsController.close();
    _errorsController.close();
  }

  void _onWakeWord(int keywordIndex) {
    if (!_detectionsController.isClosed) {
      _detectionsController.add(keywordIndex);
    }
  }

  void _onError(PorcupineException error) {
    if (!_errorsController.isClosed) {
      _errorsController.add(classifyPorcupineError(error));
    }
  }
}
