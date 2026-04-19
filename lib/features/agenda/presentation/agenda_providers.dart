import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/providers/api_client_provider.dart';
import 'package:voice_agent/features/agenda/data/api_agenda_repository.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';
import 'package:voice_agent/features/agenda/domain/agenda_state.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_notifier.dart';

final agendaRepositoryProvider = Provider<AgendaRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiAgendaRepository(apiClient);
});

final agendaNotifierProvider =
    StateNotifierProvider<AgendaNotifier, AgendaState>((ref) {
  final repository = ref.watch(agendaRepositoryProvider);
  return AgendaNotifier(repository);
});
