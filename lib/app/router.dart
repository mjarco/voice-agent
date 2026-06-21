import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/app_shell_scaffold.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_screen.dart';
import 'package:voice_agent/features/chat/presentation/conversations_screen.dart';
import 'package:voice_agent/features/chat/presentation/thread_screen.dart';
import 'package:voice_agent/features/pins/presentation/pin_detail_screen.dart';
import 'package:voice_agent/features/pins/presentation/pins_screen.dart';
import 'package:voice_agent/features/plan/presentation/plan_screen.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_screen.dart';
import 'package:voice_agent/features/routines/presentation/routines_screen.dart';
import 'package:voice_agent/features/history/history_screen.dart';
import 'package:voice_agent/features/history/transcript_detail_screen.dart';
import 'package:voice_agent/features/recording/presentation/recording_screen.dart';
import 'package:voice_agent/features/debug/notifications_debug_screen.dart';
import 'package:voice_agent/features/settings/advanced_settings_screen.dart';
import 'package:voice_agent/features/settings/settings_screen.dart';
import 'package:voice_agent/features/usage/presentation/usage_screen.dart';

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
              builder: (context, state) => const PlanScreen(),
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
              builder: (context, state) => const RoutinesScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return RoutineDetailScreen(routineId: id);
                  },
                ),
              ],
            ),
          ],
        ),
        // Branch 4: Chat
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
              builder: (_, _) => const ConversationsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) {
                    final id = state.pathParameters['id']!;
                    return ThreadScreen(conversationId: id);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    // Pins — top-level (full-screen, outside shell) so the saved-references
    // screen is reachable from anywhere: the Record landing screen's app bar
    // and the Chat app bar both push '/pins' (P045 + quick-access).
    GoRoute(
      path: '/pins',
      builder: (context, state) => const PinsScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              PinDetailScreen(recordId: state.pathParameters['id']!),
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
        GoRoute(
          path: 'usage',
          builder: (context, state) => const UsageScreen(),
        ),
        // P040 test-infra: debug screen for inspecting the in-memory
        // notification snapshot + firing a pending notification in 2 s.
        // Route is registered unconditionally; the screen itself
        // guards behavior via `debugNotificationsScreenEnabled` and the
        // Settings entry point is only rendered in debug builds.
        GoRoute(
          path: 'notifications-debug',
          builder: (context, state) => const NotificationsDebugScreen(),
        ),
      ],
    ),
  ],
);
