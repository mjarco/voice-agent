import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent/features/usage/domain/usage_summary.dart';
import 'package:voice_agent/features/usage/domain/usage_state.dart';
import 'package:voice_agent/features/usage/presentation/usage_controller.dart';
import 'package:voice_agent/features/usage/presentation/usage_providers.dart';
import 'package:voice_agent/features/usage/presentation/usage_screen.dart';

/// A minimal StateNotifier that holds a fixed UsageState without triggering
/// any network calls.  This avoids the auto-load in UsageController's
/// constructor.
class _FixedStateController extends StateNotifier<UsageState>
    implements UsageController {
  _FixedStateController(super.initial);

  @override
  Future<void> refresh() async {}
}

UsageSummary _sampleSummary({
  String from = '2026-04-01',
  String to = '2026-04-23',
  double costUsd = 12.34,
  double costPln = 49.36,
}) =>
    UsageSummary(
      periodFrom: from,
      periodTo: to,
      totalCostUsd: costUsd,
      totalCostPln: costPln,
      totalInputTokens: 1234567,
      totalOutputTokens: 567890,
      totalRequests: 42,
      daily: [
        const DailyUsage(
          date: '2026-04-01',
          costUsd: 0.56,
          costPln: 2.24,
          requests: 3,
          models: [
            ModelCost(model: 'claude-sonnet-4-20250514', costUsd: 0.40),
            ModelCost(model: 'gpt-4o', costUsd: 0.16),
          ],
        ),
        const DailyUsage(
          date: '2026-04-02',
          costUsd: 1.10,
          costPln: 4.40,
          requests: 5,
          models: [
            ModelCost(model: 'claude-sonnet-4-20250514', costUsd: 1.10),
          ],
        ),
      ],
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required UsageState state,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        usageControllerProvider.overrideWith(
          (_) => _FixedStateController(state),
        ),
      ],
      child: const MaterialApp(home: UsageScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  group('UsageScreen', () {
    testWidgets('shows loading spinner', (tester) async {
      await _pumpScreen(tester, state: const UsageLoading());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await _pumpScreen(
        tester,
        state: const UsageError(message: 'Server error 500: Internal'),
      );

      expect(find.text('Server error 500: Internal'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows cost summary in loaded state', (tester) async {
      await _pumpScreen(
        tester,
        state: UsageLoaded(
          currentMonth: _sampleSummary(),
          previousMonth: _sampleSummary(
            from: '2026-03-01',
            to: '2026-03-31',
            costUsd: 8.00,
            costPln: 32.00,
          ),
        ),
      );

      // Primary PLN cost
      expect(find.text('49.36 PLN'), findsOneWidget);
      // Secondary USD cost
      expect(find.text('\$12.34 USD'), findsOneWidget);
      // Request count
      expect(find.text('42'), findsOneWidget);
      // Section title
      expect(find.text('Current Month'), findsOneWidget);
      // Daily breakdown section
      expect(find.text('Daily Breakdown'), findsOneWidget);
      // Previous month section (collapsed)
      expect(find.textContaining('Previous Month'), findsOneWidget);
    });

    testWidgets('shows app bar with title', (tester) async {
      await _pumpScreen(tester, state: const UsageLoading());

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Usage & Costs'),
        ),
        findsOneWidget,
      );
    });
  });
}
