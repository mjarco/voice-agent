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
/// the web UI's (thought-agent#564). The client builds the RRULE from the
/// four schedules; saving pops with the routine the server wrote.
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
  String? _unknownRRule;
  RoutineScheduleKind? _kind = RoutineScheduleKind.daily;
  final Set<String> _days = {};
  TimeOfDay? _time;
  DateTime? _lastDay;
  late DateTime _startsOn;
  RoutineMissed _missed = RoutineMissed.lapses;
  bool _missedTouched = false;
  String? _validation;

  /// Set when the last day is what keeps the form from saving: the field is
  /// marked until it changes.
  bool _lastDayInvalid = false;

  bool get _isEdit => widget.editId != null;

  DateTime get _today {
    final now = ref.read(routinesClockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _startsOn = _today;
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
    final schedule = RoutineSchedule.parse(r.rrule);
    if (schedule == null) {
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
    // A last day already past (an ended routine) is not offered again: the
    // new version cannot end before it starts.
    final last = parseRoutineDay(r.lastDay);
    _lastDay = last != null && !last.isBefore(_today) ? last : null;
    _missed = r.missed;
    _missedTouched = true;
    final templates = [...r.templates]
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
      // A monthly routine waits, any other lapses (ADR-CORE-092), until the
      // owner chooses.
      if (!_missedTouched && kind != null) {
        _missed = kind == RoutineScheduleKind.monthly
            ? RoutineMissed.waits
            : RoutineMissed.lapses;
      }
    });
  }

  /// The form as a [RoutineInput], or a message naming what to fix.
  (RoutineInput?, String?) _input() {
    _lastDayInvalid = false;
    final name = _name.text.trim();
    if (name.isEmpty) return (null, 'Give the routine a name.');
    final kind = _kind;
    if (kind == null) return (null, 'Choose a schedule.');
    final days = routineWeekdays.where(_days.contains).toList();
    RoutineSchedule schedule;
    switch (kind) {
      case RoutineScheduleKind.daily:
        schedule = const RoutineSchedule.daily();
      case RoutineScheduleKind.weekdays:
        if (days.isEmpty) return (null, 'Choose at least one day of the week.');
        schedule = RoutineSchedule.weekdays(days);
      case RoutineScheduleKind.weeks:
        if (days.isEmpty) return (null, 'Choose at least one day of the week.');
        final n = int.tryParse(_interval.text.trim());
        if (n == null || n < 2) {
          return (null, 'Every N weeks needs N of 2 or more.');
        }
        schedule = RoutineSchedule.weeks(days, n);
      case RoutineScheduleKind.monthly:
        final d = int.tryParse(_monthday.text.trim());
        if (d == null || d < 1 || d > 31) {
          return (null, 'Choose a day of the month from 1 to 31.');
        }
        schedule = RoutineSchedule.monthly(d);
    }
    final from = _isEdit ? _startsOn : _today;
    final last = _lastDay;
    if (last != null && last.isBefore(from)) {
      _lastDayInvalid = true;
      return (null, 'The last day cannot be before the start day.');
    }
    if (last != null && !schedule.occursBetween(from, last)) {
      _lastDayInvalid = true;
      return (
        null,
        'No day of this schedule falls between ${formatRoutineDay(from)} '
            'and the last day. Move the last day or clear it.'
      );
    }
    return (
      RoutineInput(
        name: name,
        rrule: schedule.toRRule(),
        startTime: _time == null ? null : _formatTime(_time!),
        lastDay: _lastDay == null ? null : formatRoutineDay(_lastDay!),
        missed: _missed,
        items: _steps
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
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
        .save(input, startsOn: _isEdit ? formatRoutineDay(_startsOn) : null);
  }

  Future<void> _askOverdue(String day) async {
    final notifier =
        ref.read(routineFormNotifierProvider(widget.editId).notifier);
    final status = await showDialog<OccurrenceStatus>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('An occurrence is still open'),
        content: Text(
          'This routine still owes $day. Tick it off or skip it, '
          'and the edit is saved again.',
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

  Future<void> _pickStartsOn() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsOn,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _startsOn = picked);
  }

  Future<void> _pickLastDay() async {
    final first = _isEdit && _startsOn.isAfter(_today) ? _startsOn : _today;
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
        _lastDayInvalid = false;
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
                if (_isEdit) ...[
                  _DateTile(
                    tileKey: const Key('routine-form-starts-on'),
                    label: 'Changes from',
                    value: formatRoutineDay(_startsOn),
                    onTap: _pickStartsOn,
                  ),
                  const Text(
                    'The current version ends the day before; '
                    'the new one starts that day.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const Key('routine-form-name'),
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ..._buildSchedule(),
                const SizedBox(height: 8),
                _DateTile(
                  tileKey: const Key('routine-form-time'),
                  label: 'Hour',
                  value: _time == null ? 'None' : _formatTime(_time!),
                  onTap: _pickTime,
                  onClear:
                      _time == null ? null : () => setState(() => _time = null),
                ),
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
                            _lastDayInvalid = false;
                          }),
                  invalid: _lastDayInvalid,
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

  List<Widget> _buildSchedule() {
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
        decoration: const InputDecoration(
          labelText: 'Schedule',
          border: OutlineInputBorder(),
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
          decoration: const InputDecoration(
            labelText: 'Every how many weeks',
            border: OutlineInputBorder(),
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
                    selected: _days.contains(d),
                    onSelected: (on) => setState(
                        () => on ? _days.add(d) : _days.remove(d)),
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
          decoration: const InputDecoration(
            labelText: 'Day of the month (1–31)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
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
