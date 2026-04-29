import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/local_commands/local_command_matcher.dart';

/// Singleton [LocalCommandMatcher] (stateless, P036).
final localCommandMatcherProvider = Provider<LocalCommandMatcher>((ref) {
  return const LocalCommandMatcher();
});
