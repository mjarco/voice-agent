import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';

class ApiConfig {
  const ApiConfig({this.url, this.token});

  /// API endpoint URL. Null means not configured.
  final String? url;

  /// Bearer token for authorization. Null means no auth.
  final String? token;
}

/// Reads API URL and token from core app config.
final apiConfigProvider = Provider<ApiConfig>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiConfig(
    url: config.apiUrl,
    token: config.apiToken,
  );
});
