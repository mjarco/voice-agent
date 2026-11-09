import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Agenda and the routines' section share one screen since ADR-ARCH-012,
/// and each reads its own endpoint; these counters tell one that the other
/// changed something (ADR-ARCH-008). Two counters, so neither answers its own
/// signal.

/// Bumped by `RoutinesSection` after it created, paused or resumed a routine,
/// or came back from a routine's pages. Consumer: `AgendaScreen`, which reads
/// the day again.
final routinesEditedProvider = StateProvider<int>((ref) => 0);

/// Bumped by `AgendaScreen` after a tick, an undo or a pull to refresh.
/// Consumer: `RoutinesSection`, which reads the routines again.
final agendaTickedProvider = StateProvider<int>((ref) => 0);
