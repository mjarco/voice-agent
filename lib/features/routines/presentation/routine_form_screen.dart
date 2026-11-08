import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/routines/domain/routine_form_state.dart';
import 'package:voice_agent/features/routines/domain/routine_schedule.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/presentation/routines_providers.dart';

/// Creates a routine ([editId] null) or edits one (#365): the same form as
/// the web UI's. A routine is recurring, once (a day with a window) or some
/// day (ADR-CORE-116 of personal-agent); for a recurring one the client
/// builds the RRULE from the four schedules. Saving pops with the routine
/// the server wrote.
class RoutineFormScreen extends ConsumerStatefulWidget {
  const RoutineFormScreen({super.key, this.editId});
  final String? editId;

  @override
  ConsumerState<RoutineFormScreen> createState() => _RoutineFormScreenState();
}

class _RoutineFormScreenState extends ConsumerState<RoutineFormScreen> {
  final _name = TextEditingController();
  final _interval = TextEditingController(text: '2');
  final _monthday = TextEditingController();
  final List<TextEditingController> _steps = [];

  bool _filled = false;
  RoutineKind _type = RoutineKind.recurring;
  String? _unknownRRule;
  RoutineScheduleKind? _kind = RoutineScheduleKind.daily;
  final Set<String> _days = {};
  DateTime? _dueOn;
  TimeWindow _dueWindow = TimeWindow.day;
  TimeOfDay? _time;
  DateTime? _lastDay;
  RoutineMissed _missed = RoutineMissed.lapses;
  bool _missedTouched = false;
  String? _validation;

  /// The field the form's own check is about; a server refusal names its
  /// field in the state (#367). Marked until the field changes or the next
  /// Save.
  RoutineFormField? _invalid;

  bool get _isEdit => widget.editId != null;

  DateTime get _today {
    final now = ref.read(routinesClockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    if (!_isEdit) {
      _steps.add(TextEditingController());
      _filled = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _interval.dispose();
    _monthday.dispose();
    for (final c in _steps) {
      c.dispose();
    }
    super.dispose();
  }

  /// Prefills the form once from the edited routine.
  void _fill(Routine r) {
    _filled = true;
    _name.text = r.name;
    _type = r.kind;
    _dueOn = parseRoutineDay(r.dueOn);
    _dueWindow = r.dueWindow ?? TimeWindow.day;
    final schedule = RoutineSchedule.parse(r.rrule);
    if (!r.isRecurring) {
      // Kept for a switch to recurring.
      _kind = RoutineScheduleKind.daily;
    } else if (schedule == null) {
      _kind = null;
      _unknownRRule = r.rrule;
    } else {
      _kind = schedule.kind;
      _days
        ..clear()
        ..addAll(schedule.days);
      if (schedule.kind == RoutineScheduleKind.weeks) {
        _interval.text = '${schedule.interval}';
      }
      if (schedule.monthday != null) _monthday.text = '${schedule.monthday}';
    }
    _time = _parseTime(r.startTime);
    // A last day already past (an ended routine) is not offered again: an
    // edit cannot end it before today.
    final last = r.isRecurring ? parseRoutineDay(r.lastDay) : null;
    _lastDay = last != null && !last.isBefore(_today) ? last : null;
    if (r.isRecurring) {
      _missed = r.missed;
      _missedTouched = true;
    }
    final templates = [...r.steps]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final c in _steps) {
      c.dispose();
    }
    _steps
      ..clear()
      ..addAll(templates.map((t) => TextEditingController(text: t.text)));
    if (_steps.isEmpty) _steps.add(TextEditingController());
  }

  static TimeOfDay? _parseTime(String? hhmm) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hhmm ?? '');
    if (m == null) return null;
    return TimeOfDay(hour: int.parse(m[1]!), minute: int.parse(m[2]!));
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _setKind(RoutineScheduleKind? kind) {
    setState(() {
      _kind = kind;
      _touched(RoutineFormField.schedule);
      _touched(RoutineFormField.days);
      _touched(RoutineFormField.interval);
      _touched(RoutineFormField.monthday);
      // A monthly routine waits, any other lapses (ADR-CORE-092), until the
      // owner chooses.
      if (!_missedTouched && kind != null) {
        _missed = kind == RoutineScheduleKind.monthly
            ? RoutineMissed.waits
            : RoutineMissed.lapses;
      }
    });
  }

  /// [field] changed: its mark goes.
  void _touched(RoutineFormField field) {
    if (_invalid == field) _invalid = null;
    final notifier =
        ref.read(routineFormNotifierProvider(widget.editId).notifier);
    if (ref.read(routineFormNotifierProvider(widget.editId)).errorField ==
        field) {
      notifier.clearErrorField();
    }
  }

  /// A failed check of the form: [field] is marked, [message] shown.
  (RoutineInput?, String?) _refuse(RoutineFormField field, String message) {
    _invalid = field;
    return (null, message);
  }

