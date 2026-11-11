import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/pin.dart';
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
      floatingActionButton: FloatingActionButton(
        // Own tag: several tabs keep a "+" mounted at once.
        heroTag: 'pins-new',
        key: const Key('pins-add'),
        tooltip: 'New pin',
        onPressed: () async {
          await context.push('/pins/new');
          notifier.refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: switch (state) {
        PinsListInitial() => const Center(child: CircularProgressIndicator()),
        PinsListLoading() => const Center(child: CircularProgressIndicator()),
        PinsListLoaded(pins: final pins) =>
          _buildList(context, ref, notifier, pins),
        PinsListError(message: final message) =>
          _ErrorState(message: message, onRetry: notifier.refresh),
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    PinsNotifier notifier,
    List<PinSummary> pins,
  ) {
    if (pins.isEmpty) return const _EmptyState();
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        // Room for the "+" button, so it covers no row's menu.
        padding: const EdgeInsets.only(bottom: 88),
        children: [for (final p in pins) _tile(context, ref, notifier, p)],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    PinsNotifier notifier,
    PinSummary pin,
  ) {
    return _PinTile(
      key: Key('pin-tile-${pin.recordId}'),
      pin: pin,
      onTap: () async {
        await context.push('/pins/${pin.recordId}');
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

class _PinTile extends StatelessWidget {
  const _PinTile({
    super.key,
    required this.pin,
    required this.onTap,
    required this.onUnpin,
  });

  final PinSummary pin;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.push_pin_outlined),
      title: Text(pin.pinName),
      subtitle: Text(_formatDate(pin.createdAt)),
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No pins yet. Tap + to write one, or say "zapamiętaj ..." in a chat.',
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
