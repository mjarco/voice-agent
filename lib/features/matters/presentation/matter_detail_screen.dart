import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/core/providers/agent_turns_provider.dart';
import 'package:voice_agent/features/matters/domain/matters_state.dart';
import 'package:voice_agent/features/matters/presentation/matter_detail_notifier.dart';
import 'package:voice_agent/features/matters/presentation/matter_dialogs.dart';
import 'package:voice_agent/features/matters/presentation/matter_tasks_notifier.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';

/// One matter as a place to act from (04 of the discussion
/// 2026-11-va-meals-dashboard): its state in a sentence, its agenda of tasks
/// to tick off, add and remove, its history as a story, its pins, and the
/// conversation field, where what is said or written is about this matter
/// (personal-agent's ADR-API-126). Everything opened from here is pushed, so
/// Back returns to the matter.
class MatterDetailScreen extends ConsumerStatefulWidget {
  const MatterDetailScreen({super.key, required this.matterId, this.field});

  final String matterId;

  /// The conversation field; the app puts it here, as features do not
  /// import each other.
  final Widget? field;

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

  MatterTasksNotifier get _tasks =>
      ref.read(matterTasksNotifierProvider(widget.matterId).notifier);

  DateTime _now() => ref.read(mattersClockProvider)();

  /// The notifier outlives the page (an entry's undo sends its delete after
  /// the page may be gone), so a matter opened again is read again here: the
  /// chat may have changed it meanwhile.
  @override
  void initState() {
    super.initState();
    // Built for the first time, a notifier reads itself; one kept alive (the
    // same matter open under another tab, F1 of V3's device check) is read
    // again.
    final detail = ref.exists(matterDetailNotifierProvider(widget.matterId));
    final tasks = ref.exists(matterTasksNotifierProvider(widget.matterId));
    if (!detail && !tasks) return;
    Future.microtask(() {
      if (!mounted) return;
      if (detail) unawaited(_notifier.refresh());
      if (tasks) unawaited(_tasks.load());
    });
  }

