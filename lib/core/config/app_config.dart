import 'package:voice_agent/core/config/vad_config.dart';

/// Sentinel object used to distinguish "not provided" from "explicitly null"
/// in [AppConfig.copyWith].
const _sentinel = Object();

class AppConfig {
  const AppConfig({
    this.apiUrl,
    this.apiToken,
    this.groqApiKey,
    this.autoSend = true,
    this.language = 'auto',
    this.keepHistory = true,
    this.vadConfig = const VadConfig.defaults(),
    this.ttsEnabled = true,
    this.audioFeedbackEnabled = true,
    this.devTelemetryEnabled = true,
    this.otelCollectorUrl = defaultOtelCollectorUrl,
  });

  final String? apiUrl;
  final String? apiToken;
  final String? groqApiKey;
  final bool autoSend;
  final String language;
  final bool keepHistory;
  final VadConfig vadConfig;
  final bool ttsEnabled;
  final bool audioFeedbackEnabled;

  // P039 T5c — dev-flavor runtime kill-switch + endpoint override.
  // Persisted on both flavors but only consulted by `lib/main_dev.dart`;
  // the stable flavor leaves them at defaults and never reads them.
  final bool devTelemetryEnabled;
  final String otelCollectorUrl;

  AppConfig copyWith({
    Object? apiUrl = _sentinel,
    Object? apiToken = _sentinel,
    Object? groqApiKey = _sentinel,
    bool? autoSend,
    String? language,
    bool? keepHistory,
    VadConfig? vadConfig,
    bool? ttsEnabled,
    bool? audioFeedbackEnabled,
    bool? devTelemetryEnabled,
    String? otelCollectorUrl,
  }) {
    return AppConfig(
      apiUrl: apiUrl == _sentinel ? this.apiUrl : apiUrl as String?,
      apiToken: apiToken == _sentinel ? this.apiToken : apiToken as String?,
      groqApiKey:
          groqApiKey == _sentinel ? this.groqApiKey : groqApiKey as String?,
      autoSend: autoSend ?? this.autoSend,
      language: language ?? this.language,
      keepHistory: keepHistory ?? this.keepHistory,
      vadConfig: vadConfig ?? this.vadConfig,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      audioFeedbackEnabled: audioFeedbackEnabled ?? this.audioFeedbackEnabled,
      devTelemetryEnabled: devTelemetryEnabled ?? this.devTelemetryEnabled,
      otelCollectorUrl: otelCollectorUrl ?? this.otelCollectorUrl,
    );
  }
}

/// Default Collector endpoint used when the user has not customised it.
/// Sourced from `--dart-define=OTEL_COLLECTOR=…` at build time, or
/// `http://laptop.lan:4318` as the fallback for the home stack.
const String defaultOtelCollectorUrl = String.fromEnvironment(
  'OTEL_COLLECTOR',
  defaultValue: 'http://laptop.lan:4318',
);
