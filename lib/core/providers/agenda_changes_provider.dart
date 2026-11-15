import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts the moments the agenda may have changed outside the Agenda tab
/// (ADR-ARCH-008): a task swiped done or skipped on Dziś. The Agenda tab stays
/// alive in the shell; its notifier reads the day again on a change.
///
/// Producer: `TodayNotifier`. Consumer: `AgendaNotifier`.
final agendaChangesProvider = StateProvider<int>((ref) => 0);
