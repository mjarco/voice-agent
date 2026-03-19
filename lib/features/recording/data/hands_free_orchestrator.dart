import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:voice_agent/features/recording/domain/hands_free_engine.dart';
import 'package:voice_agent/features/recording/domain/vad_service.dart';

/// Implements [HandsFreeEngine] by wiring the [AudioRecorder] PCM stream to
/// the [VadService] and managing segment state and async WAV writes.
///
/// Inject [AudioRecorder] and [VadService] for testability. At runtime the
/// [handsFreeEngineProvider] constructs both.
class HandsFreeOrchestrator implements HandsFreeEngine {
  HandsFreeOrchestrator(this._audioRecorder, this._vadService);

  final AudioRecorder _audioRecorder;
  final VadService _vadService;

  // ── Tuning constants ────────────────────────────────────────────────────────
  static const _sampleRate = 16000;
  static const _bytesPerSample = 2;
  static const _preRollMs = 300;
  static const _hangoverMs = 400;
  static const _minSpeechMs = 500;
  static const _maxSegmentMs = 30000;
  static const _cooldownMs = 1000;

  // ── Runtime state ───────────────────────────────────────────────────────────
  StreamController<HandsFreeEngineEvent>? _controller;
  StreamSubscription<Uint8List>? _audioSub;

  _Phase _phase = _Phase.idle;

  // Derived from VadService.frameSize after init()
  int _frameSize = 0;
  int _msPerFrame = 0;
  int _hangoverFrameThreshold = 0;
  int _minSpeechFrameThreshold = 0;
  int _maxSpeechFrameThreshold = 0;

  // Remainder buffer: accumulates partial VAD frames between audio chunks.
  final List<int> _remainder = [];

  // Pre-roll ring buffer: keeps the last preRollMs of fully-processed frames.
  final List<Uint8List> _preRoll = [];
  int _preRollCapacity = 0; // max frames in ring

  // Current speech accumulation.
  BytesBuilder _speechBuffer = BytesBuilder(copy: false);
  int _speechFrameCount = 0; // speech frames only (not pre-roll, not hangover) — for minSpeechMs gate
  int _captureFrameCount = 0; // all frames since capturing started — for maxSegmentMs gate
  int _hangoverCount = 0;

  // Frames received while in _Phase.stopping (VAD continues during WAV write).
  final List<Uint8List> _pendingFrames = [];
  final List<VadLabel> _pendingLabels = [];
  bool _pendingSpeechStarted = false;
  Completer<void>? _wavWriteCompleter;

  // Cooldown suppression (VAD-triggered end only; not maxSegmentMs force-close).
  Timer? _cooldownTimer;
  bool _inCooldown = false;

  // Sequential chunk processing queue.
  final List<Uint8List> _chunkQueue = [];
  bool _processingChunks = false;

  // ── HandsFreeEngine interface ────────────────────────────────────────────────

  @override
  Future<bool> hasPermission() => _audioRecorder.hasPermission();

  @override
  Stream<HandsFreeEngineEvent> start() {
    _controller = StreamController<HandsFreeEngineEvent>();
    _phase = _Phase.listening;
    _doStart(); // fire-and-forget
    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    if (_phase == _Phase.idle) return;
    _phase = _Phase.idle;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _inCooldown = false;

    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    try {
      await _audioRecorder.dispose();
    } catch (_) {}

    // Await any in-flight WAV write before closing the stream.
    if (_wavWriteCompleter != null) {
      await _wavWriteCompleter!.future.catchError((_) {});
    }

    _vadService.dispose();
    _resetBuffers();

    await _controller?.close();
    _controller = null;
  }

  @override
  void dispose() {
    unawaited(stop());
  }

  // ── Internal startup ────────────────────────────────────────────────────────

