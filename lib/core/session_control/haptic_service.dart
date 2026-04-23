import 'package:flutter/services.dart';

/// Wraps [HapticFeedback.lightImpact] for testability.
///
/// The dispatcher fires a light haptic tap after applying each signal,
/// providing non-visual confirmation for screenless use.
class HapticService {
  /// Triggers a light haptic impact.
  Future<void> lightImpact() => HapticFeedback.lightImpact();
}
