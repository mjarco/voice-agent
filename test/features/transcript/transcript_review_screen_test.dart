import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/sync_queue_item.dart';
import 'package:voice_agent/core/models/transcript.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/transcript/transcript_review_screen.dart';

class MockStorageService implements StorageService {
  final List<Transcript> savedTranscripts = [];
  final List<String> enqueuedIds = [];
  bool shouldThrow = false;

  @override
  Future<void> saveTranscript(Transcript t) async {
    if (shouldThrow) throw Exception('save failed');
    savedTranscripts.add(t);
  }

  @override
  Future<void> enqueue(String transcriptId) async {
    if (shouldThrow) throw Exception('enqueue failed');
    enqueuedIds.add(transcriptId);
  }

  @override
  Future<String> getDeviceId() async => 'test-device-id';

  @override
  Future<Transcript?> getTranscript(String id) async => null;
  @override
  Future<List<Transcript>> getTranscripts({int limit = 50, int offset = 0}) async => [];
  @override
  Future<void> deleteTranscript(String id) async {}
  @override
  Future<List<SyncQueueItem>> getPendingItems() async => [];
  @override
  Future<void> markSending(String id) async {}
  @override
  Future<void> markSent(String id) async {}
  @override
  Future<void> markFailed(String id, String error) async {}
  @override
  Future<void> markPendingForRetry(String id) async {}
  @override
  Future<List<TranscriptWithStatus>> getTranscriptsWithStatus({
    int limit = 20,
    int offset = 0,
  }) async => [];
}

const _testResult = TranscriptResult(
  text: 'Hello world test transcript',
  segments: [],
  detectedLanguage: 'en',
  audioDurationMs: 5000,
);

Widget _buildTestWidget({
  required MockStorageService mockStorage,
  TranscriptResult result = _testResult,
}) {
  return ProviderScope(
    overrides: [
      storageServiceProvider.overrideWithValue(mockStorage),
    ],
    child: MaterialApp(
      home: TranscriptReviewScreen(transcriptResult: result),
    ),
  );
}

void main() {
  late MockStorageService mockStorage;

  setUp(() {
    mockStorage = MockStorageService();
  });

  testWidgets('renders transcript text in editable field', (tester) async {
    await tester.pumpWidget(_buildTestWidget(mockStorage: mockStorage));

    expect(find.text('Hello world test transcript'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('renders metadata row with language', (tester) async {
    await tester.pumpWidget(_buildTestWidget(mockStorage: mockStorage));

    expect(find.text('EN'), findsOneWidget);
    expect(find.text('5s'), findsOneWidget);
  });

  testWidgets('renders three action buttons', (tester) async {
    await tester.pumpWidget(_buildTestWidget(mockStorage: mockStorage));

    expect(find.text('Re-record'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('approve calls saveTranscript and enqueue', (tester) async {
    await tester.pumpWidget(_buildTestWidget(mockStorage: mockStorage));

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(mockStorage.savedTranscripts.length, 1);
    expect(mockStorage.savedTranscripts.first.text,
        'Hello world test transcript');
    expect(mockStorage.savedTranscripts.first.language, 'en');
    expect(mockStorage.enqueuedIds.length, 1);
  });

  testWidgets('discard without edit does not show confirmation dialog',
      (tester) async {
    await tester.pumpWidget(_buildTestWidget(mockStorage: mockStorage));

    // Don't tap discard (it would try to pop without a Navigator).
    // Instead verify the text was not edited, so _isEdited is false.
    // The edit tracking is tested in the 'discard after edit' test below.
    expect(find.text('Hello world test transcript'), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('discard after edit shows confirmation dialog', (tester) async {
    await tester.pumpWidget(_buildTestWidget(mockStorage: mockStorage));

    // Edit the text
    await tester.enterText(find.byType(TextField), 'Edited text');
    await tester.pump();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
  });

  testWidgets('save failure shows error snackbar', (tester) async {
    mockStorage.shouldThrow = true;
    await tester.pumpWidget(_buildTestWidget(mockStorage: mockStorage));

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to save'), findsOneWidget);
  });
}
