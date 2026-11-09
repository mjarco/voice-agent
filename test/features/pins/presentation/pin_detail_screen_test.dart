import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/links/link_opener.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';
import 'package:voice_agent/features/pins/presentation/pin_detail_screen.dart';

class _StubRepository implements PinsRepository {
  PinDetail? pin;
  Exception? fetchError;
  Exception? unpinError;
  String? lastUnpinId;
  int fetchCount = 0;

  @override
  Future<List<PinSummary>> fetchPins() async =>
      throw UnimplementedError();

  @override
  Future<PinDetail> fetchPin(String recordId) async {
    fetchCount++;
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

class _FakeLinkOpener implements LinkOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    if (!isOpenableLink(uri)) return false;
    opened.add(uri);
    return true;
  }
}

PinDetail _pinWith(String text) => PinDetail(
      recordId: 'abc',
      pinName: 'pin abc',
      text: text,
      createdAt: DateTime.utc(2026, 11, 6),
    );

Future<void> _pump(
  WidgetTester tester,
  PinsRepository repo, {
  LinkOpener? opener,
}) async {
  final router = GoRouter(
    initialLocation: '/pins/abc',
    routes: [
      GoRoute(
        path: '/pins',
        builder: (context, state) => const Scaffold(body: Text('Pins list')),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                PinDetailScreen(recordId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final pin = state.extra! as PinDetail;
                  return Scaffold(
                    body: Column(
                      children: [
                        TextButton(
                          onPressed: () => context.pop(
                            PinDetail(
                              recordId: 'edited',
                              pinName: pin.pinName,
                              text: pin.text,
                              createdAt: pin.createdAt,
                            ),
                          ),
                          child: const Text('Save form'),
                        ),
                        TextButton(
                          onPressed: () => context.pop(),
                          child: const Text('Cancel form'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/conversation/:id',
        builder: (context, state) =>
            Scaffold(body: Text('Thread ${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pinsRepositoryProvider.overrideWithValue(repo),
        linkOpenerProvider.overrideWithValue(opener ?? _FakeLinkOpener()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PinDetailScreen', () {
    testWidgets('after an edit the screen follows the new record id',
        (tester) async {
      await _pump(tester, _StubRepository());

      await tester.tap(find.byKey(const Key('pin-detail-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save form'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('pin edited'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('unpin after an edit names the new record id', (tester) async {
      final repo = _StubRepository();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('pin-detail-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save form'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-detail-unpin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-detail-unpin-confirm')));
      await tester.pumpAndSettle();

      expect(repo.lastUnpinId, 'edited');
    });

    testWidgets('a form closed without a write reads the pin again',
        (tester) async {
      final repo = _StubRepository();
      await _pump(tester, repo);
      final fetchesBefore = repo.fetchCount;

      await tester.tap(find.byKey(const Key('pin-detail-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel form'));
      await tester.pumpAndSettle();

      expect(repo.fetchCount, fetchesBefore + 1);
    });

    testWidgets('a pin that is gone after a closed form leads to the list',
        (tester) async {
      final repo = _StubRepository();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('pin-detail-edit')));
      await tester.pumpAndSettle();
      repo.fetchError = PinNotFoundException();
      await tester.tap(find.text('Cancel form'));
      await tester.pumpAndSettle();

      expect(find.text('Pins list'), findsOneWidget);
    });

    testWidgets('a failed read after a closed form stays on the pin',
        (tester) async {
      final repo = _StubRepository();
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('pin-detail-edit')));
      await tester.pumpAndSettle();
      repo.fetchError = PinsGeneralException('offline');
      await tester.tap(find.text('Cancel form'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pin-detail-retry-button')), findsOneWidget);
    });

    testWidgets('a stale unpin leaves for the list and says why',
        (tester) async {
      final repo = _StubRepository()
        ..unpinError = PinRefusedException('pin_changed', 'wczytaj ponownie');
      await _pump(tester, repo);
      repo.fetchError = PinNotFoundException();

      await tester.tap(find.byKey(const Key('pin-detail-unpin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pin-detail-unpin-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Pins list'), findsOneWidget);
      expect(find.text('wczytaj ponownie'), findsOneWidget);
    });

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

    testWidgets('open-conversation action opens the source chat thread',
        (tester) async {
      final repo = _StubRepository()
        ..pin = PinDetail(
          recordId: 'abc',
          pinName: 'pin abc',
          text: '# Heading\n\nbody text',
          conversationId: 'conv-789',
          createdAt: DateTime.utc(2026, 6, 15),
        );
      await _pump(tester, repo);

      final action = find.byKey(const Key('pin-detail-open-conversation'));
      expect(action, findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('Thread conv-789'), findsOneWidget);
    });

    testWidgets('hides the open-conversation action when no source conversation',
        (tester) async {
      final repo = _StubRepository()
        ..pin = PinDetail(
          recordId: 'abc',
          pinName: 'pin abc',
          text: 'body',
          createdAt: DateTime.utc(2026, 6, 15),
        );
      await _pump(tester, repo);

      expect(
        find.byKey(const Key('pin-detail-open-conversation')),
        findsNothing,
      );
    });

    group('an article pinned as Markdown', () {
      testWidgets('a tapped web link opens in another app', (tester) async {
        final opener = _FakeLinkOpener();
        await _pump(
          tester,
          _StubRepository()..pin = _pinWith('[Go blog](https://go.dev/blog)'),
          opener: opener,
        );

        await tester.tap(find.text('Go blog', findRichText: true));
        await tester.pumpAndSettle();

        expect(opener.opened, [Uri.parse('https://go.dev/blog')]);
      });

      testWidgets('a link that is not web or mail is not opened and says so',
          (tester) async {
        final opener = _FakeLinkOpener();
        await _pump(
          tester,
          _StubRepository()..pin = _pinWith('[run](javascript:alert(1))'),
          opener: opener,
        );

        await tester.tap(find.text('run', findRichText: true));
        await tester.pumpAndSettle();

        expect(opener.opened, isEmpty);
        expect(find.textContaining('Cannot open the link'), findsOneWidget);
      });

      testWidgets('a table keeps its columns and scrolls sideways',
          (tester) async {
        await _pump(
          tester,
          _StubRepository()
            ..pin = _pinWith(
              '| GPIO | Function |\n| --- | --- |\n| 21 | SDA |\n| 22 | SCL |',
            ),
        );

        final table = find.byType(Table);
        expect(table, findsOneWidget);
        expect(
          tester.widget<Table>(table).defaultColumnWidth,
          isA<IntrinsicColumnWidth>(),
        );
        final scroll = find.ancestor(
          of: table,
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        );
        expect(scroll, findsOneWidget);
      });

      testWidgets('an image that is not on the web shows its description',
          (tester) async {
        await _pump(
          tester,
          _StubRepository()..pin = _pinWith('![Starter jar](file:///etc/x.png)'),
        );

        expect(find.byKey(const Key('pin-detail-image')), findsNothing);
        expect(find.byKey(const Key('pin-detail-image-fallback')), findsOneWidget);
        expect(find.text('Starter jar'), findsOneWidget);
      });

      testWidgets('a web image that fails to load shows its description',
          (tester) async {
        await _pump(
          tester,
          _StubRepository()
            ..pin = _pinWith('![Starter jar](https://example.org/jar.jpg)'),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('pin-detail-image')), findsOneWidget);
        expect(find.byKey(const Key('pin-detail-image-fallback')), findsOneWidget);
      });
    });
  });
}
