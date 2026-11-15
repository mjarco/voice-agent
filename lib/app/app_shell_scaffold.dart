import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/config/app_config_provider.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/observability/telemetry.dart';
import 'package:voice_agent/core/providers/app_foreground_provider.dart';
import 'package:voice_agent/core/providers/shopping_list_changes_provider.dart';
import 'package:voice_agent/core/widgets/glass.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_providers.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/features/matters/presentation/matters_providers.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';
import 'package:voice_agent/features/recording/presentation/voice_inputs_host.dart';
import 'package:voice_agent/features/today/presentation/today_providers.dart';

class AppShellScaffold extends ConsumerStatefulWidget {
  const AppShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShellScaffold> createState() => _AppShellScaffoldState();
}

class _AppShellScaffoldState extends ConsumerState<AppShellScaffold>
    with WidgetsBindingObserver {
  // Matches Branch 0 in router.dart's StatefulShellRoute: Dziś, the start
  // screen, where Back from every other tab lands (V1 of the redesign).
  static const _todayTabIndex = 0;
  // Matches Branch 3. A proposal made by voice reaches the app in no other way
  // than a read of this tab.
  static const _shoppingTabIndex = 3;
  // Matches Branch 2. The list stays built in the shell, so a return to the
  // tab reads it again, as the push of its page did before ADR-ARCH-012.
  static const _mattersTabIndex = 2;

  /// P040 §Reconciler Triggers #2: kick a refresh on app resume if the last
  /// successful agenda fetch was >1h ago. Compensates for iOS BGAppRefresh
  /// being opportunistic.
  static const _stalenessThreshold = Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appForegroundedProvider.notifier).state =
        state == AppLifecycleState.resumed;

    // P039 T6 — emit lifecycle events so the Grafana timeline can
    // correlate audio/sync activity with foreground/background
    // transitions. Inactive/paused/hidden are background-ish; we
    // collapse them into `app.background` for the dashboard with
    // the precise state as an attr.
    switch (state) {
      case AppLifecycleState.resumed:
        Telemetry.instance.event('app.foreground');
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        Telemetry.instance.event(
          'app.background',
          attrs: {'state': state.name},
        );
      case AppLifecycleState.detached:
        // Best-effort terminate notification before the engine tears down.
        Telemetry.instance.event('app.terminate');
    }

    // P040 §Reconciler Triggers #2: staleness-driven foreground refresh.
    if (state == AppLifecycleState.resumed) {
      unawaited(_kickRefreshIfStale());
      // Dziś is the day as it is now: an app left overnight must not open on
      // yesterday, nor on what another device changed meanwhile.
      if (ref.exists(todayNotifierProvider)) {
        unawaited(ref.read(todayNotifierProvider.notifier).refresh());
      }
    }
    // Leaving the app is when the owner next sees the home-screen widget: what
    // was done in the app (a meal logged on the diet's day) reaches it now,
    // not at the next background read (ADR-PLATFORM-015).
    if (state == AppLifecycleState.paused &&
        ref.exists(todayNotifierProvider)) {
      unawaited(ref.read(todayNotifierProvider.notifier).refresh());
    }
  }

  Future<void> _kickRefreshIfStale() async {
    try {
      final configService = ref.read(appConfigServiceProvider);
      final last = await configService.getLastAgendaFetchAt();
      if (last == null ||
          DateTime.now().difference(last) > _stalenessThreshold) {
        // Reading the notifier instantiates it if it wasn't already — but
        // it IS already, because `ref.watch(agendaNotifierProvider)` in
        // build() promotes it to app scope per ADR-ARCH-009.
        unawaited(ref.read(agendaNotifierProvider.notifier).refresh());
      }
    } catch (_) {
      // Staleness check is best-effort; never crash the resume path.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncWorkerProvider);
    ref.watch(handsFreeControllerProvider);

    // P040 §Reconciler Triggers preamble: promote `agendaNotifierProvider`
    // to app scope per ADR-ARCH-009 (criteria 1-3 satisfied: cross-feature
    // event listening, negligible idle cost, screen-level behavior
    // preserved). The notifier listens to `sessionActiveProvider` edges
    // and reacts to app-lifecycle staleness even when the Agenda tab has
    // not been visited.
    ref.watch(agendaNotifierProvider);

    ref.listen<AsyncValue<ConnectivityStatus>>(connectivityStatusProvider, (
      prev,
      next,
    ) {
      next.whenData((status) {
        if (status == ConnectivityStatus.offline) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Brak internetu — wysyłanie wstrzymane'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    });

    final onToday = widget.navigationShell.currentIndex == _todayTabIndex;
    // Back on a tab's own screen goes to Dziś, not out of the app; a
    // notification's target opened on a tab is thus "over Dziś" (06 §2).
    return PopScope(
      canPop: onToday,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.navigationShell.goBranch(_todayTabIndex);
      },
      child: Scaffold(
        // The tabs' pages run under the floating bar (off-roadmap S2).
        extendBody: true,
        body: VoiceInputsHost(child: widget.navigationShell),
        bottomNavigationBar: GlassTabBar(
          bar: NavigationBar(
            selectedIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: (index) {
              final currentIndex = widget.navigationShell.currentIndex;
              // ADR-AUDIO-013: the tabs never touch the microphone; since Record
              // stopped being a tab (V1 of the redesign) that holds on iOS too.
              if (index == _todayTabIndex &&
                  ref.exists(todayNotifierProvider)) {
                unawaited(ref.read(todayNotifierProvider.notifier).refresh());
              }
              if (index == _shoppingTabIndex && index != currentIndex) {
                ref.read(shoppingListChangesProvider.notifier).state++;
              }
              // The first visit builds the list, which reads it; only a return
              // reads it again.
              if (index == _mattersTabIndex &&
                  index != currentIndex &&
                  ref.exists(mattersNotifierProvider)) {
                unawaited(ref.read(mattersNotifierProvider.notifier).refresh());
              }
              widget.navigationShell.goBranch(
                index,
                initialLocation: index == currentIndex,
              );
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.wb_sunny_outlined),
                label: 'Dziś',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_outlined),
                label: 'Agenda',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_open_outlined),
                label: 'Sprawy',
              ),
              NavigationDestination(
                icon: Icon(Icons.shopping_cart_outlined),
                label: 'Zakupy',
              ),
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                label: 'Rozmowy',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
