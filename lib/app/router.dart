import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/app_shell_scaffold.dart';
import 'package:voice_agent/features/recording/presentation/recording_screen.dart';

final router = GoRouter(
  initialLocation: '/record',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShellScaffold(navigationShell: navigationShell);
      },
      branches: [
        // Branch 0: History
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/history',
              builder: (context, state) => const _PlaceholderScreen(
                title: 'History',
              ),
            ),
          ],
        ),
        // Branch 1: Record (default)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/record',
              builder: (context, state) =>
                  const RecordingScreen(),
              routes: [
                GoRoute(
                  path: 'review',
                  builder: (context, state) => const _PlaceholderScreen(
                    title: 'Review',
                  ),
                ),
              ],
            ),
          ],
        ),
        // Branch 2: Settings
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const _PlaceholderScreen(
                title: 'Settings',
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(title),
      ),
    );
  }
}
