import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/usage/domain/usage_summary.dart';

Map<String, dynamic> _sampleSummaryMap() => {
      'period': {'from': '2026-04-01', 'to': '2026-04-23'},
      'total_cost_usd': 12.34,
      'total_cost_pln': 49.36,
      'total_input_tokens': 1234567,
      'total_output_tokens': 567890,
      'total_requests': 42,
      'daily': [
        {
          'date': '2026-04-01',
          'cost_usd': 0.56,
          'cost_pln': 2.24,
          'requests': 3,
          'models': {
            'claude-sonnet-4-20250514': {'cost_usd': 0.40},
            'gpt-4o': {'cost_usd': 0.16},
          },
        },
        {
          'date': '2026-04-02',
          'cost_usd': 1.10,
          'cost_pln': 4.40,
          'requests': 5,
          'models': {
            'claude-sonnet-4-20250514': {'cost_usd': 1.10},
          },
        },
      ],
    };

void main() {
  group('ModelCost', () {
    test('fromMap creates instance', () {
      final cost = ModelCost.fromMap({
        'model': 'gpt-4o',
        'cost_usd': 0.16,
      });

      expect(cost.model, 'gpt-4o');
      expect(cost.costUsd, 0.16);
    });

    test('toMap round-trips', () {
      final original = ModelCost.fromMap({
        'model': 'claude-sonnet-4-20250514',
        'cost_usd': 0.40,
      });
      final restored = ModelCost.fromMap(original.toMap());

      expect(restored.model, original.model);
      expect(restored.costUsd, original.costUsd);
    });
  });

  group('DailyUsage', () {
    test('fromMap creates instance with model breakdown', () {
      final daily = DailyUsage.fromMap({
        'date': '2026-04-01',
        'cost_usd': 0.56,
        'cost_pln': 2.24,
        'requests': 3,
        'models': {
          'claude-sonnet-4-20250514': {'cost_usd': 0.40},
          'gpt-4o': {'cost_usd': 0.16},
        },
      });

      expect(daily.date, '2026-04-01');
      expect(daily.costUsd, 0.56);
      expect(daily.costPln, 2.24);
      expect(daily.requests, 3);
      expect(daily.models, hasLength(2));
      expect(daily.models[0].model, 'claude-sonnet-4-20250514');
      expect(daily.models[0].costUsd, 0.40);
      expect(daily.models[1].model, 'gpt-4o');
      expect(daily.models[1].costUsd, 0.16);
    });

    test('fromMap handles missing models map', () {
      final daily = DailyUsage.fromMap({
        'date': '2026-04-01',
        'cost_usd': 0.00,
        'cost_pln': 0.00,
        'requests': 0,
      });

      expect(daily.models, isEmpty);
    });

    test('toMap round-trips', () {
      final original = DailyUsage.fromMap({
        'date': '2026-04-01',
        'cost_usd': 0.56,
        'cost_pln': 2.24,
        'requests': 3,
        'models': {
          'claude-sonnet-4-20250514': {'cost_usd': 0.40},
        },
      });
      final restored = DailyUsage.fromMap(original.toMap());

      expect(restored.date, original.date);
      expect(restored.costUsd, original.costUsd);
      expect(restored.costPln, original.costPln);
      expect(restored.requests, original.requests);
      expect(restored.models, hasLength(1));
      expect(restored.models[0].model, original.models[0].model);
      expect(restored.models[0].costUsd, original.models[0].costUsd);
    });
  });

  group('UsageSummary', () {
    test('fromMap creates full instance', () {
      final summary = UsageSummary.fromMap(_sampleSummaryMap());

      expect(summary.periodFrom, '2026-04-01');
      expect(summary.periodTo, '2026-04-23');
      expect(summary.totalCostUsd, 12.34);
      expect(summary.totalCostPln, 49.36);
      expect(summary.totalInputTokens, 1234567);
      expect(summary.totalOutputTokens, 567890);
      expect(summary.totalRequests, 42);
      expect(summary.daily, hasLength(2));
      expect(summary.daily[0].date, '2026-04-01');
      expect(summary.daily[1].date, '2026-04-02');
    });

    test('toMap round-trips', () {
      final original = UsageSummary.fromMap(_sampleSummaryMap());
      final restored = UsageSummary.fromMap(original.toMap());

      expect(restored.periodFrom, original.periodFrom);
      expect(restored.periodTo, original.periodTo);
      expect(restored.totalCostUsd, original.totalCostUsd);
      expect(restored.totalCostPln, original.totalCostPln);
      expect(restored.totalInputTokens, original.totalInputTokens);
      expect(restored.totalOutputTokens, original.totalOutputTokens);
      expect(restored.totalRequests, original.totalRequests);
      expect(restored.daily, hasLength(original.daily.length));
    });

    test('fromMap with empty daily list', () {
      final summary = UsageSummary.fromMap({
        'period': {'from': '2026-04-01', 'to': '2026-04-30'},
        'total_cost_usd': 0.0,
        'total_cost_pln': 0.0,
        'total_input_tokens': 0,
        'total_output_tokens': 0,
        'total_requests': 0,
        'daily': [],
      });

      expect(summary.daily, isEmpty);
      expect(summary.totalRequests, 0);
    });
  });
}
