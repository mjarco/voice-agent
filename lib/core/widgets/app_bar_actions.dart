import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The rule of the top bar (off-roadmap 2026-11-11-va-polish): a tab's bar
/// has its title, the tab's own actions, and then these icons, the same on
/// every tab, for the screens that live outside the tabs. Settings is the
/// last, at the right edge (the owner's word).
class AppBarActions extends StatelessWidget {
  const AppBarActions({super.key, this.onReturn});

  /// Called when the screen an icon opened is closed, for a tab whose content
  /// that screen may have changed (Dziś after Jedzenie).
  final VoidCallback? onReturn;

  /// Route, label, icon; the order the bar shows them, left to right.
  static const entries = [
    ('/diet', 'Jedzenie', Icons.restaurant_outlined),
    ('/places', 'Miejsca', Icons.place_outlined),
    ('/pins', 'Pinezki', Icons.push_pin_outlined),
    ('/settings', 'Ustawienia', Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (route, label, icon) in entries)
          IconButton(
            key: Key('app-${route.substring(1)}'),
            icon: Icon(icon),
            tooltip: label,
            // Pushed, not gone to: the tab keeps its place under the screen.
            onPressed: () async {
              await context.push(route);
              onReturn?.call();
            },
          ),
      ],
    );
  }
}
