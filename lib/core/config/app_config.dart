class AppConfig {
  const AppConfig({
    this.apiUrl,
    this.apiToken,
    this.autoSend = true,
    this.language = 'auto',
    this.keepHistory = true,
  });

  final String? apiUrl;
  final String? apiToken;
  final bool autoSend;
  final String language;
  final bool keepHistory;

  AppConfig copyWith({
    String? apiUrl,
    String? apiToken,
    bool? autoSend,
    String? language,
    bool? keepHistory,
  }) {
    return AppConfig(
      apiUrl: apiUrl ?? this.apiUrl,
      apiToken: apiToken ?? this.apiToken,
      autoSend: autoSend ?? this.autoSend,
      language: language ?? this.language,
      keepHistory: keepHistory ?? this.keepHistory,
    );
  }
}
