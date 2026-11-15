import 'package:flutter/services.dart';

/// Wraps [HapticFeedback.lightImpact] for testability.
///
/// The dispatcher fires a light haptic tap after applying each signal,
/// providing non-visual confirmation for screenless use.
class HapticService {
  /// Triggers a light haptic impact.
  Future<void> lightImpact() => HapticFeedback.lightImpact();

  /// A firmer tap: a held recording has really started.
  Future<void> mediumImpact() => HapticFeedback.mediumImpact();

  /// Two light taps: what was held is sent.
  Future<void> doubleTap() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.lightImpact();
  }
}
