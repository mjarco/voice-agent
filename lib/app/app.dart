import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/router.dart';
import 'package:voice_agent/core/home_widget/home_widget_provider.dart';
import 'package:voice_agent/core/home_widget/widget_tap_channel.dart';
import 'package:voice_agent/core/providers/deep_link_providers.dart';
import 'package:voice_agent/features/location_log/presentation/location_log_sync.dart';
import 'package:voice_agent/features/pins/presentation/pins_providers.dart';
import 'package:voice_agent/features/places/presentation/places_sync.dart';
import 'package:voice_agent/features/recording/presentation/mic_activity.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';

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
        _router.go(pending, extra: DeepLinkTap());
        ref.read(pendingDeepLinkProvider.notifier).state = null;
      }
      final widgetTap = ref.read(pendingWidgetTapProvider);
      if (widgetTap != null) {
        _openWidgetTap(widgetTap);
        ref.read(pendingWidgetTapProvider.notifier).state = null;
      }
      final sharedText = ref.read(pendingSharedTextProvider);
      if (sharedText != null) {
        _openSharedText(sharedText);
        ref.read(pendingSharedTextProvider.notifier).state = null;
      }
    });
  }

  /// Pushes, as `go` would drop the shell and the hands-free session under it.
  /// A new-pin form on top is replaced, so two forms never write one draft.
  void _openSharedText(String text) {
    if (text.trim().isEmpty) return;
    final closed = _router.state.fullPath == '/pins/new'
        ? _router.pushReplacement<Object?>('/pins/new', extra: text)
        : _router.push<Object?>('/pins/new', extra: text);
    closed.then((_) => _refreshPins());
  }

  /// A tap on the home-screen widget (ADR-PLATFORM-015). Every screen opens
  /// over Dziś, so Back lands there; the mic opens Dziś listening, as a widget
  /// cannot start the microphone without the app in front (the task's D1).
  void _openWidgetTap(WidgetTap tap) {
    switch (tap) {
      case WidgetTap.food:
        _router.go('/today');
        _router.push<Object?>('/diet').then((_) => _refreshToday());
      case WidgetTap.tasks:
        _router.go('/today');
      case WidgetTap.matters:
        _router.go('/matters');
      case WidgetTap.listen:
        _router.go('/today');
        _whenResumed(
          () => ref.read(handsFreeControllerProvider.notifier).listen(),
        );
    }
  }

  /// The microphone starts only with the activity in front: a warm tap
  /// arrives through onNewIntent, before the activity is resumed.
  void _whenResumed(VoidCallback action) {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      action();
      return;
    }
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        listener.dispose();
        if (mounted) action();
      },
    );
  }

  void _refreshToday() {
    if (mounted && ref.exists(todayNotifierProvider)) {
      ref.read(todayNotifierProvider.notifier).refresh();
    }
  }

  /// The list loads once, and a form opened from here has no list to return to.
  void _refreshPins() {
    if (mounted && ref.exists(pinsNotifierProvider)) {
      ref.read(pinsNotifierProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Warm-path notification taps (ADR-PLATFORM-008). Routes every emission
    // for the lifetime of the app.
    ref.listen<AsyncValue<String>>(notificationTapStreamProvider, (prev, next) {
      next.whenData((payload) {
        if (payload.isNotEmpty) _router.go(payload, extra: DeepLinkTap());
      });
    });

    ref.listen<AsyncValue<WidgetTap>>(widgetTapStreamProvider, (prev, next) {
      next.whenData(_openWidgetTap);
    });

    ref.listen<AsyncValue<SharedText>>(sharedTextStreamProvider, (prev, next) {
      next.whenData((shared) => _openSharedText(shared.text));
    });

    ref.watch(locationLogSyncProvider);
    ref.watch(locationLogResumeProvider);
    ref.watch(placesSyncProvider);

    final isDev = appFlavor == 'dev';
    return MaterialApp.router(
      title: isDev ? 'Voice Agent DEV' : 'Voice Agent',
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      theme: ThemeData(
        colorSchemeSeed: isDev ? Colors.orange : Colors.blue,
        useMaterial3: true,
      ),
      routerConfig: _router,
      // The mic's state over every screen (V1 device check, the owner's
      // remark of 2026-11-15): a strip at the top edge, under the status bar.
      builder: (context, child) => Stack(
        children: [
          ?child,
          Positioned(
            top: MediaQuery.paddingOf(context).top,
            left: 0,
            right: 0,
            child: const MicActivityStrip(),
          ),
        ],
      ),
    );
  }
}
