import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/background/background_service_provider.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/core/providers/deep_link_providers.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/features/pins/domain/pin_draft_store.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/presentation/pin_form_screen.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';

import '../helpers/stub_background_service.dart';
import '../helpers/stub_notifications.dart';
import '../helpers/stub_session_control.dart';

class _StubStorageService with TelemetryStorageNoop implements StorageService {
  @override
  Future<String> getDeviceId() async => 'test-device';
  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  }) async => [];
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
  Future<int> recoverStaleSending() async => 0;
  @override
  Future<List<SyncQueueItem>> getFailedItems({int? maxAttempts}) async => [];
}

class _NoOpConnectivity extends ConnectivityService {
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
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

class _StubPinWriter implements PinWriter {
  @override
  Future<PinSuggestion> suggestPinFromText(String text) async =>
      const PinSuggestion(name: 'Proposed', aliases: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubPinsRepository implements PinsRepository {
  int fetches = 0;

  @override
  Future<List<PinSummary>> fetchPins(PinView view) async {
    fetches++;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _MemoryDrafts implements PinDraftStore {
  final Map<String?, PinDraft> drafts = {};

  @override
  Future<PinDraft?> load(String? recordId) async => drafts[recordId];

  @override
  Future<void> save(String? recordId, PinDraft draft) async {
    drafts[recordId] = draft;
  }

  @override
  Future<void> remove(String? recordId) async {
    drafts.remove(recordId);
  }
}

List<Override> get _testOverrides => [
      storageServiceProvider.overrideWithValue(_StubStorageService()),
      connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
      backgroundServiceProvider.overrideWithValue(StubBackgroundService()),
      agendaRepositoryProvider.overrideWithValue(_StubAgendaRepository()),
      ...notificationStubOverrides(),
      ...sessionControlTestOverrides,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  testWidgets('App renders with shell and 5 tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Agenda'), findsWidgets);
    expect(find.text('Shopping'), findsWidgets);
    expect(find.text('Record'), findsWidgets);
    expect(find.text('Routines'), findsWidgets);
    expect(find.text('Chat'), findsWidgets);
  });

  testWidgets('Default tab is Record (index 2)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 2);
  });

  testWidgets('Tapping Agenda tab switches to index 0', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 0);
  });

  testWidgets('Tapping Chat tab switches to index 4', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();

    final navBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navBar.selectedIndex, 4);
  });

  testWidgets('App uses Material 3', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _testOverrides, child: const App()),
    );

    final materialApp = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(materialApp.theme?.useMaterial3, isTrue);
  });

  group('shared text', () {
    final form = find.byType(PinFormScreen);
    final textField = find.byKey(const Key('pin-form-text'));

    String formText(WidgetTester tester) =>
        tester.widget<TextField>(textField).controller!.text;

    Future<StreamController<SharedText>> pump(
      WidgetTester tester, {
      String? cold,
      _MemoryDrafts? drafts,
      _StubPinsRepository? pins,
    }) async {
      final warm = StreamController<SharedText>();
      addTearDown(warm.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._testOverrides,
            pinWriterProvider.overrideWithValue(_StubPinWriter()),
            pinsRepositoryProvider.overrideWithValue(
              pins ?? _StubPinsRepository(),
            ),
            pinDraftStoreProvider.overrideWithValue(drafts ?? _MemoryDrafts()),
            pendingSharedTextProvider.overrideWith((ref) => cold),
            sharedTextStreamProvider.overrideWith((ref) => warm.stream),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();
      return warm;
    }

    testWidgets('text that launched the app opens the form once',
        (tester) async {
      await pump(tester, cold: 'shared');

      expect(form, findsOneWidget);
      expect(formText(tester), 'shared');
      final container =
          ProviderScope.containerOf(tester.element(find.byType(App)));
      expect(container.read(pendingSharedTextProvider), isNull);
    });

    testWidgets('blank text opens nothing', (tester) async {
      final warm = await pump(tester, cold: '  ');

      warm.add(SharedText(' \n'));
      await tester.pumpAndSettle();

      expect(form, findsNothing);
    });

    testWidgets('text shared while running opens the form', (tester) async {
      final warm = await pump(tester);

      warm.add(SharedText('shared'));
      await tester.pumpAndSettle();

      expect(formText(tester), 'shared');
    });

    testWidgets('the form opens over the shell, which stays', (tester) async {
      final warm = await pump(tester);

      warm.add(SharedText('shared'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);

      while (form.evaluate().isNotEmpty ||
          find.byType(NavigationBar).evaluate().isEmpty) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
    });

    testWidgets('the same text shared twice opens the form twice',
        (tester) async {
      final warm = await pump(tester);

      warm.add(SharedText('shared'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(form, findsNothing);

      warm.add(SharedText('shared'));
      await tester.pumpAndSettle();

      expect(form, findsOneWidget);
    });

    testWidgets('leaving a shared form reads a loaded list again',
        (tester) async {
      final pins = _StubPinsRepository();
      final warm = await pump(tester, pins: pins);
      ProviderScope.containerOf(tester.element(find.byType(App)))
          .read(pinsNotifierProvider);
      await tester.pump();
      final before = pins.fetches;

      warm.add(SharedText('shared'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(pins.fetches, before + 1);
    });

    testWidgets('leaving a replaced form reads a loaded list again',
        (tester) async {
      final pins = _StubPinsRepository();
      final warm = await pump(tester, cold: 'first', pins: pins);
      ProviderScope.containerOf(tester.element(find.byType(App)))
          .read(pinsNotifierProvider);
      await tester.pump();

      warm.add(SharedText('second'));
      await tester.pumpAndSettle();
      final before = pins.fetches;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(pins.fetches, before + 1);
    });

    testWidgets('a list never opened is not read', (tester) async {
      final pins = _StubPinsRepository();
      final warm = await pump(tester, pins: pins);

      warm.add(SharedText('shared'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(pins.fetches, lessThanOrEqualTo(1));
    });

    testWidgets('a share replaces a new-pin form and joins its draft',
        (tester) async {
      final drafts = _MemoryDrafts();
      final warm = await pump(tester, cold: 'first', drafts: drafts);

      await tester.enterText(textField, 'typed');
      await tester.pump(PinFormScreen.draftDelay);
      warm.add(SharedText('second'));
      await tester.pumpAndSettle();

      expect(form, findsOneWidget);
      expect(formText(tester), 'typed\n\nsecond');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(form, findsNothing);
      expect(drafts.drafts[null]?.text, 'typed\n\nsecond');
    });
  });
}
