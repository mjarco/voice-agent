import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts the turns personal-agent has answered, spoken or typed: each may
/// have written into a matter, the agenda or the day. Screens that stay alive
/// under a pushed route read themselves again on a change (device check of
/// V3, F1: a matter's screen kept its old state after a typed conversation
/// on it). A counter, so two equal replies ("Zapisane.") still count twice.
///
/// Producers: `SyncWorker`'s reply (`sync_provider.dart`) and
/// `ThreadNotifier`'s result. Consumers: `MatterDetailScreen` and Dziś
/// (`todayNotifierProvider`).
final agentTurnsProvider = StateProvider<int>((ref) => 0);
