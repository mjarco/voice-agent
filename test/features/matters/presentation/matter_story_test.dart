import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/presentation/matter_detail_screen.dart';

void main() {
  final now = DateTime(2026, 11, 15, 12);

  group('statusLine', () {
    test('an active matter with recent activity is "W toku"', () {
      final m = MatterSummary(id: 'm', title: 't', status: MatterStatus.active, lastActivity: DateTime(2026, 11, 14, 9));
      expect(statusLine(m, now), 'W toku · ostatnio wczoraj');
    });

    test('an active matter idle for a week is "Aktywna", and says it stands still', () {
      final m = MatterSummary(id: 'm', title: 't', status: MatterStatus.active, lastActivity: DateTime(2026, 11, 1), standingStill: true);
      expect(statusLine(m, now), 'Aktywna · ostatnio 01.11 · stoi');
    });

    test('a waiting matter', () {
      expect(statusLine(const MatterSummary(id: 'm', title: 't', status: MatterStatus.waiting), now), 'Czeka');
    });
  });

  test('relativeDay', () {
    expect(relativeDay(DateTime(2026, 11, 15, 8), '', now), 'dziś');
    expect(relativeDay(DateTime(2026, 11, 12), '', now), '3 dni temu');
    expect(relativeDay(null, '2026-11-02', now), '02.11');
    expect(relativeDay(null, '', now), '');
  });

  test('storyText says the server\'s markers in Polish', () {
    MatterEntry e(MatterEntryKind k, String t) => MatterEntry(kind: k, text: t);
    expect(storyText(e(MatterEntryKind.tick, 'done: Zmierzyć łazienkę (2026-11-12)')), '✓ Zmierzyć łazienkę');
    expect(storyText(e(MatterEntryKind.waitingFor, 'wycena od Kasi')), 'Czeka na: wycena od Kasi');
    expect(storyText(e(MatterEntryKind.waitingFor, '')), 'Już na nic nie czeka');
    expect(storyText(e(MatterEntryKind.nextStep, 'wybrać płytki')), 'Następny krok: wybrać płytki');
    expect(storyText(e(MatterEntryKind.joined, 'routine: Odebrać płytki')), 'Dołączone zadanie: Odebrać płytki');
    expect(storyText(e(MatterEntryKind.status, 'waiting')), 'Status: czeka');
  });
}
