import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_agent/features/pins/domain/pin_draft_store.dart';

/// Keeps each draft as one JSON value: drafts are few and small, and they stand
/// apart from the transcript database and its migrations.
class PrefsPinDraftStore implements PinDraftStore {
  static const _newKey = 'pin_draft_new_v1';
  static const _editPrefix = 'pin_draft_edit_v1_';

  String _key(String? recordId) =>
      recordId == null ? _newKey : '$_editPrefix$recordId';

  @override
  Future<PinDraft?> load(String? recordId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(recordId));
    if (raw == null) return null;
    return PinDraft.fromMap(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(String? recordId, PinDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(recordId), jsonEncode(draft.toMap()));
  }

  @override
  Future<void> remove(String? recordId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(recordId));
  }
}
