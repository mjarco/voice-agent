import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/app_shell_scaffold.dart';
import 'package:voice_agent/features/history/history_screen.dart';
import 'package:voice_agent/features/history/transcript_detail_screen.dart';
import 'package:voice_agent/features/recording/presentation/recording_screen.dart';
import 'package:voice_agent/features/settings/advanced_settings_screen.dart';
import 'package:voice_agent/features/settings/settings_screen.dart';

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
              builder: (context, state) => const HistoryScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return TranscriptDetailScreen(transcriptId: id);
                  },
                ),
              ],
            ),
          ],
        ),
        // Branch 1: Record (default)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/record',
              builder: (context, state) => const RecordingScreen(),
            ),
          ],
        ),
        // Branch 2: Settings
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'advanced',
                  builder: (context, state) =>
                      const AdvancedSettingsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);
