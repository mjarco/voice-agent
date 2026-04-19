import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/domain/agenda_state.dart';

class AgendaNotifier extends StateNotifier<AgendaState> {
  AgendaNotifier(this._repository) : super(const AgendaInitial()) {
    _selectedDate = DateTime.now();
    loadAgenda();
  }

  final AgendaRepository _repository;
  late DateTime _selectedDate;

  DateTime get selectedDate => _selectedDate;

  String get _dateString =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  bool get isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> loadAgenda() async {
    final cached = await _repository.getCachedAgenda(_dateString);
    state = AgendaLoading(cached: cached);

    try {
      final response = await _repository.fetchAgenda(_dateString);
      state = AgendaLoaded(
        response: response,
        fetchedAt: DateTime.now(),
      );
      await _repository.cacheAgenda(_dateString, response);
    } catch (e) {
      state = AgendaError(message: e.toString(), cached: cached);
    }
  }

  Future<void> refresh() => loadAgenda();

  void selectDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    loadAgenda();
  }

  void goToToday() => selectDate(DateTime.now());

  void previousDay() =>
      selectDate(_selectedDate.subtract(const Duration(days: 1)));

  void nextDay() =>
      selectDate(_selectedDate.add(const Duration(days: 1)));

  Future<bool> markDone(String recordId) async {
    try {
      await _repository.markActionItemDone(recordId);
      await loadAgenda();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> skipOccurrence(String routineId, String occurrenceId) async {
    try {
      await _repository.updateOccurrenceStatus(
        routineId,
        occurrenceId,
        OccurrenceStatus.skipped,
      );
      await loadAgenda();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> completeOccurrence(
      String routineId, String occurrenceId) async {
    try {
      await _repository.updateOccurrenceStatus(
        routineId,
        occurrenceId,
        OccurrenceStatus.done,
      );
      await loadAgenda();
      return true;
    } catch (_) {
      return false;
    }
  }
}
