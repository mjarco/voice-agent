import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';
import 'package:voice_agent/features/pins/presentation/pin_detail_screen.dart';

class _StubRepository implements PinsRepository {
  PinDetail? pin;
  Exception? fetchError;
  Exception? unpinError;
  String? lastUnpinId;

  @override
  Future<List<PinSummary>> fetchPins(PinView view) async =>
      throw UnimplementedError();

  @override
  Future<PinDetail> fetchPin(String recordId) async {
    if (fetchError != null) throw fetchError!;
    return pin ??
        PinDetail(
          recordId: recordId,
          pinName: 'pin $recordId',
          text: '# Heading\n\nbody text',
          createdAt: DateTime.utc(2026, 6, 15),
        );
  }

  @override
  Future<void> unpin(String recordId) async {
    lastUnpinId = recordId;
    if (unpinError != null) throw unpinError!;
  }
}

Future<void> _pump(WidgetTester tester, PinsRepository repo) async {
  final router = GoRouter(
    initialLocation: '/chat/pins/abc',
    routes: [
      GoRoute(
        path: '/chat/pins',
        builder: (context, state) => const Scaffold(body: Text('Pins list')),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                PinDetailScreen(recordId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [pinsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PinDetailScreen', () {
    testWidgets('renders the pin name and markdown body', (tester) async {
      await _pump(tester, _StubRepository());

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('pin abc'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pin-detail-markdown')), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('copy action puts the verbatim text on the clipboard',
        (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });

      await _pump(tester, _StubRepository());

      await tester.tap(find.byKey(const Key('pin-detail-copy')));
      await tester.pumpAndSettle();

      expect(copied, '# Heading\n\nbody text');

      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('unpin confirmation calls the repository and pops',
        (tester) async {
      final repo = _StubRepository();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('pin-detail-unpin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-detail-unpin-confirm')));
      await tester.pumpAndSettle();

      expect(repo.lastUnpinId, 'abc');
      expect(find.text('Pins list'), findsOneWidget);
    });

    testWidgets('shows the error state with retry on fetch failure',
        (tester) async {
      await _pump(tester, _StubRepository()..fetchError = PinNotFoundException());

      expect(
        find.byKey(const Key('pin-detail-retry-button')),
        findsOneWidget,
      );
    });
  });
}
