import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:voice_agent/core/notifications/domain/notification_service.dart';
import 'package:voice_agent/core/notifications/notification_providers.dart';

/// Debug screen exposing the in-memory snapshot of currently scheduled OS
/// notifications. Read-only listing of (id, title, body, fireAt) plus a
/// "fire in 2 s" action that cancels and re-schedules the entry with a
/// near-instant fire time — useful for verifying tap → deep-link paths
/// (T3, T4 in the P040 manual test plan) without waiting for the next
/// 09/12/15/19 summary.
///
/// Mounted only under `kDebugMode`. Guarded at route-definition time in
/// `app/router.dart` so the screen is unreachable on release builds.
class NotificationsDebugScreen extends ConsumerStatefulWidget {
  const NotificationsDebugScreen({super.key});

  @override
  ConsumerState<NotificationsDebugScreen> createState() =>
      _NotificationsDebugScreenState();
}

class _NotificationsDebugScreenState
    extends ConsumerState<NotificationsDebugScreen> {
  Map<int, ScheduledNotification> _snapshot = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(notificationServiceProvider);
      final snap = await service.currentlyScheduled();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Cancels the existing schedule for [n.id] and re-schedules with
  /// `fireAt = now + 2 s`. The diff-based reconciler in production reads
  /// the in-memory snapshot, so after this action the snapshot reflects
  /// the new fireAt and the OS fires within ~2 s.
  ///
  /// Bypasses `AgendaNotificationScheduler` — direct service write
  /// outside the reconciler is allowed here because this is debug-only
  /// tooling, not production scheduling.
  Future<void> _fireIn2s(ScheduledNotification n) async {
    final service = ref.read(notificationServiceProvider);
    final fireAt = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 2));
    await service.cancel(n.id);
    await service.schedule(ScheduledNotification(
      id: n.id,
      title: n.title,
      body: n.body,
      fireAt: fireAt,
      payload: n.payload,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rescheduled id=${n.id} for $fireAt')),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications (debug)'),
        actions: [
          IconButton(
            key: const Key('debug-notifications-refresh'),
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-read in-memory snapshot',
            onPressed: _reload,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    if (_snapshot.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No notifications scheduled.\n\n'
            'Open the Agenda tab to trigger a reconcile, then return here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final entries = _snapshot.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final n = entries[i].value;
        return ListTile(
          dense: true,
          title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'id=${n.id}  •  ${_describeFire(n.fireAt)}\n'
            'body: ${n.body}\n'
            'payload: ${n.payload}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: TextButton(
            key: Key('debug-fire-now-${n.id}'),
            onPressed: () => _fireIn2s(n),
            child: const Text('Fire in 2s'),
          ),
        );
      },
    );
  }

  String _describeFire(tz.TZDateTime fireAt) {
    final now = tz.TZDateTime.now(tz.local);
    final diff = fireAt.difference(now);
    final humanDiff = diff.isNegative
        ? '${(-diff).inMinutes}m ago'
        : diff.inHours >= 1
            ? '${diff.inHours}h${(diff.inMinutes % 60).toString().padLeft(2, '0')}'
            : '${diff.inMinutes}m${(diff.inSeconds % 60).toString().padLeft(2, '0')}s';
    return 'fires in $humanDiff  (${fireAt.toLocal()})';
  }
}

/// Sentinel guard: ensures the screen is only ever built under [kDebugMode].
/// Route definitions reference this so a release build can never reach the
/// screen even if the route somehow stays registered.
bool get debugNotificationsScreenEnabled => kDebugMode;
