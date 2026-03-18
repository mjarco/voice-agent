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
  });

  final String? apiUrl;
  final String? apiToken;
  final String? groqApiKey;
  final bool autoSend;
  final String language;
  final bool keepHistory;

  AppConfig copyWith({
    Object? apiUrl = _sentinel,
    Object? apiToken = _sentinel,
    Object? groqApiKey = _sentinel,
    bool? autoSend,
    String? language,
    bool? keepHistory,
  }) {
    return AppConfig(
      apiUrl: apiUrl == _sentinel ? this.apiUrl : apiUrl as String?,
      apiToken: apiToken == _sentinel ? this.apiToken : apiToken as String?,
      groqApiKey:
          groqApiKey == _sentinel ? this.groqApiKey : groqApiKey as String?,
      autoSend: autoSend ?? this.autoSend,
      language: language ?? this.language,
      keepHistory: keepHistory ?? this.keepHistory,
    );
  }
}
