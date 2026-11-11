import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The rule of the top bar (off-roadmap 2026-11-11-va-polish): a tab's bar
/// has its title, the tab's own actions, and then this menu, the same on
/// every tab, with the screens that live outside the tabs.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  /// Route, label, icon; the order the menu shows them.
  static const entries = [
    ('/places', 'Miejsca', Icons.place_outlined),
    ('/pins', 'Pins', Icons.push_pin_outlined),
    ('/settings', 'Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('app-menu'),
      tooltip: 'Menu',
      icon: const Icon(Icons.more_vert),
      // Pushed, not gone to: the tab keeps its place under the screen.
      onSelected: (route) => context.push(route),
      itemBuilder: (_) => [
        for (final (route, label, icon) in entries)
          PopupMenuItem<String>(
            key: Key('app-menu-${route.substring(1)}'),
            value: route,
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Text(label),
              ],
            ),
          ),
      ],
    );
  }
}
