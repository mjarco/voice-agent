import 'package:voice_agent/core/models/agenda.dart';
import 'package:voice_agent/features/agenda/domain/agenda_repository.dart';

sealed class AgendaState {
  const AgendaState();
}

class AgendaInitial extends AgendaState {
  const AgendaInitial();
}

class AgendaLoading extends AgendaState {
  const AgendaLoading({this.cached});
  final CachedAgenda? cached;
}

class AgendaLoaded extends AgendaState {
  const AgendaLoaded({required this.response, required this.fetchedAt});
  final AgendaResponse response;
  final DateTime fetchedAt;
}

class AgendaError extends AgendaState {
  const AgendaError({required this.message, this.cached});
  final String message;
  final CachedAgenda? cached;
}
