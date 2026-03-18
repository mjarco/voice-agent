import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';

/// Whether the API URL has been configured by the user.
/// Reads from appConfigProvider — true when URL is non-null and non-empty.
final apiUrlConfiguredProvider = Provider<bool>((ref) {
  final config = ref.watch(appConfigProvider);
  final url = config.apiUrl;
  return url != null && url.isNotEmpty;
});
