import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/features/api_sync/api_config.dart';
import 'package:voice_agent/features/api_sync/sync_worker.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  final worker = SyncWorker(
    storageService: ref.watch(storageServiceProvider),
    apiClient: ref.watch(apiClientProvider),
    apiConfig: ref.watch(apiConfigProvider),
    connectivityService: ref.watch(connectivityServiceProvider),
  );

  worker.start();
  ref.onDispose(() => worker.stop());

  return worker;
});
