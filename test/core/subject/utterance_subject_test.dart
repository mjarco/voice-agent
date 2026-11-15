import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/subject/utterance_subject.dart';

void main() {
  group('UtteranceSubject (ADR-NET-008)', () {
    test('a matter screen in either place is the matter', () {
      expect(UtteranceSubject.ofLocation('/matters/m-1'), const UtteranceSubject.matter('m-1'));
      expect(UtteranceSubject.ofLocation('/matter/m-1'), const UtteranceSubject.matter('m-1'));
    });

    test('every other screen is Dzień', () {
      for (final path in ['/today', '/matters', '/matters/new', '/dietary', '/conversation/c-1', '/chat/c-1', '/matters/m-1/edit']) {
        expect(UtteranceSubject.ofLocation(path), UtteranceSubject.day, reason: path);
      }
    });

    test('the key and the request field', () {
      const m = UtteranceSubject.matter('m-1');
      expect(m.key, 'matter:m-1');
      expect(UtteranceSubject.ofKey(m.key), m);
      expect(m.toJson(), {'kind': 'matter', 'matter_id': 'm-1'});
      expect(UtteranceSubject.day.key, isNull);
      expect(UtteranceSubject.day.toJson(), isNull);
      expect(UtteranceSubject.ofKey(null), UtteranceSubject.day);
      expect(UtteranceSubject.ofKey('food:x'), UtteranceSubject.day);
      expect(UtteranceSubject.ofKey('matter:'), UtteranceSubject.day);
    });
  });

  group('UtteranceSubject.diet (ADR-NET-009)', () {
    test("the diet's screens are Jedzenie", () {
      for (final path in ['/diet', '/diet?day=2026-11-14', '/diet/menu', '/diet/own-meals', '/diet/target']) {
        expect(UtteranceSubject.ofLocation(path), UtteranceSubject.diet, reason: path);
      }
    });

    test('the key and the request field', () {
      const d = UtteranceSubject.diet;
      expect(d.isDay, isFalse);
      expect(d.matterId, isNull);
      expect(d.key, 'diet');
      expect(UtteranceSubject.ofKey('diet'), d);
      expect(d.toJson(), {'kind': 'diet'});
      expect(d == UtteranceSubject.day, isFalse);
    });
  });
}
