import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts the moments the Shopping tab's list or waiting proposals may have
/// changed elsewhere (ADR-ARCH-008). The tab stays alive in the shell and does
/// not poll.
///
/// Producers: `ThreadNotifier` (a turn that proposed, an answer in the chat) and
/// `AppShellScaffold` (the tab opened, where a proposal made by voice appears).
/// Consumer: `ShoppingScreen`, which reads the list again.
final shoppingListChangesProvider = StateProvider<int>((ref) => 0);