  Future<void> _refresh() => Future.wait([_notifier.refresh(), _tasks.load()]);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matterDetailNotifierProvider(widget.matterId));
    // A turn answered, said here or written in a thread opened from here,
    // may have written into the matter.
    ref.listen<int>(agentTurnsProvider, (_, _) => unawaited(_refresh()));

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
      body: Column(
        children: [
          Expanded(
            child: switch (state) {
              MatterDetailLoading() =>
                const Center(child: CircularProgressIndicator()),
              MatterDetailLoaded(:final detail) => RefreshIndicator(
                  onRefresh: _refresh,
                  child: _body(detail),
                ),
              MatterDetailError(:final message) =>
                _ErrorState(message: message, onRetry: _notifier.refresh),
            },
          ),
          // A proposed matter is not a place to talk from until accepted.
          if (state is MatterDetailLoaded && state.detail.matter.status != MatterStatus.proposed)
            ?widget.field,
        ],
      ),
    );
  }

  Widget _body(MatterDetail detail) {
    final m = detail.matter;
    final proposed = m.status == MatterStatus.proposed;
    final story = _story(detail);
    final pins = [for (final l in detail.links) if (l.kind == MatterLinkKind.pin) l];
    return ListView(
      key: const Key('matter-list'),
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
          title: Text(statusLine(m, _now()), key: const Key('matter-status')),
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
        if (!proposed) ..._agenda(),
        _Header(
          text: 'Historia',
          action: TextButton.icon(
            key: const Key('matter-add-entry'),
            icon: const Icon(Icons.note_add_outlined, size: 18),
            label: const Text('Dodaj wpis'),
            onPressed: _addEntry,
          ),
        ),
        if (story.isEmpty)
          const ListTile(dense: true, title: Text('Nic się jeszcze nie wydarzyło.')),
        for (final s in story) _storyTile(s),
        if (pins.isNotEmpty) ...[
          const _Header(text: 'Pinezki'),
          for (final p in pins) _pinTile(p),
        ],
        _field(
          key: 'keywords',
          title: 'Słowa kluczowe',
          value: m.keywords,
          onSave: _notifier.setKeywords,
        ),
      ],
    );
  }

  // ── The agenda ──────────────────────────────────────────────────────────

  List<Widget> _agenda() {
    final state = ref.watch(matterTasksNotifierProvider(widget.matterId));
    return [
      _Header(
        text: 'Agenda sprawy',
        action: TextButton.icon(
          key: const Key('matter-add-task'),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Dodaj zadanie'),
          onPressed: _addTask,
        ),
      ),
      ...switch (state) {
        MatterTasksLoading() => [const LinearProgressIndicator()],
        MatterTasksError() => [
            ListTile(
              key: const Key('matter-tasks-error'),
              dense: true,
              title: const Text('Nie udało się wczytać zadań'),
              trailing: TextButton(onPressed: _tasks.load, child: const Text('Ponów')),
            ),
          ],
        MatterTasksLoaded(:final tasks) when tasks.isEmpty => [
            const ListTile(
              key: Key('matter-tasks-empty'),
              dense: true,
              title: Text('Brak zadań. Powiedz, co trzeba zrobić, albo dodaj.'),
            ),
          ],
        MatterTasksLoaded(:final tasks) => [for (final t in tasks) _taskTile(t)],
      },
    ];
  }

  Widget _taskTile(MatterTask t) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: Key('matter-task-${t.id}'),
      direction: t.canTick ? DismissDirection.horizontal : DismissDirection.endToStart,
      background: _SwipeBackground(
        color: Colors.green.shade600,
        icon: Icons.check,
        label: 'Zrobione',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _SwipeBackground(
        color: scheme.error,
        icon: Icons.delete_outline,
        label: 'Usuń',
        alignment: Alignment.centerRight,
      ),
      // The row leaves at once; the write and its undo follow.
      onDismissed: (direction) {
        final tasks = _tasks;
        tasks.hide(t.id);
        if (direction == DismissDirection.startToEnd) {
          unawaited(_taskWrite(t, 'Zrobione', () => tasks.done(t), () => tasks.undoDone(t)));
        } else {
          unawaited(_removeTask(t));
        }
      },
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 88,
          child: Text(
            t.overdue ? '! ${t.when}' : t.when,
            style: t.overdue ? TextStyle(color: scheme.error, fontWeight: FontWeight.bold) : null,
          ),
        ),
        title: Text(t.routine.name),
        onTap: () => context.push('/routine/${t.id}'),
      ),
    );
  }

  /// Runs a task's write with an undo in the snackbar.
  Future<void> _taskWrite(
    MatterTask t,
    String done,
    Future<bool> Function() write,
    Future<bool> Function() undo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final tasks = _tasks;
    if (!await write()) {
      if (mounted) showMatterError(context, 'zmienić zadania', tasks.lastActionError);
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      key: const Key('matter-task-snackbar'),
      content: Text('$done: ${t.routine.name}'),
      persist: false,
      action: SnackBarAction(
        key: const Key('matter-task-undo'),
        label: 'Cofnij',
        onPressed: () => unawaited(undo()),
      ),
    ));
  }

  /// Off the agenda with an undo: personal-agent never takes an archived
  /// routine back, so the archive is asked for only when the undo runs out
  /// (device check of V3, F2); Cofnij reads the agenda again.
  Future<void> _removeTask(MatterTask t) async {
    final messenger = ScaffoldMessenger.of(context);
    final tasks = _tasks;
    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(SnackBar(
          key: const Key('matter-task-snackbar'),
          content: Text('Usunięte z agendy: ${t.routine.name}'),
          persist: false,
          action: SnackBarAction(
            key: const Key('matter-task-undo'),
            label: 'Cofnij',
            onPressed: () {},
          ),
        ))
        .closed;
    if (reason == SnackBarClosedReason.action) {
      await tasks.unhide(t.id);
      return;
    }
    if (!await tasks.remove(t) && mounted) {
      showMatterError(context, 'usunąć zadania', tasks.lastActionError);
    }
  }

  Future<void> _addTask() async {
    final task = await askMatterTask(context, _now());
    if (task == null || !mounted) return;
    final tasks = _tasks;
    if (!await tasks.add(task.name, dueOn: task.dueOn) && mounted) {
      showMatterError(context, 'dodać zadania', tasks.lastActionError);
    }
  }

  // ── The history as a story ────────────────────────────────────────────────

  List<_StoryLine> _story(MatterDetail detail) {
    final lines = <_StoryLine>[
      for (final e in detail.timeline)
        if (!_removing.contains(e.id) && !_isConversationBookkeeping(e))
          _StoryLine(at: e.createdAt, day: e.day, text: storyText(e), entry: e),
      for (final l in detail.links)
        if (l.kind == MatterLinkKind.conversation && !l.missing)
          _StoryLine(
            at: l.lastAt ?? l.createdAt,
            day: l.day ?? '',
            text: 'Rozmowa: ${l.label.isEmpty ? '…' : l.label}${l.turns > 0 ? ' (${l.turns})' : ''}',
            conversation: l,
          ),
    ];
    lines.sort((a, b) {
      final ta = a.at, tb = b.at;
      if (ta == null || tb == null) return tb == null ? -1 : 1;
      return tb.compareTo(ta);
    });
    return lines;
  }

  /// A conversation's joining and leaving are told by the conversation's
  /// own line.
  static bool _isConversationBookkeeping(MatterEntry e) =>
      (e.kind == MatterEntryKind.joined || e.kind == MatterEntryKind.left) &&
      e.text.startsWith('conversation');

  Widget _storyTile(_StoryLine s) {
    final theme = Theme.of(context);
    final e = s.entry;
    final c = s.conversation;
    return ListTile(
      key: Key(c != null ? 'matter-story-conversation-${c.targetId}' : 'matter-story-${e?.id ?? s.text.hashCode}'),
      dense: true,
      leading: SizedBox(
        width: 64,
        child: Text(relativeDay(s.at, s.day, _now()), style: theme.textTheme.bodySmall),
      ),
      title: Text(s.text),
      trailing: c != null
          ? const Icon(Icons.chevron_right)
          : e != null && e.removable && e.kind == MatterEntryKind.note
              ? IconButton(
                  key: Key('matter-entry-delete-${e.id}'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Usuń wpis',
                  onPressed: () => _removeEntry(e.id!),
                )
              : null,
      onTap: c == null ? null : () => context.push('/conversation/${c.targetId}'),
      onLongPress: c == null ? null : () => _unlink(c),
    );
  }

  Widget _pinTile(MatterLink l) => ListTile(
        key: Key('matter-pin-${l.id}'),
        dense: true,
        enabled: !l.missing,
        leading: const Icon(Icons.push_pin_outlined),
        title: Text(l.label.isEmpty ? l.targetId : l.label),
        onTap: l.missing ? null : () => context.push('/pins/${l.targetId}'),
        trailing: IconButton(
          key: Key('matter-link-remove-${l.id}'),
          icon: const Icon(Icons.link_off),
          tooltip: 'Odłącz',
          onPressed: () => _unlink(l),
        ),
      );

  Widget _field({
    required String key,
    required String title,
    required String value,
    required Future<bool> Function(String) onSave,
  }) {
    return ListTile(
      key: Key('matter-field-$key'),
      dense: true,
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
        await askMatterText(context,
            title: 'Dodaj wpis',
            multiline: true,
            hint: 'Co się wydarzyło, jednym zdaniem');
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

/// One line of the history: an entry or a conversation, at its time.
class _StoryLine {
  const _StoryLine({required this.at, required this.day, required this.text, this.entry, this.conversation});
  final DateTime? at;
  final String day;
  final String text;
  final MatterEntry? entry;
  final MatterLink? conversation;
}

/// The matter's state as a sentence: "W toku · ostatnio wczoraj". An active
/// matter is "w toku" with an activity in the last 7 days, as on Dziś and
/// the widget.
String statusLine(MatterSummary m, DateTime now) {
  final last = m.lastActivity;
  final recent = last != null && now.difference(last).inDays < 7;
  final status = switch (m.status) {
    MatterStatus.active => recent ? 'W toku' : 'Aktywna',
    MatterStatus.waiting => 'Czeka',
    MatterStatus.paused => 'Wstrzymana',
    MatterStatus.closed => 'Zamknięta',
    MatterStatus.proposed => 'Do przejrzenia',
    MatterStatus.unknown => 'Sprawa',
  };
  final parts = [
    status,
    if (last != null) 'ostatnio ${relativeDay(last, '', now)}',
    if (m.standingStill) 'stoi',
  ];
  return parts.join(' · ');
}

/// A day as the owner says it: dziś, wczoraj, "3 dni temu" within a week,
/// otherwise "12.11". [fallback] is the server's `YYYY-MM-DD` when [at] is
/// unknown.
String relativeDay(DateTime? at, String fallback, DateTime now) {
  DateTime? day = at?.toLocal();
  day ??= DateTime.tryParse(fallback);
  if (day == null) return '';
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final ago = today.difference(d).inDays;
  if (ago <= 0) return 'dziś';
  if (ago == 1) return 'wczoraj';
  if (ago < 7) return '$ago dni temu';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}

/// An entry as a sentence of the story; the server's English markers of a
/// link or a tick are said in Polish.
String storyText(MatterEntry e) {
  String polish(String t) => t
      .replaceFirst(RegExp(r'^routine: '), 'zadanie: ')
      .replaceFirst(RegExp(r'^pin: '), 'pinezka: ');
  return switch (e.kind) {
    MatterEntryKind.note => e.text,
    MatterEntryKind.opened => e.text.isEmpty ? 'Założona' : 'Założona: ${e.text}',
    MatterEntryKind.nextStep => e.text.isEmpty ? 'Bez następnego kroku' : 'Następny krok: ${e.text}',
    MatterEntryKind.waitingFor => e.text.isEmpty ? 'Już na nic nie czeka' : 'Czeka na: ${e.text}',
    MatterEntryKind.status => 'Status: ${MatterStatus.fromJson(e.text) == MatterStatus.unknown ? e.text : MatterStatus.fromJson(e.text).label}',
    MatterEntryKind.joined => 'Dołączone ${polish(e.text)}',
    MatterEntryKind.left => 'Odłączone ${polish(e.text)}',
    MatterEntryKind.tick => e.text
        .replaceFirst(RegExp(r'^done: '), '✓ ')
        .replaceFirst(RegExp(r'^skipped: '), 'pominięte: ')
        .replaceFirst(RegExp(r' \(\d{4}-\d{2}-\d{2}\)$'), ''),
    MatterEntryKind.unknown => e.text,
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary, letterSpacing: 0.8),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
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
