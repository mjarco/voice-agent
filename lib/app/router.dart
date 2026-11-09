import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/app_shell_scaffold.dart';
import 'package:voice_agent/core/models/pin.dart';
import 'package:voice_agent/features/agenda/presentation/agenda_screen.dart';
import 'package:voice_agent/features/chat/presentation/conversations_screen.dart';
import 'package:voice_agent/features/chat/presentation/thread_screen.dart';
import 'package:voice_agent/features/matters/presentation/matter_detail_screen.dart';
import 'package:voice_agent/features/matters/presentation/matter_form_screen.dart';
import 'package:voice_agent/features/matters/presentation/matters_screen.dart';
import 'package:voice_agent/features/pins/presentation/pin_detail_screen.dart';
import 'package:voice_agent/features/pins/presentation/pin_form_screen.dart';
import 'package:voice_agent/features/pins/presentation/pins_screen.dart';
import 'package:voice_agent/features/places/presentation/places_screen.dart';
import 'package:voice_agent/features/routines/presentation/routine_detail_screen.dart';
import 'package:voice_agent/features/routines/presentation/routine_form_screen.dart';
import 'package:voice_agent/features/routines/presentation/routines_screen.dart';
import 'package:voice_agent/features/history/history_screen.dart';
import 'package:voice_agent/features/history/transcript_detail_screen.dart';
import 'package:voice_agent/features/recording/presentation/recording_screen.dart';
import 'package:voice_agent/features/debug/notifications_debug_screen.dart';
import 'package:voice_agent/features/location_log/presentation/location_log_screen.dart';
import 'package:voice_agent/features/settings/advanced_settings_screen.dart';
import 'package:voice_agent/features/settings/settings_screen.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_screen.dart';

GoRouter createRouter({String initialLocation = '/record'}) => GoRouter(
  initialLocation: initialLocation,
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
        // Branch 1: Shopping
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/shopping',
              // `?store=diy,garden`: a tap on an arrival alert, already
              // checked by arrivalRoute (ADR-NOTIF-003).
              builder: (context, state) => ShoppingScreen(
                tap: state.extra,
                placeTypes: [
                  for (final t
                      in (state.uri.queryParameters['store'] ?? '').split(','))
                    if (t.isNotEmpty) t,
                ],
              ),
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
                  path: 'new',
                  builder: (context, state) => const RoutineFormScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return RoutineDetailScreen(routineId: id);
                  },
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) => RoutineFormScreen(
                        editId: state.pathParameters['id']!,
                      ),
                    ),
                  ],
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
    // Places — top-level like Pins, reached from the Shopping and Record app
    // bars; a place is named standing there, so it is rare, and not a tab.
    GoRoute(path: '/places', builder: (context, state) => const PlacesScreen()),
    // Matters (ADR-CORE-118 of personal-agent) — top-level like Pins, reached
    // from the same Record and Chat app bars.
    GoRoute(
      path: '/matters',
      builder: (context, state) => const MattersScreen(),
      routes: [
        GoRoute(
          path: 'new',
          builder: (context, state) => const MatterFormScreen(),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              MatterDetailScreen(matterId: state.pathParameters['id']!),
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
          path: 'new',
          builder: (context, state) =>
              PinFormScreen(initialText: state.extra as String?),
        ),
        GoRoute(
          path: ':id',
          builder: (context, state) =>
              PinDetailScreen(recordId: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              // The form edits the pin it is given; without one, the pin's
              // screen is the place to start from.
              redirect: (context, state) => state.extra is PinDetail
                  ? null
                  : '/pins/${state.pathParameters['id']}',
              builder: (context, state) =>
                  PinFormScreen(pin: state.extra! as PinDetail),
            ),
          ],
        ),
      ],
    ),
    // Conversation thread — top-level (outside shell), so a specific thread
    // can be opened from anywhere (e.g. a pin's "open source conversation").
    // The in-shell `/chat/:id` cannot be pushed from outside the shell: pushing
    // it builds the shell at the chat branch's *default* location (the
    // conversations list), dropping the `:id`. This standalone route renders
    // the same full-screen ThreadScreen with a back button to the caller.
    GoRoute(
      path: '/conversation/:id',
      builder: (_, state) =>
          ThreadScreen(conversationId: state.pathParameters['id']!),
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
          path: 'location',
          builder: (context, state) => const LocationLogScreen(),
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
