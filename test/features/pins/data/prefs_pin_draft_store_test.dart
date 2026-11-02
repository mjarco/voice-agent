import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/features/pins/data/prefs_pin_draft_store.dart';
import 'package:voice_agent/features/pins/domain/pin_draft_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const draft = PinDraft(title: 'Tarta', text: 'ciasto', titleTyped: true);

  group('PrefsPinDraftStore', () {
    test('no draft reads as null', () async {
      expect(await PrefsPinDraftStore().load(null), isNull);
    });

    test('a draft survives a new store', () async {
      await PrefsPinDraftStore().save(null, draft);

      final loaded = await PrefsPinDraftStore().load(null);

      expect(loaded?.title, 'Tarta');
      expect(loaded?.text, 'ciasto');
      expect(loaded?.titleTyped, isTrue);
    });

    test('the new pin and each edited pin have their own draft', () async {
      final store = PrefsPinDraftStore();
      await store.save(null, draft);
      await store.save(
        'a',
        const PinDraft(title: 'A', text: 'edit a', titleTyped: true),
      );

      expect((await store.load(null))?.text, 'ciasto');
      expect((await store.load('a'))?.text, 'edit a');
      expect(await store.load('b'), isNull);
    });

    test('remove takes only the named draft', () async {
      final store = PrefsPinDraftStore();
      await store.save(null, draft);
      await store.save('a', draft);

      await store.remove('a');

      expect(await store.load('a'), isNull);
      expect(await store.load(null), isNotNull);
    });
  });
}
