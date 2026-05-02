import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_agent/app/router.dart';
import 'package:voice_agent/core/notifications/come_back_notifier.dart';

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

class _AppState extends State<App> with WidgetsBindingObserver {
  late final _router = createRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        ComeBackNotifier.instance.scheduleComeBack();
      case AppLifecycleState.resumed:
        ComeBackNotifier.instance.cancelComeBack();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDev = appFlavor == 'dev';
    return MaterialApp.router(
      title: isDev ? 'Voice Agent DEV' : 'Voice Agent',
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      theme: ThemeData(
        colorSchemeSeed: isDev ? Colors.orange : Colors.blue,
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
