import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/matter.dart';

void main() {
  group('MatterSummary.fromMap', () {
    test('reads every field of the list row', () {
      final m = MatterSummary.fromMap({
        'id': 'm1',
        'title': 'Remont łazienki',
        'keywords': 'łazienka hydraulik',
        'status': 'waiting',
        'next_step': 'zadzwonić',
        'waiting_for': 'wycena',
        'from_matter_id': 'm0',
        'source': 'chat',
        'last_entry': 'hydraulik przyjdzie',
        'last_activity': '2026-11-01T10:00:00Z',
        'standing_still': true,
        'link_count': 3,
        'created_at': '2026-10-01T10:00:00Z',
        'updated_at': '2026-11-01T10:00:00Z',
      });

      expect(m.title, 'Remont łazienki');
      expect(m.keywords, 'łazienka hydraulik');
      expect(m.status, MatterStatus.waiting);
      expect(m.nextStep, 'zadzwonić');
      expect(m.waitingFor, 'wycena');
      expect(m.fromMatterId, 'm0');
      expect(m.lastEntry, 'hydraulik przyjdzie');
      expect(m.lastActivity, DateTime.utc(2026, 11, 1, 10));
      expect(m.standingStill, isTrue);
      expect(m.linkCount, 3);
    });

    test('a missing or malformed optional field is empty, not an error', () {
      final m = MatterSummary.fromMap({
        'id': 'm1',
        'title': 'T',
        'status': 'someday',
        'link_count': '3',
        'last_activity': 'yesterday',
        'standing_still': 'yes',
      });

      expect(m.status, MatterStatus.unknown);
      expect(m.linkCount, 0);
      expect(m.lastActivity, isNull);
      expect(m.standingStill, isFalse);
      expect(m.nextStep, '');
      expect(m.fromMatterId, isNull);
    });

    test('days still count from the last activity, else the last change', () {
      final now = DateTime.utc(2026, 11, 9, 12);
      expect(
        MatterSummary(
          id: 'a',
          title: 'a',
          lastActivity: DateTime.utc(2026, 10, 30, 12),
        ).daysStill(now),
        10,
      );
      expect(
        MatterSummary(
          id: 'a',
          title: 'a',
          updatedAt: DateTime.utc(2026, 11, 7, 12),
        ).daysStill(now),
        2,
      );
      expect(const MatterSummary(id: 'a', title: 'a').daysStill(now), isNull);
    });
  });

  group('MatterDetail.fromMap', () {
    test('reads the timeline and the links', () {
      final d = MatterDetail.fromMap({
        'id': 'm1',
        'title': 'T',
        'status': 'proposed',
        'timeline': [
          {
            'id': 'e1',
            'kind': 'next_step',
            'text': 'kupić płytki',
            'source': 'phone',
            'day': '2026-11-08',
            'created_at': '2026-11-08T09:00:00Z',
          },
          {'kind': 'tick', 'text': 'Podlać kwiaty', 'day': '2026-11-07'},
        ],
        'links': [
          {
            'id': 'l1',
            'kind': 'conversation',
            'target_id': 'c1',
            'from_event_id': 'ev1',
            'label': 'O płytkach',
            'day': '2026-11-02',
            'turns': 4,
            'missing': false,
            'created_at': '2026-11-02T09:00:00Z',
          },
          {'id': 'l2', 'kind': 'pin', 'target_id': 'p1', 'missing': true},
        ],
      });

      expect(d.matter.status, MatterStatus.proposed);
      expect(d.timeline, hasLength(2));
      expect(d.timeline[0].kind, MatterEntryKind.nextStep);
      expect(d.timeline[0].removable, isTrue);
      expect(d.timeline[1].kind, MatterEntryKind.tick);
      expect(d.timeline[1].removable, isFalse);
      expect(d.links[0].kind, MatterLinkKind.conversation);
      expect(d.links[0].turns, 4);
      expect(d.links[0].fromEventId, 'ev1');
      expect(d.links[1].kind, MatterLinkKind.pin);
      expect(d.links[1].missing, isTrue);
      expect(d.links[1].label, '');
    });

    test('a detail without timeline or links has empty ones', () {
      final d = MatterDetail.fromMap({'id': 'm1', 'title': 'T'});
      expect(d.timeline, isEmpty);
      expect(d.links, isEmpty);
    });
  });
}
