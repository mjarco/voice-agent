import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/core/network/shopping_proposals_port.dart';
import 'package:voice_agent/core/providers/deep_link_providers.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_screen.dart';
import 'package:voice_agent/features/routines/presentation/routine_form_screen.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_providers.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_screen.dart';

import '../core/network/fake_shopping_proposals.dart';
import '../features/routines/fake_routines_repository.dart';
import '../features/shopping/fake_shopping_repository.dart';

import '../helpers/stub_background_service.dart';
import '../helpers/stub_notifications.dart';
import '../helpers/stub_session_control.dart';

class _StubStorageService with TelemetryStorageNoop implements StorageService {
  @override
  Future<String> getDeviceId() async => 'test-device';
  @override
  Future<void> saveTranscript(Transcript t) async {}
  @override
  Future<Transcript?> getTranscript(String id) async => null;
  @override
  Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async => [];
  @override
  Future<void> deleteTranscript(String id) async {}
  @override
  Future<void> enqueue(String transcriptId) async {}
  @override
  Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override
  Future<void> markSending(String id) async {}
  @override
  Future<void> markSent(String id) async {}
  @override
  Future<void> markFailed(String id, String error, {int? overrideAttempts}) async {}
  @override
  Future<void> markPendingForRetry(String id) async {}
  @override
  Future<void> reactivateForResend(String transcriptId) async {}
  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  }) async => [];
  @override
  Future<int> recoverStaleSending() async => 0;
  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

class _StubAgendaRepository implements AgendaRepository {
  @override
  Future<AgendaResponse> fetchAgenda(String date) async => AgendaResponse(
        date: date,
        granularity: 'day',
        from: date,
        to: date,
        routineItems: [],
      );
  @override
  Future<CachedAgenda?> getCachedAgenda(String date) async => null;
  @override
  Future<void> cacheAgenda(String date, AgendaResponse response) async {}
  @override
  Future<void> resolveOccurrence(
    String routineId,
    OccurrenceStatus status, {
    String? scheduledFor,
  }) async {}
  @override
  Future<void> unresolveOccurrence(String routineId,
      {String? scheduledFor}) async {}
  @override
  Future<void> refreshCalendars() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  final overrides = [
    storageServiceProvider.overrideWithValue(_StubStorageService()),
    backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
    agendaRepositoryProvider.overrideWithValue(_StubAgendaRepository()),
    ...notificationStubOverrides(),
    ...sessionControlTestOverrides,
  ];

  group('5-tab navigation', () {
    testWidgets('initial location is /record (center tab)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const App()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record'), findsWidgets);

      final navBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navBar.selectedIndex, 2);
    });

    testWidgets('all 5 tab destinations render', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const App()),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5);
    });

    testWidgets('switching tabs preserves state (indexedStack)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const App()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record'), findsWidgets);

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navBar.selectedIndex, 2);
    });
  });

  group('routines inside the Agenda (ADR-ARCH-012)', () {
    testWidgets('an old /routines/:id address opens the routine in the Agenda',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides,
            routinesRepositoryProvider
                .overrideWithValue(FakeRoutinesRepository()),
            pendingDeepLinkProvider.overrideWith((ref) => '/routines/rtn-1'),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoutineDetailScreen), findsOneWidget);
      expect(
        tester.widget<RoutineDetailScreen>(find.byType(RoutineDetailScreen))
            .routineId,
        'rtn-1',
      );
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar))
          .selectedIndex, 0);
    });
  });

  group('the routines\' old addresses (ADR-ARCH-012)', () {
    Future<void> open(WidgetTester tester, String link) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides,
            routinesRepositoryProvider
                .overrideWithValue(FakeRoutinesRepository()),
            pendingDeepLinkProvider.overrideWith((ref) => link),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('/routines opens the Agenda', (tester) async {
      await open(tester, '/routines');

      expect(tester.widget<NavigationBar>(find.byType(NavigationBar))
          .selectedIndex, 0);
      expect(find.byKey(const Key('agenda-routines-section')), findsOneWidget);
    });

    testWidgets('/routines/:id/edit opens the routine\'s form', (tester) async {
      await open(tester, '/routines/rtn-1/edit');

      expect(find.byType(RoutineFormScreen), findsOneWidget);
    });
  });

  group('an arrival alert\'s route (ADR-NOTIF-003)', () {
    final shoppingOverrides = [
      ...overrides,
      shoppingRepositoryProvider.overrideWithValue(FakeShoppingRepository()),
      shoppingProposalsPortProvider.overrideWithValue(FakeShoppingProposals()),
    ];

    testWidgets('a cold start opens Shopping with the place\'s types',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...shoppingOverrides,
            pendingDeepLinkProvider.overrideWith(
              (ref) => '/shopping?store=electrical,grocery',
            ),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      final screen = tester.widget<ShoppingScreen>(find.byType(ShoppingScreen));
      expect(screen.placeTypes, ['electrical', 'grocery']);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar))
          .selectedIndex, 1);
    });

    testWidgets('a warm tap opens it too', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...shoppingOverrides,
            notificationTapStreamProvider.overrideWith(
              (ref) => Stream.value('/shopping?store=electrical'),
            ),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      final screen = tester.widget<ShoppingScreen>(find.byType(ShoppingScreen));
      expect(screen.placeTypes, ['electrical']);
    });
  });
}
