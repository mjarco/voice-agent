import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/router.dart';
import 'package:voice_agent/core/providers/deep_link_providers.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key, this.scaffoldMessengerKey});

  /// Global key for [ScaffoldMessengerState], used by [Toaster] to show
  /// toasts without a [BuildContext]. Created in `main.dart` and shared
  /// via the [toasterProvider] override in [ProviderScope].
  ///
  /// When null (tests), [MaterialApp] uses its own internal key and
  /// toast functionality is not available.
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  late final GoRouter _router = createRouter();
  bool _coldStartConsumed = false;

  @override
  void initState() {
    super.initState();

    // Cold-start deep-link consumption (ADR-PLATFORM-008). One-shot: read
    // once on first frame, then clear. If a tap arrives during the init
    // window before the warm-path callback is registered, it is lost —
    // documented as acceptable; user can re-tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_coldStartConsumed) return;
      _coldStartConsumed = true;
      final pending = ref.read(pendingDeepLinkProvider);
      if (pending != null && pending.isNotEmpty) {
        _router.go(pending);
        ref.read(pendingDeepLinkProvider.notifier).state = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Warm-path notification taps (ADR-PLATFORM-008). Routes every emission
    // for the lifetime of the app.
    ref.listen<AsyncValue<String>>(notificationTapStreamProvider, (prev, next) {
      next.whenData((payload) {
        if (payload.isNotEmpty) _router.go(payload);
      });
    });

    final isDev = appFlavor == 'dev';
    return MaterialApp.router(
      title: isDev ? 'Voice Agent DEV' : 'Voice Agent',
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      theme: ThemeData(
        colorSchemeSeed: isDev ? Colors.orange : Colors.blue,
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