  Future<void> _doStart() async {
    try {
      await _vadService.init();
      _frameSize = _vadService.frameSize;
      _msPerFrame = _frameSize * 1000 ~/ (_sampleRate * _bytesPerSample);
      _hangoverFrameThreshold =
          (_hangoverMs + _msPerFrame - 1) ~/ _msPerFrame;
      _minSpeechFrameThreshold =
          (_minSpeechMs + _msPerFrame - 1) ~/ _msPerFrame;
      _maxSpeechFrameThreshold =
          (_maxSegmentMs + _msPerFrame - 1) ~/ _msPerFrame;
      _preRollCapacity =
          (_preRollMs + _msPerFrame - 1) ~/ _msPerFrame;

      final audioStream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

      if (_phase == _Phase.idle) return; // stop() called during init

      _emit(const EngineListening());
      _audioSub = audioStream.listen(
        _enqueueChunk,
        onError: (Object e) => _emitError('Audio stream error: $e'),
        onDone: _onStreamDone,
        cancelOnError: true,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isPermission =
          msg.contains('permission') || msg.contains('denied');
      _emitError('Failed to start audio: $e',
          requiresSettings: isPermission);
    }
  }

  // ── Chunk queue (ensures sequential async frame processing) ─────────────────

  void _enqueueChunk(Uint8List chunk) {
    _chunkQueue.add(chunk);
    if (!_processingChunks) _drainQueue();
  }

  Future<void> _drainQueue() async {
    _processingChunks = true;
    while (_chunkQueue.isNotEmpty) {
      final chunk = _chunkQueue.removeAt(0);
      await _processChunk(chunk);
    }
    _processingChunks = false;
  }

  Future<void> _processChunk(Uint8List chunk) async {
    if (_phase == _Phase.idle) return;

    _remainder.addAll(chunk);
    while (_remainder.length >= _frameSize) {
      final frame = Uint8List.fromList(_remainder.sublist(0, _frameSize));
      _remainder.removeRange(0, _frameSize);
      await _processFrame(frame);
    }
  }

  // ── Frame-level VAD state machine ───────────────────────────────────────────

  Future<void> _processFrame(Uint8List frame) async {
    final label = await _vadService.classify(frame);

    switch (_phase) {
      case _Phase.idle:
        return;

      case _Phase.listening:
        _addToPreRoll(frame);
        if (label == VadLabel.speech && !_inCooldown) {
          _startCapturing(frame);
        }

      case _Phase.capturing:
        _speechBuffer.add(frame);
        _captureFrameCount++;
        if (label == VadLabel.speech) {
          _speechFrameCount++;
          _hangoverCount = 0;
          if (_captureFrameCount >= _maxSpeechFrameThreshold) {
            _handleMaxSegment();
          }
        } else {
          _hangoverCount++;
          if (_hangoverCount >= _hangoverFrameThreshold) {
            _handleHangoverComplete();
          }
        }

      case _Phase.stopping:
        // VAD classification continues; accumulate for possible next segment.
        _pendingFrames.add(frame);
        _pendingLabels.add(label);
        if (label == VadLabel.speech && !_inCooldown) {
          _pendingSpeechStarted = true;
        }
    }
  }

  // ── State transitions ────────────────────────────────────────────────────────

  void _startCapturing(Uint8List firstSpeechFrame) {
    _speechBuffer = BytesBuilder(copy: false);
    _speechFrameCount = 0;
    _captureFrameCount = 0;
    _hangoverCount = 0;

    for (final f in _preRoll) {
      _speechBuffer.add(f);
    }
    _preRoll.clear();
    _speechBuffer.add(firstSpeechFrame);
    _speechFrameCount = 1;
    _captureFrameCount = 1;

    _phase = _Phase.capturing;
    _emit(const EngineCapturing());
  }

  void _handleHangoverComplete() {
    // Hangover fires → write segment, start cooldown.
    final validSpeech = _speechFrameCount >= _minSpeechFrameThreshold;
    _initiateWavWrite(validSpeech: validSpeech, startCooldown: true);
  }

  void _handleMaxSegment() {
    // maxSegmentMs reached → force-close, no cooldown.
    _initiateWavWrite(validSpeech: true, startCooldown: false);
  }

  void _initiateWavWrite({
    required bool validSpeech,
    required bool startCooldown,
  }) {
    final pcmBytes = _speechBuffer.takeBytes();
    _phase = _Phase.stopping;
    _pendingFrames.clear();
    _pendingLabels.clear();
    _pendingSpeechStarted = false;

    if (startCooldown) {
      _inCooldown = true;
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(
        const Duration(milliseconds: _cooldownMs),
        () => _inCooldown = false,
      );
    }

    _emit(const EngineStopping());

    final completer = Completer<void>();
    _wavWriteCompleter = completer;

    _writeWav(pcmBytes, validSpeech: validSpeech).then((_) {
      completer.complete();
    }).catchError((Object e) {
      completer.complete();
    });
  }

  Future<void> _writeWav(Uint8List pcmBytes,
      {required bool validSpeech}) async {
    if (!validSpeech) {
      // Segment too short — skip WAV write, emit nothing.
      _wavWriteCompleter = null;
      await _afterWavWrite(wavPath: null);
      return;
    }

    try {
      final tmpDir = await getTemporaryDirectory();
      final path =
          '${tmpDir.path}/hf_seg_${DateTime.now().millisecondsSinceEpoch}.wav';
      final wavBytes = _buildWavBytes(pcmBytes);
      await File(path).writeAsBytes(wavBytes, flush: true);
      _wavWriteCompleter = null;
      await _afterWavWrite(wavPath: path);
    } catch (e) {
      _wavWriteCompleter = null;
      await _afterWavWrite(wavPath: null, writeError: e.toString());
    }
  }

  Future<void> _afterWavWrite({
    required String? wavPath,
    String? writeError,
  }) async {
    if (_phase == _Phase.idle) return;

    if (wavPath != null) {
      _emit(EngineSegmentReady(wavPath));
    } else if (writeError != null) {
      // WAV write failed — rejected segment, stay running.
      // Engine does NOT emit EngineSegmentReady; controller marks it Rejected.
      // We emit a special EngineError that the controller maps to a job rejection.
      _emit(EngineError('Write failed: $writeError'));
    }
    // If wavPath == null && writeError == null → segment was too short, silently skip.

    // Resolve deferred speech that arrived during stopping.
    final hadPendingSpeech = _pendingSpeechStarted;
    final pendingBuf = List<Uint8List>.from(_pendingFrames);
    final pendingLbls = List<VadLabel>.from(_pendingLabels);
    _pendingFrames.clear();
    _pendingLabels.clear();
    _pendingSpeechStarted = false;

    if (hadPendingSpeech && !_inCooldown) {
      // Resume capturing with pending frames as new speech buffer.
      _speechBuffer = BytesBuilder(copy: false);
      _speechFrameCount = 0;
      _captureFrameCount = 0;
      _hangoverCount = 0;
      for (var i = 0; i < pendingBuf.length; i++) {
        _speechBuffer.add(pendingBuf[i]);
        _captureFrameCount++;
        if (pendingLbls[i] == VadLabel.speech) {
          _speechFrameCount++;
          _hangoverCount = 0;
        } else {
          _hangoverCount++;
        }
      }
      _phase = _Phase.capturing;
      _emit(const EngineCapturing());
    } else {
      // Return to listening; add pending frames to pre-roll.
      _phase = _Phase.listening;
      for (final f in pendingBuf) {
        _addToPreRoll(f);
      }
      _emit(const EngineListening());
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _addToPreRoll(Uint8List frame) {
    _preRoll.add(frame);
    while (_preRoll.length > _preRollCapacity) {
      _preRoll.removeAt(0);
    }
  }

  void _resetBuffers() {
    _remainder.clear();
    _preRoll.clear();
    _speechBuffer = BytesBuilder(copy: false);
    _speechFrameCount = 0;
    _captureFrameCount = 0;
    _hangoverCount = 0;
    _pendingFrames.clear();
    _pendingLabels.clear();
    _pendingSpeechStarted = false;
    _chunkQueue.clear();
    _processingChunks = false;
  }

  void _emit(HandsFreeEngineEvent event) {
    if (_phase != _Phase.idle &&
        _controller != null &&
        !_controller!.isClosed) {
      _controller!.add(event);
    }
  }

  void _emitError(String message, {bool requiresSettings = false}) {
    _controller?.add(EngineError(message, requiresSettings: requiresSettings));
    unawaited(stop());
  }

  void _onStreamDone() {
    if (_phase != _Phase.idle) {
      _emitError('Audio stream ended unexpectedly');
    }
  }

  /// Builds a complete WAV file (44-byte header + PCM data).
  static Uint8List _buildWavBytes(Uint8List pcm) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataLen = pcm.length;
    final header = ByteData(44)
      // RIFF chunk
      ..setUint8(0, 0x52) ..setUint8(1, 0x49) ..setUint8(2, 0x46) ..setUint8(3, 0x46)
      ..setUint32(4, dataLen + 36, Endian.little)
      ..setUint8(8, 0x57) ..setUint8(9, 0x41) ..setUint8(10, 0x56) ..setUint8(11, 0x45)
      // fmt sub-chunk
      ..setUint8(12, 0x66) ..setUint8(13, 0x6D) ..setUint8(14, 0x74) ..setUint8(15, 0x20)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little) // PCM
      ..setUint16(22, channels, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, byteRate, Endian.little)
      ..setUint16(32, blockAlign, Endian.little)
      ..setUint16(34, bitsPerSample, Endian.little)
      // data sub-chunk
      ..setUint8(36, 0x64) ..setUint8(37, 0x61) ..setUint8(38, 0x74) ..setUint8(39, 0x61)
      ..setUint32(40, dataLen, Endian.little);

    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(pcm);
    return out.takeBytes();
  }
}

enum _Phase { idle, listening, capturing, stopping }
