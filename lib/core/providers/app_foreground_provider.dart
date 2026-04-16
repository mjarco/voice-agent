import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is currently in the foreground (resumed).
/// Set by `AppShellScaffold` via `WidgetsBindingObserver`.
final appForegroundedProvider = StateProvider<bool>((ref) => true);
