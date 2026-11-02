import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/core/network/pin_writer.dart';
import 'package:voice_agent/features/pins/domain/pin_draft_store.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/presentation/pin_form_screen.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';

class _FakeWriter implements PinWriter {
  /// Answers by text; a text with no entry gets 'Proposed'.
  final Map<String, Completer<PinSuggestion>> held = {};
  PinSuggestion suggestion = const PinSuggestion(
    name: 'Proposed',
    topicLabel: 'Kuchnia',
    aliases: ['ciasto'],
  );
  Exception? suggestError;
  Exception? saveError;
  Completer<void>? saveHold;

  final List<String> suggested = [];
  final List<PinTextCreateRequest> created = [];
  final List<(String, String?, String?)> edits = [];

  PinDetail _saved(String id, String name, String text) => PinDetail(
        recordId: id,
        pinName: name,
        text: text,
        createdAt: DateTime.utc(2026, 11, 2),
      );

  @override
  Future<PinSuggestion> suggestPinFromText(String text) {
    suggested.add(text);
    if (suggestError != null) return Future.error(suggestError!);
    final hold = held[text];
    return hold != null ? hold.future : Future.value(suggestion);
  }

  @override
  Future<PinCreateResult> createTextPin(PinTextCreateRequest request) async {
    created.add(request);
    await saveHold?.future;
    if (saveError != null) throw saveError!;
    return PinCreateResult(
      pin: _saved('new-id', request.name, request.text),
      created: true,
    );
  }

  @override
  Future<PinCreateResult> editPin(
    String recordId, {
    String? name,
    String? text,
  }) async {
    edits.add((recordId, name, text));
    if (saveError != null) throw saveError!;
    return PinCreateResult(
      pin: _saved('edited-id', name ?? '', text ?? ''),
      created: true,
    );
  }

  @override
  Future<PinSuggestion> suggestPin(String conversationId, String eventId) =>
      throw UnimplementedError();

  @override
  Future<PinCreateResult> createPin(PinCreateRequest request) =>
      throw UnimplementedError();
}

class _FakeDrafts implements PinDraftStore {
  final Map<String?, PinDraft> drafts = {};
  int writes = 0;
  bool loadFails = false;

  @override
  Future<PinDraft?> load(String? recordId) async {
    if (loadFails) throw Exception('broken');
    return drafts[recordId];
  }

  @override
  Future<void> save(String? recordId, PinDraft draft) async {
    writes++;
    drafts[recordId] = draft;
  }

  @override
  Future<void> remove(String? recordId) async {
    drafts.remove(recordId);
  }
}

final _pin = PinDetail(
  recordId: 'old-id',
  pinName: 'Tarta',
  text: 'old text',
  createdAt: DateTime.utc(2026, 11, 1),
);

const _delay = PinFormScreen.proposalDelay;
final _textField = find.byKey(const Key('pin-form-text'));
final _titleField = find.byKey(const Key('pin-form-title'));
final _save = find.byKey(const Key('pin-form-save'));

String _title(WidgetTester tester) =>
    tester.widget<TextField>(_titleField).controller!.text;

String _text(WidgetTester tester) =>
    tester.widget<TextField>(_textField).controller!.text;

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(_save).onPressed != null;

