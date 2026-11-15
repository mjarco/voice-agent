import 'dart:async';

import 'package:voice_agent/core/widgets/aurora_background.dart';

/// Runs before every test file. The sky of Aurora stands still in widget
/// tests (off-roadmap S2); test/core/widgets/aurora_background_test.dart
/// turns the drift on for its own cases.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AuroraDrift.debugEnabled = false;
  await testMain();
}
