import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/storage/storage_service.dart';

/// Provider for [StorageService].
///
/// Must be overridden in main.dart with an initialized
/// [SqliteStorageService] instance before the app starts.
final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError(
    'storageServiceProvider must be overridden with an initialized instance',
  );
});
