import 'dart:async';

import 'package:voice_agent/core/widgets/aurora_background.dart';
import 'package:voice_agent/features/recording/presentation/mic_orb.dart';

/// Runs before every test file. The sky of Aurora (off-roadmap S2) and the
/// living mic (S5) stand still in widget tests, as a loop never lets
/// pumpAndSettle settle; their own tests turn them on for their cases.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AuroraDrift.debugEnabled = false;
  MicOrb.debugAnimate = false;
  await testMain();
}
