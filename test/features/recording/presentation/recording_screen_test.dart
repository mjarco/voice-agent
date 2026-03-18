import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/app/app.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/providers/api_url_provider.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';

class _StubStorage implements StorageService {
  @override Future<String> getDeviceId() async => 'test';
  @override Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({int limit = 20, int offset = 0}) async => [];
  @override Future<void> saveTranscript(Transcript t) async {}
  @override Future<Transcript?> getTranscript(String id) async => null;
  @override Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async => [];
  @override Future<void> deleteTranscript(String id) async {}
  @override Future<void> enqueue(String transcriptId) async {}
  @override Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override Future<void> markSending(String id) async {}
  @override Future<void> markSent(String id) async {}
  @override Future<void> markFailed(String id, String error) async {}
  @override Future<void> markPendingForRetry(String id) async {}
  @override Future<void> reactivateForResend(String transcriptId) async {}
}

class _NoOpConnectivity extends ConnectivityService {
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

List<Override> get _baseOverrides => [
  storageServiceProvider.overrideWithValue(_StubStorage()),
  connectivityServiceProvider.overrideWith((_) => _NoOpConnectivity()),
];

void main() {
  testWidgets('Record screen shows mic button in idle state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._baseOverrides,
          apiUrlConfiguredProvider.overrideWithValue(true),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic), findsWidgets);
    expect(find.text('Tap to record'), findsOneWidget);
  });

  testWidgets('Record screen shows banner when API not configured',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _baseOverrides, child: const App()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Set up your API endpoint in Settings to sync your transcripts.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Record screen hides banner when API configured',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._baseOverrides,
          apiUrlConfiguredProvider.overrideWithValue(true),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Set up your API endpoint in Settings to sync your transcripts.',
      ),
      findsNothing,
    );
  });
}
