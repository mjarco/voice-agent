import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the API URL has been configured by the user.
///
/// This is a stub that always returns `false` (banner always shown).
/// Proposal 006 (Settings Screen) replaces this with a real provider
/// that reads from SharedPreferences.
final apiUrlConfiguredProvider = Provider<bool>((ref) {
  return false;
});
