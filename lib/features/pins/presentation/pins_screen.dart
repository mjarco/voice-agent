import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/pins/domain/pins_repository.dart';
import 'package:voice_agent/features/pins/domain/pins_state.dart';
import 'package:voice_agent/features/pins/presentation/pins_notifier.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';

/// Browse saved references (pins) from the personal-agent pinboard.
/// Reached from the Chat list screen's app bar (proposal 045).
class PinsScreen extends ConsumerWidget {
  const PinsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pinsNotifierProvider);
    final notifier = ref.read(pinsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Pins')),
      body: Column(
        children: [
          _ViewToggle(
            view: state is PinsListLoaded ? state.view : notifier.view,
            onChanged: notifier.setView,
          ),
          Expanded(
            child: switch (state) {
              PinsListInitial() =>
                const Center(child: CircularProgressIndicator()),
              PinsListLoading() =>
                const Center(child: CircularProgressIndicator()),
              PinsListLoaded(pins: final pins, view: final view) =>
                _buildList(context, ref, notifier, pins, view),
              PinsListError(message: final message) =>
                _ErrorState(message: message, onRetry: notifier.refresh),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    PinsNotifier notifier,
    List<PinSummary> pins,
    PinView view,
  ) {
    if (pins.isEmpty) return const _EmptyState();
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        children: view == PinView.topic
            ? _topicGrouped(context, ref, notifier, pins)
            : [
                for (final p in pins)
                  _tile(context, ref, notifier, p, showTopic: true),
              ],
      ),
    );
  }

  /// Preserve the backend's topic ordering, inserting a header on each label
  /// change. Pins with no topic label are collected into a single trailing
  /// "No topic" section so they are never dropped.
  List<Widget> _topicGrouped(
    BuildContext context,
    WidgetRef ref,
    PinsNotifier notifier,
    List<PinSummary> pins,
  ) {
    final byLabel = <String, List<PinSummary>>{};
    final order = <String>[];
    final untitled = <PinSummary>[];
    for (final p in pins) {
      final label = p.topicLabel;
      if (label == null || label.isEmpty) {
        untitled.add(p);
      } else {
        if (!byLabel.containsKey(label)) {
          byLabel[label] = [];
          order.add(label);
        }
        byLabel[label]!.add(p);
      }
    }

    // In the by-topic view the section header already names the topic, so the
    // tile subtitle omits it to avoid duplication.
    final widgets = <Widget>[];
    for (final label in order) {
      widgets.add(_SectionHeader(label: label));
      widgets.addAll(
        byLabel[label]!
            .map((p) => _tile(context, ref, notifier, p, showTopic: false)),
      );
    }
    if (untitled.isNotEmpty) {
      widgets.add(const _SectionHeader(label: 'No topic'));
      widgets.addAll(
        untitled.map((p) => _tile(context, ref, notifier, p, showTopic: false)),
      );
    }
    return widgets;
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    PinsNotifier notifier,
    PinSummary pin, {
    required bool showTopic,
  }) {
    return _PinTile(
      key: Key('pin-tile-${pin.recordId}'),
      pin: pin,
      showTopic: showTopic,
      onTap: () async {
        await context.push('/chat/pins/${pin.recordId}');
        // ADR-ARCH-011: refresh on return so an unpin done from the detail
        // screen is reflected in the list.
        notifier.refresh();
      },
      onUnpin: () => _confirmUnpin(context, ref, pin.recordId),
    );
  }

  Future<void> _confirmUnpin(
    BuildContext context,
    WidgetRef ref,
    String recordId,
  ) async {
    final confirmed = await _showUnpinDialog(context);
    if (confirmed != true) return;
    final notifier = ref.read(pinsNotifierProvider.notifier);
    final ok = await notifier.unpin(recordId);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notifier.lastActionError ?? 'Unpin failed')),
      );
    }
  }
}

Future<bool?> _showUnpinDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('pin-unpin-dialog'),
      title: const Text('Unpin reference?'),
      content: const Text('This removes it from your pins.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('pin-unpin-confirm'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Unpin'),
        ),
      ],
    ),
  );
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final PinView view;
  final ValueChanged<PinView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SegmentedButton<PinView>(
        segments: const [
          ButtonSegment(
            value: PinView.recent,
            label: Text('Recent'),
            icon: Icon(Icons.schedule),
          ),
          ButtonSegment(
            value: PinView.topic,
            label: Text('By topic'),
            icon: Icon(Icons.folder_outlined),
          ),
        ],
        selected: {view},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _PinTile extends StatelessWidget {
  const _PinTile({
    super.key,
    required this.pin,
    required this.showTopic,
    required this.onTap,
    required this.onUnpin,
  });

  final PinSummary pin;
  final bool showTopic;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.push_pin_outlined),
      title: Text(pin.pinName),
      subtitle: Text(_subtitle()),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        key: Key('pin-menu-${pin.recordId}'),
        onSelected: (value) {
          if (value == 'unpin') onUnpin();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'unpin', child: Text('Unpin')),
        ],
      ),
    );
  }

  String _subtitle() {
    final label = pin.topicLabel;
    final date = _formatDate(pin.createdAt);
    if (showTopic && label != null && label.isNotEmpty) {
      return '$label · $date';
    }
    return date;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No pins yet. Say "zapamiętaj ..." in a chat to save a reference.',
          textAlign: TextAlign.center,
        ),
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
            key: const Key('pins-retry-button'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
