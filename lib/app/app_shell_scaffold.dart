import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/core/network/connectivity_service.dart';
import 'package:voice_agent/core/providers/app_foreground_provider.dart';
import 'package:voice_agent/features/activation/presentation/activation_provider.dart';
import 'package:voice_agent/features/api_sync/sync_provider.dart';
import 'package:voice_agent/features/recording/presentation/recording_providers.dart';

class AppShellScaffold extends ConsumerStatefulWidget {
  const AppShellScaffold({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShellScaffold> createState() => _AppShellScaffoldState();
}

class _AppShellScaffoldState extends ConsumerState<AppShellScaffold>
    with WidgetsBindingObserver {
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
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncWorkerProvider);
    ref.watch(handsFreeControllerProvider);
    ref.watch(activationControllerProvider);

    ref.listen<AsyncValue<ConnectivityStatus>>(
      connectivityStatusProvider,
      (prev, next) {
        next.whenData((status) {
          if (status == ConnectivityStatus.offline) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No internet connection – sync paused'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        });
      },
    );

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) {
          const recordTabIndex = 2;
          final currentIndex = widget.navigationShell.currentIndex;
          if (currentIndex == recordTabIndex && index != recordTabIndex) {
            unawaited(
              ref.read(handsFreeControllerProvider.notifier).stopSession(),
            );
          } else if (index == recordTabIndex && currentIndex != recordTabIndex) {
            unawaited(
              ref.read(handsFreeControllerProvider.notifier).startSession(),
            );
          }
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.repeat),
            label: 'Routines',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}
