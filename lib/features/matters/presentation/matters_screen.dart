import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_state.dart';
import 'package:voice_agent/features/matters/presentation/matter_dialogs.dart';
import 'package:voice_agent/features/matters/presentation/matters_notifier.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';

/// The owner's matters (ADR-CORE-118 of personal-agent): the proposed ones to
/// review first, then the rest grouped by status. A tab of the bottom bar,
/// in the place Routines had (ADR-ARCH-012).
class MattersScreen extends ConsumerWidget {
  const MattersScreen({super.key});

  /// The order of the groups below the proposed ones, as the server orders.
  static const _groups = [
    (MatterStatus.active, 'Aktywne'),
    (MatterStatus.waiting, 'Czekają'),
    (MatterStatus.paused, 'Wstrzymane'),
    (MatterStatus.closed, 'Zamknięte'),
    (MatterStatus.unknown, 'Inne'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mattersNotifierProvider);
    final notifier = ref.read(mattersNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Sprawy')),
      floatingActionButton: FloatingActionButton(
        key: const Key('matters-add'),
        tooltip: 'Nowa sprawa',
        onPressed: () async {
          await context.push('/matters/new');
          notifier.refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: switch (state) {
        MattersListLoading() =>
          const Center(child: CircularProgressIndicator()),
        MattersListLoaded(:final proposed, :final matters) =>
          _list(context, notifier, proposed, matters),
        MattersListError(:final message) =>
          _ErrorState(message: message, onRetry: notifier.refresh),
      },
    );
  }

  Widget _list(
    BuildContext context,
    MattersNotifier notifier,
    List<MatterSummary> proposed,
    List<MatterSummary> matters,
  ) {
    Future<void> open(MatterSummary m) async {
      await context.push('/matters/${m.id}');
      // ADR-ARCH-011: what the detail changed shows in the list on return.
      notifier.refresh();
    }

    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Room for the "+" button, so it covers no row.
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          if (proposed.isEmpty && matters.isEmpty) const _EmptyState(),
          if (proposed.isNotEmpty) ...[
            _Header(
              key: const Key('matters-proposed-header'),
              text: 'Do przejrzenia (${proposed.length})',
            ),
            for (final m in proposed)
              _ProposedCard(
                key: Key('matter-proposed-${m.id}'),
                matter: m,
                onTap: () => open(m),
                onAccept: (status) =>
                    _run(context, 'przyjąć', () => notifier.accept(m.id, status),
                        notifier),
                onDrop: () async {
                  if (await confirmDrop(context) != true) return;
                  if (!context.mounted) return;
                  await _run(context, 'odrzucić', () => notifier.drop(m.id),
                      notifier);
                },
              ),
          ],
          for (final (status, label) in _groups)
            if (matters.where((m) => m.status == status).toList()
                case final group when group.isNotEmpty) ...[
              _Header(text: label),
              for (final m in group)
                _MatterTile(
                  key: Key('matter-tile-${m.id}'),
                  matter: m,
                  now: now,
                  onTap: () => open(m),
                ),
            ],
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    String what,
    Future<bool> Function() action,
    MattersNotifier notifier,
  ) async {
    final ok = await action();
    if (ok || !context.mounted) return;
    showMatterError(context, what, notifier.lastActionError);
  }
}

class _Header extends StatelessWidget {
  const _Header({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _ProposedCard extends StatelessWidget {
  const _ProposedCard({
    super.key,
    required this.matter,
    required this.onTap,
    required this.onAccept,
    required this.onDrop,
  });

  final MatterSummary matter;
  final VoidCallback onTap;
  final void Function(MatterStatus status) onAccept;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(matter.title),
            subtitle: matter.lastEntry.isEmpty
                ? null
                : Text(
                    matter.lastEntry,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: onTap,
          ),
          ProposedActions(
            idSuffix: matter.id,
            onAccept: onAccept,
            onDrop: onDrop,
          ),
        ],
      ),
    );
  }
}

class _MatterTile extends StatelessWidget {
  const _MatterTile({
    super.key,
    required this.matter,
    required this.now,
    required this.onTap,
  });

  final MatterSummary matter;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = matter.nextStep.isNotEmpty
        ? 'Następny krok: ${matter.nextStep}'
        : matter.lastEntry;
    return ListTile(
      title: Text(matter.title),
      subtitle: Text(
        [matter.status.label, if (detail.isNotEmpty) detail].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: matter.standingStill
          ? Text(
              standingStillLabel(matter.daysStill(now)),
              key: Key('matter-still-${matter.id}'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// "stoi od N dni", or "stoi" when the server sent no time to count from.
String standingStillLabel(int? days) => switch (days) {
      null => 'stoi',
      1 => 'stoi od 1 dnia',
      final n => 'stoi od $n dni',
    };

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 96, 32, 0),
      child: Text(
        'Nie ma jeszcze spraw. Stuknij +, by otworzyć nową, albo powiedz o '
        'niej w czacie.',
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const Key('matters-retry-button'),
            onPressed: onRetry,
            child: const Text('Spróbuj ponownie'),
          ),
        ],
      ),
    );
  }
}
