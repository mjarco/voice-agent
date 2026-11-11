import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The rule of the top bar (off-roadmap 2026-11-11-va-polish): a tab's bar
/// has its title, the tab's own actions, and then these, the same on every
/// tab: Pins and Settings as icons, always in sight (the owner's word), and
/// a menu with the other screens that live outside the tabs (Miejsca).
class AppBarActions extends StatelessWidget {
  const AppBarActions({super.key});

  /// Route, label, icon of the screens shown as icons, in bar order.
  static const shortcuts = [
    ('/pins', 'Pins', Icons.push_pin_outlined),
    ('/settings', 'Settings', Icons.settings),
  ];

  /// Route, label, icon of the screens in the menu, in menu order.
  static const menu = [('/places', 'Miejsca', Icons.place_outlined)];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (route, label, icon) in shortcuts)
          IconButton(
            key: Key('app-${route.substring(1)}'),
            icon: Icon(icon),
            tooltip: label,
            // Pushed, not gone to: the tab keeps its place under the screen.
            onPressed: () => context.push(route),
          ),
        PopupMenuButton<String>(
          key: const Key('app-menu'),
          tooltip: 'Menu',
          icon: const Icon(Icons.more_vert),
          onSelected: (route) => context.push(route),
          itemBuilder: (_) => [
            for (final (route, label, icon) in menu)
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
        ),
      ],
    );
  }
}
