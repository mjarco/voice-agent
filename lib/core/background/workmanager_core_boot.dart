import 'package:voice_agent/core/config/app_config.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/network/api_client.dart';
import 'package:voice_agent/core/notifications/data/local_notification_service.dart';
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart' show deriveBaseUrl;
import 'package:voice_agent/core/storage/sqlite_storage_service.dart';
import 'package:voice_agent/core/storage/storage_service.dart';

/// Typed bundle of `core/`-layer dependencies. See ADR-PLATFORM-007.
class CoreBootBundle {
  CoreBootBundle({
    required this.storage,
    required this.config,
    required this.configService,
    required this.api,
    required this.notifications,
  });

  final StorageService storage;
  final AppConfig config;
  final AppConfigService configService;
  final ApiClient api;
  final NotificationService notifications;
}

/// Single source of truth for `core/`-layer dependency construction.
/// Called by both the foreground init (`app_main.dart`) and the workmanager
/// background isolate entrypoint (`app/background/agenda_refresh_entrypoint.dart`).
///
/// Does NOT construct feature-level objects — those live in
/// `app/background/wire_*_for_background.dart` helpers, composed by app-layer
/// code (per ADR-ARCH-003: `core/` cannot import `features/`).
///
/// See ADR-PLATFORM-007 for the design rationale and the parity-gate test.
Future<CoreBootBundle> coreBoot() async {
  final storage = await SqliteStorageService.initialize();

  final configService = AppConfigService();
  final config = await configService.load();

  final api = ApiClient(
    baseUrl: deriveBaseUrl(config.apiUrl),
    token: config.apiToken,
  );

  final notifications = LocalNotificationService();
  await notifications.init();

  return CoreBootBundle(
    storage: storage,
    config: config,
    configService: configService,
    api: api,
    notifications: notifications,
  );
}