  /// The form as a [RoutineInput], or a message naming what to fix.
  (RoutineInput?, String?) _input() {
    _invalid = null;
    final name = _name.text.trim();
    if (name.isEmpty) {
      return _refuse(RoutineFormField.name, 'Give the routine a name.');
    }
    final startTime = _time == null ? null : _formatTime(_time!);
    final steps = _steps
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    switch (_type) {
      case RoutineKind.oneOff:
        final due = _dueOn;
        if (due == null) {
          return _refuse(RoutineFormField.dueOn, 'Choose the day.');
        }
        return (
          RoutineInput(
            name: name,
            term: OneOffTerm(formatRoutineDay(due), _dueWindow),
            startTime: startTime,
            steps: steps,
          ),
          null
        );
      case RoutineKind.someday:
        return (
          RoutineInput(
            name: name,
            term: const SomedayTerm(),
            startTime: startTime,
            steps: steps,
          ),
          null
        );
      case RoutineKind.recurring:
        break;
    }
    final kind = _kind;
    if (kind == null) {
      return _refuse(RoutineFormField.schedule, 'Choose a schedule.');
    }
    final days = routineWeekdays.where(_days.contains).toList();
    RoutineSchedule schedule;
    switch (kind) {
      case RoutineScheduleKind.daily:
        schedule = const RoutineSchedule.daily();
      case RoutineScheduleKind.weekdays:
        if (days.isEmpty) {
          return _refuse(
              RoutineFormField.days, 'Choose at least one day of the week.');
        }
        schedule = RoutineSchedule.weekdays(days);
      case RoutineScheduleKind.weeks:
        if (days.isEmpty) {
          return _refuse(
              RoutineFormField.days, 'Choose at least one day of the week.');
        }
        final n = int.tryParse(_interval.text.trim());
        if (n == null || n < 2) {
          return _refuse(RoutineFormField.interval,
              'Every N weeks needs N of 2 or more.');
        }
        schedule = RoutineSchedule.weeks(days, n);
      case RoutineScheduleKind.monthly:
        final d = int.tryParse(_monthday.text.trim());
        if (d == null || d < 1 || d > 31) {
          return _refuse(RoutineFormField.monthday,
              'Choose a day of the month from 1 to 31.');
        }
        schedule = RoutineSchedule.monthly(d);
    }
    // A new rule counts from today.
    final from = _today;
    final last = _lastDay;
    if (last != null && last.isBefore(from)) {
      return _refuse(RoutineFormField.lastDay,
          'The last day cannot be before today.');
    }
    if (last != null && !schedule.occursBetween(from, last)) {
      return _refuse(
          RoutineFormField.lastDay,
          'No day of this schedule falls between ${formatRoutineDay(from)} '
          'and the last day. Move the last day or clear it.');
    }
    return (
      RoutineInput(
        name: name,
        term: RecurringTerm(schedule.toRRule()),
        startTime: startTime,
        lastDay: _lastDay == null ? null : formatRoutineDay(_lastDay!),
        missed: _missed,
        steps: steps,
      ),
      null
    );
  }

  Future<void> _save() async {
    final (input, problem) = _input();
    setState(() => _validation = problem);
    if (input == null) return;
    await ref
        .read(routineFormNotifierProvider(widget.editId).notifier)
        .save(input);
  }

