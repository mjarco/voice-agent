import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/sse_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(
    baseUrl: deriveBaseUrl(config.apiUrl),
    token: config.apiToken,
  );
});

final sseClientProvider = Provider<SseClient>((ref) {
  return SseClient(apiClient: ref.watch(apiClientProvider));
});

String? deriveBaseUrl(String? apiUrl) {
  if (apiUrl == null || apiUrl.isEmpty) return null;
  final uri = Uri.tryParse(apiUrl);
  if (uri == null) return null;
  final segments = uri.pathSegments;
  final apiIdx = segments.indexOf('api');
  if (apiIdx == -1 || apiIdx + 1 >= segments.length) return null;
  final baseSegments = segments.sublist(0, apiIdx + 2);
  var result = uri.replace(pathSegments: baseSegments).toString();
  if (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
