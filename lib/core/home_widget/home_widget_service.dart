import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:voice_agent/core/home_widget/home_widget_numbers.dart';
import 'package:voice_agent/core/home_widget/home_widget_port.dart';

/// [HomeWidgetPort] over the `home_widget` plugin, which works in the
/// WorkManager isolate too (a plugin registers in every engine, the app's own
/// channels only in the activity's). The data goes to its SharedPreferences
/// file, which `TodayWidgetProvider.kt` reads.
class HomeWidgetService implements HomeWidgetPort {
  const HomeWidgetService();

  /// The provider's class, `android/.../TodayWidgetProvider.kt`.
  static const androidProvider = 'com.voiceagent.voice_agent.TodayWidgetProvider';

  @override
  Future<void> show(HomeWidgetNumbers numbers) async {
    try {
      for (final e in numbers.toData().entries) {
        await HomeWidget.saveWidgetData<Object>(e.key, e.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: androidProvider);
    } on PlatformException catch (e) {
      developer.log('widget not updated: $e', name: 'HomeWidgetService');
    } on MissingPluginException {
      // No plugin in this engine (a test): nothing to draw.
    }
  }

  @override
  Future<bool> isPlaced() async {
    try {
      final installed = await HomeWidget.getInstalledWidgets();
      return installed.any((w) => w.androidClassName == androidProvider);
    } on PlatformException {
      // Unknown: read anyway, a widget left stale is the worse miss.
      return true;
    } on MissingPluginException {
      return false;
    }
  }
}
