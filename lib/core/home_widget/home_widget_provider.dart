import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/home_widget/home_widget_port.dart';
import 'package:voice_agent/core/home_widget/home_widget_service.dart';
import 'package:voice_agent/core/home_widget/widget_tap_channel.dart';

/// The home-screen widget, Android only (ADR-PLATFORM-015).
final homeWidgetProvider = Provider<HomeWidgetPort>((ref) {
  return Platform.isAndroid ? const HomeWidgetService() : const NoHomeWidget();
});

/// The widget tap that launched the app: read in `app_main.dart` before
/// `runApp`, taken once on the first frame, then null (ADR-PLATFORM-008).
final pendingWidgetTapProvider = StateProvider<WidgetTap?>((ref) => null);

/// Widget taps while the app runs. In production overridden in
/// `app_main.dart`; the default for tests is an empty stream.
final widgetTapStreamProvider = StreamProvider<WidgetTap>((ref) {
  return const Stream<WidgetTap>.empty();
});
