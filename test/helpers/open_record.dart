import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Opens the recording screen over the shell, as Ustawienia → "Nagrywanie i
/// historia" does since ADR-ARCH-013 (the app starts on Dziś). The shell
/// stays under it, so the voice inputs it hosts keep working.
Future<void> openRecord(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  if (bar.evaluate().isEmpty) await tester.pump();
  unawaited(GoRouter.of(tester.element(bar)).push('/record'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
