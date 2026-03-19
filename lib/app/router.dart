import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/app/app_shell_scaffold.dart';
import 'package:voice_agent/features/history/history_screen.dart';
import 'package:voice_agent/features/history/transcript_detail_screen.dart';
import 'package:voice_agent/core/models/transcript_result.dart';
import 'package:voice_agent/features/recording/presentation/recording_screen.dart';
import 'package:voice_agent/features/settings/advanced_settings_screen.dart';
import 'package:voice_agent/features/settings/settings_screen.dart';
import 'package:voice_agent/features/transcript/transcript_review_screen.dart';

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
              builder: (context, state) =>
                  const RecordingScreen(),
              routes: [
                GoRoute(
                  path: 'review',
                  builder: (context, state) {
                    final result = state.extra as TranscriptResult?;
                    if (result == null) {
                      return const _PlaceholderScreen(title: 'Review');
                    }
                    return TranscriptReviewScreen(
                      transcriptResult: result,
                    );
                  },
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
