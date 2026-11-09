import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_state.dart';
import 'package:voice_agent/features/matters/presentation/matter_detail_notifier.dart';
import 'package:voice_agent/features/matters/presentation/matter_dialogs.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';

/// One matter: its state (status, next step, what it waits for, keywords),
/// the timeline and what is joined to it. A proposed matter shows the
/// owner's accept / drop buttons on top.
class MatterDetailScreen extends ConsumerStatefulWidget {
  const MatterDetailScreen({super.key, required this.matterId});

  final String matterId;

  @override
  ConsumerState<MatterDetailScreen> createState() =>
      _MatterDetailScreenState();
}

class _MatterDetailScreenState extends ConsumerState<MatterDetailScreen> {
  /// Entries removed on screen whose undo has not run out yet; the server is
  /// asked only when it does.
  final Set<String> _removing = {};

  MatterDetailNotifier get _notifier =>
      ref.read(matterDetailNotifierProvider(widget.matterId).notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matterDetailNotifierProvider(widget.matterId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state is MatterDetailLoaded ? state.detail.matter.title : 'Sprawa',
        ),
        actions: [
          if (state is MatterDetailLoaded &&
              state.detail.matter.status != MatterStatus.proposed)
            IconButton(
              key: const Key('matter-delete'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Usuń sprawę',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: switch (state) {
        MatterDetailLoading() =>
          const Center(child: CircularProgressIndicator()),
        MatterDetailLoaded(:final detail) => RefreshIndicator(
            onRefresh: _notifier.refresh,
            child: _body(detail),
          ),
        MatterDetailError(:final message) =>
          _ErrorState(message: message, onRetry: _notifier.refresh),
      },
    );
  }

  Widget _body(MatterDetail detail) {
    final m = detail.matter;
    final proposed = m.status == MatterStatus.proposed;
    final timeline =
        detail.timeline.where((e) => !_removing.contains(e.id)).toList();
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (proposed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ProposedActions(
              idSuffix: m.id,
              onAccept: _accept,
              onDrop: _drop,
            ),
          ),
        ListTile(
          title: const Text('Status'),
          subtitle: Text(m.status.label, key: const Key('matter-status')),
          trailing: proposed
              ? null
              : PopupMenuButton<MatterStatus>(
                  key: const Key('matter-status-menu'),
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'Zmień status',
                  onSelected: (s) => _write(
                    'zmienić statusu',
                    () => _notifier.setStatus(s),
                  ),
                  itemBuilder: (_) => [
                    for (final s in const [
                      MatterStatus.active,
                      MatterStatus.waiting,
                      MatterStatus.paused,
                      MatterStatus.closed,
                    ])
                      PopupMenuItem(
                        key: Key('matter-status-${s.name}'),
                        value: s,
                        enabled: s != m.status,
                        child: Text(s.label),
                      ),
                  ],
                ),
        ),
        _field(
          key: 'next-step',
          title: 'Następny krok',
          value: m.nextStep,
          onSave: _notifier.setNextStep,
        ),
        _field(
          key: 'waiting-for',
          title: 'Czeka na',
          value: m.waitingFor,
          onSave: _notifier.setWaitingFor,
        ),
        _field(
          key: 'keywords',
          title: 'Słowa kluczowe',
          value: m.keywords,
          onSave: _notifier.setKeywords,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('matter-add-entry'),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Dodaj wpis'),
              onPressed: _addEntry,
            ),
          ),
        ),
        _Header(text: 'Historia (${timeline.length})'),
        for (final (i, e) in timeline.indexed)
          ListTile(
            key: Key('matter-entry-${e.id ?? 'tick-$i'}'),
            dense: true,
            leading: Text(e.day, style: theme.textTheme.bodySmall),
            title: Text(e.text),
            subtitle: e.kind.label.isEmpty ? null : Text(e.kind.label),
            trailing: e.removable
                ? IconButton(
                    key: Key('matter-entry-delete-${e.id}'),
                    icon: const Icon(Icons.close),
                    tooltip: 'Usuń wpis',
                    onPressed: () => _removeEntry(e.id!),
                  )
                : null,
          ),
        if (detail.links.isNotEmpty) ...[
          _Header(text: 'Powiązania (${detail.links.length})'),
          for (final l in detail.links) _linkTile(l),
        ],
      ],
    );
  }

  Widget _field({
    required String key,
    required String title,
    required String value,
    required Future<bool> Function(String) onSave,
  }) {
    return ListTile(
      key: Key('matter-field-$key'),
      title: Text(title),
      subtitle: Text(value.isEmpty ? '—' : value),
      trailing: IconButton(
        key: Key('matter-edit-$key'),
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Zmień',
        onPressed: () async {
          final text =
              await askMatterText(context, title: title, initial: value);
          if (text == null || text == value) return;
          await _write('zapisać', () => onSave(text));
        },
      ),
    );
  }

  Widget _linkTile(MatterLink l) {
    final conversation = l.kind == MatterLinkKind.conversation;
    final details = [
      ?l.day,
      if (l.turns > 0) '${l.turns} wypowiedzi',
      if (l.missing) 'usunięte',
    ];
    return ListTile(
      key: Key('matter-link-${l.id}'),
      enabled: !l.missing,
      leading: Icon(switch (l.kind) {
        MatterLinkKind.conversation => Icons.forum_outlined,
        MatterLinkKind.routine => Icons.repeat,
        MatterLinkKind.pin => Icons.push_pin_outlined,
        MatterLinkKind.unknown => Icons.link,
      }),
      title: Text(l.label.isEmpty ? l.targetId : l.label),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      // The same standalone thread route a pin's "Open conversation" uses.
      onTap: conversation && !l.missing
          ? () => context.push('/conversation/${l.targetId}')
          : null,
      trailing: IconButton(
        key: Key('matter-link-remove-${l.id}'),
        icon: const Icon(Icons.link_off),
        tooltip: 'Odłącz',
        onPressed: () => _unlink(l),
      ),
    );
  }

  Future<void> _write(String what, Future<bool> Function() action) async {
    final notifier = _notifier;
    final ok = await action();
    if (ok || !mounted) return;
    showMatterError(context, what, notifier.lastActionError);
  }

  Future<void> _accept(MatterStatus status) =>
      _write('przyjąć', () => _notifier.accept(status));

  Future<void> _drop() async {
    if (await confirmDrop(context) != true || !mounted) return;
    final notifier = _notifier;
    final ok = await notifier.drop();
    if (!mounted) return;
    if (ok) {
      context.pop();
    } else {
      showMatterError(context, 'odrzucić', notifier.lastActionError);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await confirmMatterAction(
      context,
      key: const Key('matter-delete-dialog'),
      title: 'Usunąć sprawę?',
      content: 'Sprawa zniknie z jej historią i powiązaniami; rozmowy, '
          'rutyny i piny zostaną.',
      action: 'Usuń',
    );
    if (confirmed != true || !mounted) return;
    final notifier = _notifier;
    final ok = await notifier.delete();
    if (!mounted) return;
    if (ok) {
      context.pop();
    } else {
      showMatterError(context, 'usunąć sprawy', notifier.lastActionError);
    }
  }

  Future<void> _addEntry() async {
    final text =
        await askMatterText(context, title: 'Dodaj wpis', multiline: true);
    if (text == null || text.isEmpty || !mounted) return;
    await _write('dodać wpisu', () => _notifier.addEntry(text));
  }

  /// Hides the entry at once with an undo; the server removes it only when
  /// the undo runs out.
  Future<void> _removeEntry(String entryId) async {
    final notifier = _notifier;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removing.add(entryId));
    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(
          SnackBar(
            key: const Key('matter-entry-undo-snackbar'),
            content: const Text('Usunięto wpis'),
            // A snackbar with an action stays until dismissed unless told
            // otherwise; the undo must run out by itself.
            persist: false,
            action: SnackBarAction(
              key: const Key('matter-entry-undo'),
              label: 'Cofnij',
              onPressed: () {},
            ),
          ),
        )
        .closed;
    if (reason == SnackBarClosedReason.action) {
      if (mounted) setState(() => _removing.remove(entryId));
      return;
    }
    final ok = await notifier.deleteEntry(entryId);
    if (mounted) setState(() => _removing.remove(entryId));
    if (!ok && mounted) {
      showMatterError(context, 'usunąć wpisu', notifier.lastActionError);
    }
  }

  Future<void> _unlink(MatterLink l) async {
    final confirmed = await confirmMatterAction(
      context,
      key: const Key('matter-unlink-dialog'),
      title: 'Odłączyć od sprawy?',
      content: '„${l.label.isEmpty ? l.targetId : l.label}” przestanie '
          'należeć do tej sprawy; samo zostaje.',
      action: 'Odłącz',
    );
    if (confirmed != true || !mounted) return;
    await _write('odłączyć', () => _notifier.unlink(l.id));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.text});

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
            key: const Key('matter-detail-retry-button'),
            onPressed: onRetry,
            child: const Text('Spróbuj ponownie'),
          ),
        ],
      ),
    );
  }
}
