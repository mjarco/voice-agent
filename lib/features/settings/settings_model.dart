class AppSettings {
  const AppSettings({
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

  AppSettings copyWith({
    String? apiUrl,
    String? apiToken,
    bool? autoSend,
    String? language,
    bool? keepHistory,
  }) {
    return AppSettings(
      apiUrl: apiUrl ?? this.apiUrl,
      apiToken: apiToken ?? this.apiToken,
      autoSend: autoSend ?? this.autoSend,
      language: language ?? this.language,
      keepHistory: keepHistory ?? this.keepHistory,
    );
  }
}
