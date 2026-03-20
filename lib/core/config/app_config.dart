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
  });

  final String? apiUrl;
  final String? apiToken;
  final String? groqApiKey;
  final bool autoSend;
  final String language;
  final bool keepHistory;
  final VadConfig vadConfig;
  final bool ttsEnabled;

  AppConfig copyWith({
    Object? apiUrl = _sentinel,
    Object? apiToken = _sentinel,
    Object? groqApiKey = _sentinel,
    bool? autoSend,
    String? language,
    bool? keepHistory,
    VadConfig? vadConfig,
    bool? ttsEnabled,
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
    );
  }
}
