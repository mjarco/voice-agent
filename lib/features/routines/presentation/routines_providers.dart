import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/routines/data/api_routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routine_detail_state.dart';
import 'package:voice_agent/features/routines/domain/routine_form_state.dart';
import 'package:voice_agent/features/routines/domain/routines_repository.dart';
import 'package:voice_agent/features/routines/domain/routines_state.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_notifier.dart';
import 'package:voice_agent/features/routines/presentation/routine_form_notifier.dart';
import 'package:voice_agent/features/routines/presentation/routines_notifier.dart';

final routinesRepositoryProvider = Provider<RoutinesRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiRoutinesRepository(apiClient);
});

final routinesNotifierProvider =
    StateNotifierProvider<RoutinesNotifier, RoutinesState>((ref) {
  final repository = ref.watch(routinesRepositoryProvider);
  return RoutinesNotifier(repository);
});

/// Disposed with its page: a version opened again (a version link, after an
/// edit) loads afresh instead of showing what it was before.
final routineDetailNotifierProvider = StateNotifierProvider.autoDispose
    .family<RoutineDetailNotifier, RoutineDetailState, String>(
        (ref, routineId) {
  final repository = ref.watch(routinesRepositoryProvider);
  return RoutineDetailNotifier(repository, routineId);
});

/// The routine form: `null` creates a routine, an id edits that routine.
final routineFormNotifierProvider = StateNotifierProvider.autoDispose
    .family<RoutineFormNotifier, RoutineFormState, String?>((ref, editId) {
  final repository = ref.watch(routinesRepositoryProvider);
  return RoutineFormNotifier(repository, editId);
});

/// The device's clock; the form and End after… count today from it, the way
/// the web UI counts from the browser's date. Tests override it.
final routinesClockProvider = Provider<DateTime Function()>((_) => DateTime.now);
