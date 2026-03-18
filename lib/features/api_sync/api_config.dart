import 'package:flutter_riverpod/flutter_riverpod.dart';

class ApiConfig {
  const ApiConfig({this.url, this.token});

  /// API endpoint URL. Null means not configured.
  final String? url;

  /// Bearer token for authorization. Null means no auth.
  final String? token;
}

/// Stub provider that always returns an unconfigured ApiConfig.
///
/// Proposal 006 (Settings Screen) replaces this with a real provider
/// that reads from SharedPreferences / flutter_secure_storage.
final apiConfigProvider = Provider<ApiConfig>((ref) {
  return const ApiConfig();
});
