import 'package:flutter/material.dart';
import 'package:voice_agent/app/router.dart';

class App extends StatefulWidget {
  const App({super.key, this.scaffoldMessengerKey});

  /// Global key for [ScaffoldMessengerState], used by [Toaster] to show
  /// toasts without a [BuildContext]. Created in `main.dart` and shared
  /// via the [toasterProvider] override in [ProviderScope].
  ///
  /// When null (tests), [MaterialApp] uses its own internal key and
  /// toast functionality is not available.
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final _router = createRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Voice Agent',
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
