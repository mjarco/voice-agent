import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/recording/domain/stt_exception.dart';
import 'package:voice_agent/features/recording/domain/stt_service.dart';

class GroqSttService implements SttService {
  GroqSttService(this._ref, {Dio? dio}) : _dio = dio ?? _defaultDio();

  final Ref _ref;
  final Dio _dio;

  static Dio _defaultDio() {
    return Dio(
      BaseOptions(
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
  }

  @override
  Future<bool> isModelLoaded() async => true;

  @override
  Future<void> loadModel() async {}

  @override
  Future<TranscriptResult> transcribe(
    String audioFilePath, {
    String? languageCode,
  }) async {
    final config = _ref.read(appConfigProvider);
    final apiKey = config.groqApiKey;

    if (apiKey == null || apiKey.isEmpty) {
      throw const SttException('Groq API key not configured');
    }

    final language = config.language;

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioFilePath,
          filename: 'audio.wav',
        ),
        'model': 'whisper-large-v3-turbo',
        'response_format': 'verbose_json',
        if (language != 'auto') 'language': language,
      });

      final response = await _dio.post<Map<String, dynamic>>(
        'https://api.groq.com/openai/v1/audio/transcriptions',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );

      final body = response.data!;
      return _parseResponse(body);
    } on DioException catch (e) {
      throw _mapDioException(e);
    } finally {
      try {
        await File(audioFilePath).delete();
      } catch (_) {
        // Cleanup failure must not mask transcription result or error
      }
    }
  }

  TranscriptResult _parseResponse(Map<String, dynamic> body) {
    final text = (body['text'] as String? ?? '').trim();
    final detectedLanguage = body['language'] as String? ?? 'auto';
    final durationSec = (body['duration'] as num?)?.toDouble() ?? 0.0;
    final audioDurationMs = (durationSec * 1000).round();

    final rawSegments = body['segments'] as List<dynamic>? ?? [];
    final segments = rawSegments.map((s) {
      final seg = s as Map<String, dynamic>;
      final startMs = ((seg['start'] as num?)?.toDouble() ?? 0.0) * 1000;
      final endMs = ((seg['end'] as num?)?.toDouble() ?? 0.0) * 1000;
      return TranscriptSegment(
        text: (seg['text'] as String? ?? '').trim(),
        startMs: startMs.round(),
        endMs: endMs.round(),
      );
    }).toList();

    return TranscriptResult(
      text: text,
      segments: segments,
      detectedLanguage: detectedLanguage,
      audioDurationMs: audioDurationMs,
    );
  }

  SttException _mapDioException(DioException e) {
    if (e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const SttException('Groq service unavailable');
    }

    final statusCode = e.response?.statusCode;
    if (statusCode == null) {
      return const SttException('Groq service unavailable');
    }

    if (statusCode == 401) {
      return const SttException('Invalid Groq API key');
    }
    if (statusCode == 429) {
      return const SttException('Groq rate limit exceeded');
    }
    if (statusCode >= 500) {
      return const SttException('Groq service unavailable');
    }

    // Other 4xx — try to extract message from body
    final data = e.response?.data;
    String? message;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        message = error['message'] as String?;
      }
    }
    return SttException(message ?? 'Transcription failed');
  }
}
