import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/app_shell_scaffold.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_screen.dart';
import 'package:voice_agent/app/placeholders/chat_placeholder_screen.dart';
import 'package:voice_agent/app/placeholders/plan_placeholder_screen.dart';
import 'package:voice_agent/app/placeholders/routines_placeholder_screen.dart';
import 'package:voice_agent/features/history/history_screen.dart';
import 'package:voice_agent/features/history/transcript_detail_screen.dart';
import 'package:voice_agent/features/recording/presentation/recording_screen.dart';
import 'package:voice_agent/features/settings/advanced_settings_screen.dart';
import 'package:voice_agent/features/settings/settings_screen.dart';

GoRouter createRouter() => GoRouter(
  initialLocation: '/record',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShellScaffold(navigationShell: navigationShell);
      },
      branches: [
        // Branch 0: Agenda
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/agenda',
              builder: (context, state) => const AgendaScreen(),
            ),
          ],
        ),
        // Branch 1: Plan
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/plan',
              builder: (context, state) => const PlanPlaceholderScreen(),
            ),
          ],
        ),
        // Branch 2: Record (default)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/record',
              builder: (context, state) => const RecordingScreen(),
              routes: [
                GoRoute(
                  path: 'history',
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
          ],
        ),
        // Branch 3: Routines
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/routines',
              builder: (context, state) => const RoutinesPlaceholderScreen(),
            ),
          ],
        ),
        // Branch 4: Chat
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
              builder: (context, state) => const ChatPlaceholderScreen(),
            ),
          ],
        ),
      ],
    ),
    // Settings — outside shell (full-screen, no bottom nav)
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
      routes: [
        GoRoute(
          path: 'advanced',
          builder: (context, state) => const AdvancedSettingsScreen(),
        ),
      ],
    ),
  ],
);
