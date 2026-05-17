import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/config/app_config_service.dart';
import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/core/models/routine.dart';
import 'package:voice_agent/core/notifications/agenda_notification_scheduler.dart';
import 'package:voice_agent/core/providers/session_active_provider.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/domain/agenda_state.dart';

class AgendaNotifier extends StateNotifier<AgendaState> {
  AgendaNotifier(
    this._repository, {
    required AgendaNotificationScheduler scheduler,
    required AppConfigService configService,
    required Ref ref,
  })  : _scheduler = scheduler,
        _configService = configService,
        _ref = ref,
        super(const AgendaInitial()) {
    _selectedDate = DateTime.now();
    _setupSessionListener();
    loadAgenda();
  }

  final AgendaRepository _repository;
  final AgendaNotificationScheduler _scheduler;
  final AppConfigService _configService;
  final Ref _ref;
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

  /// Per P040 §Session Gating:
  ///   true → false: full refresh (occurrence may have been added during the
  ///   session via the web UI; only a fetch surfaces it).
  ///   false → true: reconcile-only against current cached response
  ///   (cancels per-occurrence reminders without a network round trip).
  void _setupSessionListener() {
    _ref.listen<bool>(sessionActiveProvider, (prev, next) {
      if (prev == null) return;
      if (prev == false && next == true) {
        final s = state;
        if (s is AgendaLoaded && isToday) {
          unawaited(_safeReconcile(s.response, sessionActive: true));
        }
      } else if (prev == true && next == false) {
        unawaited(refresh());
      }
    });
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
      // Persist last-fetch-at for the foreground staleness trigger
      // (app-resume check) and the bg isolate's 50-min skip guard.
      unawaited(_configService.setLastAgendaFetchAt(DateTime.now()));
      // Fire-and-forget reconcile, only for today (non-today views are for
      // browsing — they must not drive OS notification scheduling).
      if (isToday) {
        unawaited(_safeReconcile(
          response,
          sessionActive: _ref.read(sessionActiveProvider),
        ));
      }
    } catch (e) {
      state = AgendaError(message: e.toString(), cached: cached);
      // Per P040 §Reconciler Triggers: do NOT reconcile from error(cached).
      // Stale-data reconciliation could fire reminders for items that no
      // longer exist on the server.
    }
  }

  Future<void> _safeReconcile(
    AgendaResponse response, {
    required bool sessionActive,
  }) async {
    try {
      await _scheduler.reconcile(response, sessionActive: sessionActive);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AgendaNotifier] reconcile failed: $e\n$st');
      }
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

  void nextDay() => selectDate(_selectedDate.add(const Duration(days: 1)));

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
