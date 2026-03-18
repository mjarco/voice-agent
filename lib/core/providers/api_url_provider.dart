import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/settings/settings_provider.dart';

/// Whether the API URL has been configured by the user.
/// Reads from appSettingsProvider — true when URL is non-null and non-empty.
final apiUrlConfiguredProvider = Provider<bool>((ref) {
  final settings = ref.watch(appSettingsProvider);
  final url = settings.apiUrl;
  return url != null && url.isNotEmpty;
});
