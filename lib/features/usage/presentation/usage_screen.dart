import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/features/usage/domain/usage_summary.dart';
import 'package:voice_agent/features/usage/domain/usage_state.dart';
import 'package:voice_agent/features/usage/presentation/usage_providers.dart';

class UsageScreen extends ConsumerWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(usageControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Usage & Costs')),
      body: switch (state) {
        UsageLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
        UsageError(message: final message) => _buildError(context, ref, message),
        UsageLoaded(
          currentMonth: final current,
          previousMonth: final previous,
        ) =>
          _buildLoaded(context, ref, current, previous),
      },
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () =>
                ref.read(usageControllerProvider.notifier).refresh(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    WidgetRef ref,
    UsageSummary current,
    UsageSummary? previous,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(usageControllerProvider.notifier).refresh(),
      child: ListView(
        children: [
          _SummaryHeader(summary: current),
          if (current.daily.isNotEmpty) ...[
            _SectionTitle(title: 'Daily Breakdown'),
            _DailyBreakdown(daily: current.daily),
          ],
          if (previous != null)
            _PreviousMonthSection(summary: previous),
        ],
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.summary});
  final UsageSummary summary;

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    }
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Month',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.periodFrom} - ${summary.periodTo}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(
              '${summary.totalCostPln.toStringAsFixed(2)} PLN',
              key: const Key('usage-total-pln'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              '\$${summary.totalCostUsd.toStringAsFixed(2)} USD',
              key: const Key('usage-total-usd'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatChip(
                    label: 'Requests',
                    value: summary.totalRequests.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatChip(
                    label: 'Input tokens',
                    value: _formatTokens(summary.totalInputTokens),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatChip(
                    label: 'Output tokens',
                    value: _formatTokens(summary.totalOutputTokens),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _DailyBreakdown extends StatelessWidget {
  const _DailyBreakdown({required this.daily});
  final List<DailyUsage> daily;

  @override
  Widget build(BuildContext context) {
    final maxCost =
        daily.map((d) => d.costUsd).reduce((a, b) => max(a, b));

    return Column(
      children: daily.map((day) => _DailyRow(day: day, maxCost: maxCost)).toList(),
    );
  }
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.day, required this.maxCost});
  final DailyUsage day;
  final double maxCost;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCost > 0 ? day.costUsd / maxCost : 0.0;

    return ExpansionTile(
      title: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              day.date.substring(5), // MM-DD
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = constraints.maxWidth * fraction;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    key: Key('usage-bar-${day.date}'),
                    height: 16,
                    width: barWidth,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$${day.costUsd.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${day.costPln.toStringAsFixed(2)} PLN | ${day.requests} requests',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              ...day.models.map((m) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      '${m.model}: \$${m.costUsd.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviousMonthSection extends StatelessWidget {
  const _PreviousMonthSection({required this.summary});
  final UsageSummary summary;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('usage-previous-month'),
      title: Text(
        'Previous Month (${summary.periodFrom} - ${summary.periodTo})',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${summary.totalCostPln.toStringAsFixed(2)} PLN',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '\$${summary.totalCostUsd.toStringAsFixed(2)} USD',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${summary.totalRequests} requests | '
                '${summary.totalInputTokens} input tokens | '
                '${summary.totalOutputTokens} output tokens',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