/// Pumps the form over a page that shows what the form popped with.
Future<void> _pump(
  WidgetTester tester,
  _FakeWriter writer, {
  PinDetail? pin,
  String? initialText,
  _FakeDrafts? drafts,
}) async {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, state) => const _Start(),
      ),
      GoRoute(
        path: '/form',
        builder: (context, state) =>
            PinFormScreen(pin: pin, initialText: initialText),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pinWriterProvider.overrideWithValue(writer),
        pinDraftStoreProvider.overrideWithValue(drafts ?? _FakeDrafts()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

class _Start extends StatefulWidget {
  const _Start();

  @override
  State<_Start> createState() => _StartState();
}

class _StartState extends State<_Start> {
  String _result = 'nothing yet';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text(_result),
          TextButton(
            onPressed: () async {
              final saved = await context.push<PinDetail>('/form');
              setState(() => _result = 'popped ${saved?.recordId}');
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

void main() {
  group('new pin', () {
    testWidgets('proposes a title only after the text stops changing',
        (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer);

      await tester.enterText(_textField, 'first');
      await tester.pump(_delay - const Duration(milliseconds: 100));
      await tester.enterText(_textField, 'second');
      await tester.pump(_delay - const Duration(milliseconds: 100));
      expect(writer.suggested, isEmpty);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(writer.suggested, ['second']);
      expect(_title(tester), 'Proposed');
    });

    testWidgets('ignores the answer for an older text', (tester) async {
      final writer = _FakeWriter();
      final older = Completer<PinSuggestion>();
      writer.held['first'] = older;
      await _pump(tester, writer);

      await tester.enterText(_textField, 'first');
      await tester.pump(_delay);
      await tester.enterText(_textField, 'second');
      await tester.pump(_delay);
      await tester.pump();
      older.complete(const PinSuggestion(name: 'Too late'));
      await tester.pump();

      expect(_title(tester), 'Proposed');
    });

    testWidgets('does not replace a title the owner typed', (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer);

      await tester.enterText(_titleField, 'Mine');
      await tester.enterText(_textField, 'text');
      await tester.pump(_delay);
      await tester.pump();

      expect(_title(tester), 'Mine');
    });

    testWidgets('a failed proposal says so and blocks nothing', (tester) async {
      final writer = _FakeWriter()
        ..suggestError = PinsGeneralException('offline');
      await _pump(tester, writer);

      await tester.enterText(_textField, 'text');
      await tester.pump(_delay);
      await tester.pump();

      expect(find.text('No proposal, type a title'), findsOneWidget);
      expect(_saveEnabled(tester), isFalse);

      await tester.enterText(_titleField, 'Mine');
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(writer.created.single.name, 'Mine');
      expect(find.text('popped new-id'), findsOneWidget);
    });

    testWidgets('a starting text is proposed for at once', (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer, initialText: 'shared');

      expect(writer.suggested, ['shared']);
      expect(_text(tester), 'shared');
      expect(_title(tester), 'Proposed');
    });

    testWidgets('saves the text as typed with the proposed topic and aliases',
        (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer);

      await tester.enterText(_textField, '  line 1\nline 2\n');
      await tester.pump(_delay);
      await tester.pump();
      await tester.enterText(_titleField, ' Tarta ');
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      final saved = writer.created.single;
      expect(saved.text, '  line 1\nline 2\n');
      expect(saved.name, 'Tarta');
      expect(saved.topicLabel, 'Kuchnia');
      expect(saved.aliases, ['ciasto']);
    });

    testWidgets('a refusal keeps both fields and shows the server message',
        (tester) async {
      final writer = _FakeWriter()
        ..saveError = PinRefusedException('name_taken', 'wybierz inny tytuł');
      await _pump(tester, writer);

      await tester.enterText(_textField, 'text');
      await tester.pump(_delay);
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('Not saved: wybierz inny tytuł'), findsOneWidget);
      expect(_text(tester), 'text');
      expect(_title(tester), 'Proposed');
      expect(_saveEnabled(tester), isTrue);
    });

    testWidgets('a changed text drops the old topic and aliases',
        (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer);

      await tester.enterText(_textField, 'recipe');
      await tester.pump(_delay);
      await tester.pump();
      await tester.enterText(_textField, 'something else');
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      final saved = writer.created.single;
      expect(saved.topicLabel, isNull);
      expect(saved.aliases, isEmpty);
    });

    testWidgets('a failed proposal drops the old topic and aliases',
        (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer);

      await tester.enterText(_textField, 'recipe');
      await tester.pump(_delay);
      await tester.pump();
      writer.suggestError = PinsGeneralException('offline');
      await tester.enterText(_textField, 'something else');
      await tester.pump(_delay);
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(writer.created.single.topicLabel, isNull);
      expect(writer.created.single.aliases, isEmpty);
    });

    testWidgets('a failure for an older text says nothing', (tester) async {
      final writer = _FakeWriter();
      final older = Completer<PinSuggestion>();
      writer.held['first'] = older;
      await _pump(tester, writer);

      await tester.enterText(_textField, 'first');
      await tester.pump(_delay);
      await tester.enterText(_textField, 'second');
      await tester.pump(_delay);
      await tester.pump();
      older.completeError(PinsGeneralException('offline'));
      await tester.pump();
      await tester.enterText(_titleField, '');
      await tester.pump();

      expect(find.text('No proposal, type a title'), findsNothing);
    });

    testWidgets('Save cancels a waiting proposal', (tester) async {
      final writer = _FakeWriter()..saveHold = Completer<void>();
      await _pump(tester, writer);

      await tester.enterText(_titleField, 'Mine');
      await tester.enterText(_textField, 'text');
      await tester.pump();
      await tester.tap(_save);
      await tester.pump(_delay * 2);

      expect(writer.suggested, isEmpty);
      writer.saveHold!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('leaving the form cancels a waiting proposal', (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer);

      await tester.enterText(_textField, 'text');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pump(_delay * 2);

      expect(find.text('popped null'), findsOneWidget);
      expect(writer.suggested, isEmpty);
    });

    testWidgets('during a save, Back waits and Save is off', (tester) async {
      final writer = _FakeWriter()..saveHold = Completer<void>();
      await _pump(tester, writer);

      await tester.enterText(_textField, 'text');
      await tester.pump(_delay);
      await tester.pump();
      await tester.tap(_save);
      await tester.pump();

      expect(_saveEnabled(tester), isFalse);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(PinFormScreen), findsOneWidget);

      writer.saveHold!.complete();
      await tester.pumpAndSettle();

      expect(writer.created, hasLength(1));
      expect(find.text('popped new-id'), findsOneWidget);
    });

    testWidgets('save is off without a text or a title', (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer);
      expect(_saveEnabled(tester), isFalse);

      await tester.enterText(_titleField, 'Mine');
      await tester.pump();
      expect(_saveEnabled(tester), isFalse);

      await tester.enterText(_textField, '   ');
      await tester.pump();
      expect(_saveEnabled(tester), isFalse);
      expect(writer.suggested, isEmpty);
    });
  });

  group('edit', () {
    testWidgets('fills the form and proposes nothing', (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer, pin: _pin);

      expect(_title(tester), 'Tarta');
      expect(_text(tester), 'old text');

      await tester.enterText(_textField, 'new text');
      await tester.pump(_delay);
      await tester.pump();

      expect(writer.suggested, isEmpty);
      expect(_title(tester), 'Tarta');
    });

    testWidgets('sends only the changed field and returns the new version',
        (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer, pin: _pin);

      await tester.enterText(_textField, 'new text');
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(writer.edits.single, ('old-id', null, 'new text'));
      expect(find.text('popped edited-id'), findsOneWidget);
    });

    testWidgets('nothing changed closes the form with no write',
        (tester) async {
      final writer = _FakeWriter();
      await _pump(tester, writer, pin: _pin);

      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(writer.edits, isEmpty);
      expect(find.text('popped null'), findsOneWidget);
    });

    testWidgets('a stale edit keeps the text and shows the server message',
        (tester) async {
      final writer = _FakeWriter()
        ..saveError = PinRefusedException('pin_changed', 'wczytaj ponownie');
      await _pump(tester, writer, pin: _pin);

      await tester.enterText(_textField, 'new text');
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('Not saved: wczytaj ponownie'), findsOneWidget);
      expect(_text(tester), 'new text');
      expect(find.text('Copy text'), findsOneWidget);
    });

    testWidgets('other refusals offer no copy', (tester) async {
      final writer = _FakeWriter()
        ..saveError = PinRefusedException('name_taken', 'wybierz inny tytuł');
      await _pump(tester, writer, pin: _pin);

      await tester.enterText(_titleField, 'Taken');
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('Copy text'), findsNothing);
    });
  });

  group('draft', () {
    const typed = PinDraft(title: 'Mine', text: 'kept', titleTyped: true);
    const proposed = PinDraft(title: 'Old', text: 'kept', titleTyped: false);
    final banner = find.byKey(const Key('pin-form-draft'));
    final discard = find.byKey(const Key('pin-form-draft-discard'));
    const wait = PinFormScreen.draftDelay;

    testWidgets('is written only after the fields stop changing',
        (tester) async {
      final drafts = _FakeDrafts();
      await _pump(tester, _FakeWriter(), drafts: drafts);

      await tester.enterText(_textField, 'first');
      await tester.pump(wait - const Duration(milliseconds: 100));
      await tester.enterText(_textField, 'second');
      await tester.pump(wait - const Duration(milliseconds: 100));
      expect(drafts.writes, 0);

      await tester.pump(const Duration(milliseconds: 100));

      expect(drafts.writes, 1);
      expect(drafts.drafts[null]?.text, 'second');
    });

    testWidgets('Back keeps what was typed for the next form', (tester) async {
      final drafts = _FakeDrafts();
      await _pump(tester, _FakeWriter(), drafts: drafts);

      await tester.enterText(_titleField, 'Mine');
      await tester.enterText(_textField, 'typed');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(drafts.drafts[null]?.title, 'Mine');
      expect(drafts.drafts[null]?.text, 'typed');
      expect(drafts.drafts[null]?.titleTyped, isTrue);
    });

    testWidgets('going to the background writes at once', (tester) async {
      final drafts = _FakeDrafts();
      await _pump(tester, _FakeWriter(), drafts: drafts);

      await tester.enterText(_textField, 'typed');
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(Duration.zero);
      final text = drafts.drafts[null]?.text;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(text, 'typed');
    });

    testWidgets('a typed draft comes back without a proposal', (tester) async {
      final writer = _FakeWriter();
      final drafts = _FakeDrafts()..drafts[null] = typed;
      await _pump(tester, writer, drafts: drafts);

      expect(banner, findsOneWidget);
      expect(_title(tester), 'Mine');
      expect(_text(tester), 'kept');
      expect(writer.suggested, isEmpty);
    });

    testWidgets('a proposed title is asked for again', (tester) async {
      final writer = _FakeWriter();
      final drafts = _FakeDrafts()..drafts[null] = proposed;
      await _pump(tester, writer, drafts: drafts);

      expect(writer.suggested, ['kept']);
      expect(_title(tester), 'Proposed');
    });

    testWidgets('no draft shows no banner', (tester) async {
      await _pump(tester, _FakeWriter());

      expect(banner, findsNothing);
    });

    testWidgets('a broken draft leaves the form working', (tester) async {
      final drafts = _FakeDrafts()..loadFails = true;
      await _pump(tester, _FakeWriter(), drafts: drafts, pin: _pin);

      await tester.enterText(_textField, 'new text');
      await tester.pump();

      expect(_text(tester), 'new text');
      expect(_saveEnabled(tester), isTrue);
    });

    testWidgets('an edit has its own draft', (tester) async {
      final drafts = _FakeDrafts()..drafts[null] = typed;
      await _pump(tester, _FakeWriter(), drafts: drafts, pin: _pin);

      expect(banner, findsNothing);
      expect(_text(tester), 'old text');

      await tester.enterText(_textField, 'edited');
      await tester.pump(wait);

      expect(drafts.drafts['old-id']?.text, 'edited');
      expect(drafts.drafts[null]?.text, 'kept');
    });

    testWidgets('an edit back to the pin leaves no draft', (tester) async {
      final drafts = _FakeDrafts();
      await _pump(tester, _FakeWriter(), drafts: drafts, pin: _pin);

      await tester.enterText(_textField, 'edited');
      await tester.pump(wait);
      await tester.enterText(_textField, 'old text');
      await tester.pump(wait);

      expect(drafts.drafts, isEmpty);
    });

    testWidgets('emptied fields leave no draft', (tester) async {
      final drafts = _FakeDrafts()..drafts[null] = typed;
      await _pump(tester, _FakeWriter(), drafts: drafts);

      await tester.enterText(_titleField, '');
      await tester.enterText(_textField, '');
      await tester.pump(wait);

      expect(drafts.drafts, isEmpty);
    });

    testWidgets('a save removes the draft and writes none after it',
        (tester) async {
      final drafts = _FakeDrafts();
      await _pump(tester, _FakeWriter(), drafts: drafts);

      await tester.enterText(_titleField, 'Mine');
      await tester.enterText(_textField, 'typed');
      await tester.pump(wait);
      expect(drafts.drafts, isNotEmpty);
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('popped new-id'), findsOneWidget);
      expect(drafts.drafts, isEmpty);
    });

    testWidgets('a failed save keeps the draft', (tester) async {
      final writer = _FakeWriter()..saveError = Exception('offline');
      final drafts = _FakeDrafts()..drafts[null] = typed;
      await _pump(tester, writer, drafts: drafts);

      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(drafts.drafts[null]?.text, 'kept');
    });

    testWidgets('Discard on a new pin empties the form', (tester) async {
      final writer = _FakeWriter();
      final drafts = _FakeDrafts()..drafts[null] = typed;
      await _pump(tester, writer, drafts: drafts);

      await tester.tap(discard);
      await tester.pumpAndSettle();

      expect(banner, findsNothing);
      expect(_title(tester), '');
      expect(_text(tester), '');
      expect(drafts.drafts, isEmpty);
    });

    testWidgets('after Discard a new title may be proposed', (tester) async {
      final writer = _FakeWriter();
      final drafts = _FakeDrafts()..drafts[null] = typed;
      await _pump(tester, writer, drafts: drafts);

      await tester.tap(discard);
      await tester.pumpAndSettle();
      await tester.enterText(_textField, 'fresh');
      await tester.pump(_delay);
      await tester.pump();

      expect(_title(tester), 'Proposed');
    });

    testWidgets('Discard on an edit returns to the pin', (tester) async {
      final drafts = _FakeDrafts()..drafts['old-id'] = typed;
      await _pump(tester, _FakeWriter(), drafts: drafts, pin: _pin);

      expect(_text(tester), 'kept');
      await tester.tap(discard);
      await tester.pumpAndSettle();

      expect(_title(tester), 'Tarta');
      expect(_text(tester), 'old text');
      expect(drafts.drafts, isEmpty);
    });

    testWidgets('text brought to the form joins the draft', (tester) async {
      final drafts = _FakeDrafts()..drafts[null] = typed;
      await _pump(
        tester,
        _FakeWriter(),
        drafts: drafts,
        initialText: 'shared',
      );

      expect(_text(tester), 'kept\n\nshared');
      expect(_title(tester), 'Mine');
    });

    testWidgets('leaving a stale edit removes its draft', (tester) async {
      final writer = _FakeWriter()
        ..saveError = PinRefusedException('pin_changed', 'wczytaj ponownie');
      final drafts = _FakeDrafts();
      await _pump(tester, writer, drafts: drafts, pin: _pin);

      await tester.enterText(_textField, 'new text');
      await tester.pump(wait);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(drafts.drafts['old-id']?.text, 'new text');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(drafts.drafts, isEmpty);
    });
  });
}
