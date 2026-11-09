import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/matter.dart';
import 'package:voice_agent/features/matters/domain/matters_repository.dart';
import 'package:voice_agent/features/matters/domain/matters_state.dart';

/// One matter with its timeline and links. Every write returns true on
/// success; on failure it records [lastActionError] (the server's message)
/// and returns false, leaving the state as it was.
class MatterDetailNotifier extends StateNotifier<MatterDetailState> {
  MatterDetailNotifier(this._repository, this._id)
      : super(const MatterDetailLoading()) {
    load();
  }

  final MattersRepository _repository;
  final String _id;
  String? lastActionError;

  Future<void> load() async {
    if (state is! MatterDetailLoaded) state = const MatterDetailLoading();
    try {
      final detail = await _repository.fetchMatter(_id);
      if (mounted) state = MatterDetailLoaded(detail: detail);
    } catch (e) {
      if (!mounted) return;
      state = MatterDetailError(
        message: e.toString(),
        gone: e is MatterNotFoundException,
      );
    }
  }

  Future<void> refresh() => load();

  Future<bool> setStatus(MatterStatus status) =>
      _write(() => _repository.editMatter(_id, status: status));

  /// An empty [text] clears the next step.
  Future<bool> setNextStep(String text) =>
      _write(() => _repository.editMatter(_id, nextStep: text));

  /// An empty [text] clears what the matter waits for.
  Future<bool> setWaitingFor(String text) =>
      _write(() => _repository.editMatter(_id, waitingFor: text));

  Future<bool> setKeywords(String text) =>
      _write(() => _repository.editMatter(_id, keywords: text));

  Future<bool> accept(MatterStatus status) =>
      _write(() => _repository.accept(_id, status));

  Future<bool> addEntry(String text) => _change(() => _repository.addEntry(_id, text));

  Future<bool> deleteEntry(String entryId) => _change(() => _repository.deleteEntry(_id, entryId));

  Future<bool> unlink(String linkId) => _change(() => _repository.unlink(_id, linkId));

  /// Drops this proposed matter. The list reads itself again on return.
  Future<bool> drop() => _write(() async {
        await _repository.drop(_id);
        return null;
      });

  /// Deletes this matter. The list reads itself again on return.
  Future<bool> delete() => _write(() async {
        await _repository.deleteMatter(_id);
        return null;
      });

  /// A write whose answer is not the matter: the matter is read again after
  /// it, and a failed read shows on the screen, not as the write's failure.
  Future<bool> _change(Future<void> Function() call) async {
    final ok = await _write(() async {
      await call();
      return null;
    });
    if (ok && mounted) await load();
    return ok;
  }

  Future<bool> _write(Future<MatterDetail?> Function() call) async {
    lastActionError = null;
    try {
      final detail = await call();
      if (detail != null && mounted) {
        state = MatterDetailLoaded(detail: detail);
      }
      return true;
    } catch (e) {
      lastActionError = e is MattersException ? e.message : e.toString();
      return false;
    }
  }
}
