import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/settings/settings_provider.dart';

class ApiConfig {
  const ApiConfig({this.url, this.token});

  /// API endpoint URL. Null means not configured.
  final String? url;

  /// Bearer token for authorization. Null means no auth.
  final String? token;
}

/// Reads API URL and token from settings.
/// Returns ApiConfig with values from appSettingsProvider.
final apiConfigProvider = Provider<ApiConfig>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return ApiConfig(
    url: settings.apiUrl,
    token: settings.apiToken,
  );
});