  Future<void> _askOverdue(String day) async {
    final notifier =
        ref.read(routineFormNotifierProvider(widget.editId).notifier);
    // Resolving the earliest owed day brings up the next, if any.
    final open = 'The occurrence of $day is still open.';
    final status = await showDialog<OccurrenceStatus>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('An occurrence is still open'),
        content: Text(
          '$open Tick it off or skip it, and the edit is saved again.',
          key: const Key('routine-form-overdue-text'),
        ),
        actions: [
          TextButton(
            key: const Key('routine-form-overdue-cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('routine-form-overdue-skip'),
            onPressed: () => Navigator.of(ctx).pop(OccurrenceStatus.skipped),
            child: const Text('Skip'),
          ),
          FilledButton(
            key: const Key('routine-form-overdue-done'),
            onPressed: () => Navigator.of(ctx).pop(OccurrenceStatus.done),
            child: const Text('Tick off'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (status == null) {
      notifier.dismissOverdue();
    } else {
      await notifier.resolveOverdue(status);
    }
  }

  /// A one-off's day: from today, or from its day already past on an edit.
  Future<void> _pickDueOn() async {
    final due = _dueOn;
    final first = due != null && due.isBefore(_today) ? due : _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: due ?? _today,
      firstDate: first,
      lastDate: _today.add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _dueOn = picked;
        _touched(RoutineFormField.dueOn);
      });
    }
  }

  Future<void> _pickLastDay() async {
    final first = _today;
    final initial =
        _lastDay != null && !_lastDay!.isBefore(first) ? _lastDay! : first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: _today.add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _lastDay = picked;
        _touched(RoutineFormField.lastDay);
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final provider = routineFormNotifierProvider(widget.editId);
    final state = ref.watch(provider);

    ref.listen<RoutineFormState>(provider, (prev, next) {
      if (next.saved != null && prev?.saved == null) {
        context.pop(next.saved);
      } else if (next.overdueDay != null &&
          next.overdueDay != prev?.overdueDay) {
        _askOverdue(next.overdueDay!);
      }
    });

    if (!_filled && state.routine != null) _fill(state.routine!);

    final error = _validation ?? state.error;
    final canSave = _filled && !state.saving && !state.loading;
    final marked = _invalid ?? state.errorField;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit routine' : 'New routine'),
        actions: [
          if (state.saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              key: const Key('routine-form-save'),
              onPressed: canSave ? _save : null,
              child: const Text('Save'),
            ),
        ],
      ),
      body: !_filled
          ? _buildLoading(state)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error != null) ...[
                  Text(
                    error,
                    key: const Key('routine-form-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const Key('routine-form-name'),
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  // The server caps a name at 120 characters (#369).
                  inputFormatters: [LengthLimitingTextInputFormatter(120)],
                  onChanged: (_) =>
                      setState(() => _touched(RoutineFormField.name)),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    border: const OutlineInputBorder(),
                    error: _mark(marked == RoutineFormField.name),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<RoutineKind>(
                  key: const Key('routine-form-type'),
                  segments: const [
                    ButtonSegment(
                        value: RoutineKind.recurring,
                        label: Text('Recurring')),
                    ButtonSegment(
                        value: RoutineKind.oneOff, label: Text('Once')),
                    ButtonSegment(
                        value: RoutineKind.someday, label: Text('Some day')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) => setState(() {
                    _type = v.first;
                    _touched(RoutineFormField.schedule);
                    _touched(RoutineFormField.dueOn);
                  }),
                ),
                const SizedBox(height: 16),
                if (_type == RoutineKind.recurring) ..._buildSchedule(marked),
                if (_type == RoutineKind.oneOff) ..._buildDue(marked),
                if (_type == RoutineKind.someday)
                  const Text(
                    'No day: it is not on the agenda. Tick it off from here '
                    'when it is done.',
                    key: Key('routine-form-someday-note'),
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                const SizedBox(height: 8),
                _DateTile(
                  tileKey: const Key('routine-form-time'),
                  label: 'Hour',
                  value: _time == null ? 'None' : _formatTime(_time!),
                  onTap: _pickTime,
                  onClear:
                      _time == null ? null : () => setState(() => _time = null),
                ),
                if (_type == RoutineKind.recurring) ...[
                _DateTile(
                  tileKey: const Key('routine-form-last-day'),
                  label: 'Last day',
                  value: _lastDay == null
                      ? 'None'
                      : formatRoutineDay(_lastDay!),
                  onTap: _pickLastDay,
                  onClear: _lastDay == null
                      ? null
                      : () => setState(() {
                            _lastDay = null;
                            _touched(RoutineFormField.lastDay);
                          }),
                  invalid: marked == RoutineFormField.lastDay,
                ),
                const SizedBox(height: 8),
                Text('When nobody ticks it off on its day',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                SegmentedButton<RoutineMissed>(
                  key: const Key('routine-form-missed'),
                  segments: const [
                    ButtonSegment(
                        value: RoutineMissed.lapses, label: Text('Lapses')),
                    ButtonSegment(
                        value: RoutineMissed.waits, label: Text('Waits')),
                  ],
                  selected: {_missed},
                  onSelectionChanged: (v) => setState(() {
                    _missed = v.first;
                    _missedTouched = true;
                  }),
                ),
                ],
                const SizedBox(height: 16),
                ..._buildSteps(),
              ],
            ),
    );
  }

  Widget _buildLoading(RoutineFormState state) {
    if (state.loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(state.error ?? 'Failed to load the routine',
              key: const Key('routine-form-error'),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: ref
                .read(routineFormNotifierProvider(widget.editId).notifier)
                .load,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// The error look of a text field, without a second copy of the message:
  /// the message is shown above the form.
  static Widget? _mark(bool invalid) =>
      invalid ? const SizedBox.shrink() : null;

  List<Widget> _buildSchedule(RoutineFormField? marked) {
    return [
      if (_unknownRRule != null && _kind == null) ...[
        Text(
          'The current schedule ($_unknownRRule) cannot be shown here: '
          'choose one.',
          key: const Key('routine-form-unknown-rrule'),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
      ],
      DropdownButtonFormField<RoutineScheduleKind>(
        key: const Key('routine-form-kind'),
        initialValue: _kind,
        decoration: InputDecoration(
          labelText: 'Schedule',
          border: const OutlineInputBorder(),
          error: _mark(marked == RoutineFormField.schedule),
        ),
        items: const [
          DropdownMenuItem(
              value: RoutineScheduleKind.daily, child: Text('Every day')),
          DropdownMenuItem(
              value: RoutineScheduleKind.weekdays,
              child: Text('Chosen weekdays')),
          DropdownMenuItem(
              value: RoutineScheduleKind.weeks, child: Text('Every N weeks')),
          DropdownMenuItem(
              value: RoutineScheduleKind.monthly,
              child: Text('Day of the month')),
        ],
        onChanged: _setKind,
      ),
      if (_kind == RoutineScheduleKind.weeks) ...[
        const SizedBox(height: 12),
        TextField(
          key: const Key('routine-form-interval'),
          controller: _interval,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) =>
              setState(() => _touched(RoutineFormField.interval)),
          decoration: InputDecoration(
            labelText: 'Every how many weeks',
            border: const OutlineInputBorder(),
            error: _mark(marked == RoutineFormField.interval),
          ),
        ),
      ],
      if (_kind == RoutineScheduleKind.weekdays ||
          _kind == RoutineScheduleKind.weeks) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: routineWeekdays
              .map((d) => FilterChip(
                    key: Key('routine-form-day-$d'),
                    label: Text(routineWeekdayNames[d]!),
                    labelStyle: marked == RoutineFormField.days
                        ? TextStyle(
                            color: Theme.of(context).colorScheme.error)
                        : null,
                    selected: _days.contains(d),
                    onSelected: (on) => setState(() {
                      on ? _days.add(d) : _days.remove(d);
                      _touched(RoutineFormField.days);
                    }),
                  ))
              .toList(),
        ),
      ],
      if (_kind == RoutineScheduleKind.monthly) ...[
        const SizedBox(height: 12),
        TextField(
          key: const Key('routine-form-monthday'),
          controller: _monthday,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) =>
              setState(() => _touched(RoutineFormField.monthday)),
          decoration: InputDecoration(
            labelText: 'Day of the month (1–31)',
            border: const OutlineInputBorder(),
            error: _mark(marked == RoutineFormField.monthday),
          ),
        ),
      ],
    ];
  }

  /// A one-off's day and window: due that day, or within a week or a month
  /// from it.
  List<Widget> _buildDue(RoutineFormField? marked) {
    return [
      _DateTile(
        tileKey: const Key('routine-form-due-on'),
        label: 'Day',
        value: _dueOn == null ? 'Choose' : formatRoutineDay(_dueOn!),
        onTap: _pickDueOn,
        invalid: marked == RoutineFormField.dueOn,
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<TimeWindow>(
        key: const Key('routine-form-due-window'),
        initialValue: _dueWindow,
        decoration: const InputDecoration(
          labelText: 'Due',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: TimeWindow.day, child: Text('That day')),
          DropdownMenuItem(
              value: TimeWindow.week, child: Text('Within a week from it')),
          DropdownMenuItem(
              value: TimeWindow.month, child: Text('Within a month from it')),
        ],
        onChanged: (w) => setState(() => _dueWindow = w ?? TimeWindow.day),
      ),
      const Text(
        'A task not done in time waits on the agenda until ticked off.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    ];
  }

  List<Widget> _buildSteps() {
    return [
      Text('Steps', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      for (var i = 0; i < _steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key('routine-form-step-$i'),
                  controller: _steps[i],
                  decoration: InputDecoration(
                    labelText: 'Step ${i + 1}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                key: Key('routine-form-step-up-$i'),
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Move up',
                onPressed: i == 0
                    ? null
                    : () => setState(() {
                          final c = _steps.removeAt(i);
                          _steps.insert(i - 1, c);
                        }),
              ),
              IconButton(
                key: Key('routine-form-step-remove-$i'),
                icon: const Icon(Icons.close),
                tooltip: 'Remove',
                onPressed: _steps.length == 1
                    ? null
                    : () => setState(() => _steps.removeAt(i).dispose()),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('routine-form-add-step'),
          icon: const Icon(Icons.add),
          label: const Text('Add step'),
          onPressed: () =>
              setState(() => _steps.add(TextEditingController())),
        ),
      ),
    ];
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.tileKey,
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
    this.invalid = false,
  });

  final Key tileKey;
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  /// Marks the field the form's error is about.
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return ListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: invalid ? TextStyle(color: errorColor) : null),
      subtitle: Text(value,
          style: invalid ? TextStyle(color: errorColor) : null),
      iconColor: invalid ? errorColor : null,
      onTap: onTap,
      trailing: onClear == null
          ? const Icon(Icons.edit_calendar_outlined)
          : IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: onClear,
            ),
    );
  }
}
