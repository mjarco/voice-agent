import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/sync_status.dart';
import 'package:voice_agent/core/models/transcript_with_status.dart';
import 'package:voice_agent/core/storage/storage_provider.dart';
import 'package:voice_agent/core/storage/storage_service.dart';

class HistoryState {
  const HistoryState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
  });

  final List<TranscriptWithStatus> items;
  final bool isLoading;
  final bool hasMore;
}

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier(this._storage) : super(const HistoryState()) {
    loadNextPage();
  }

  final StorageService _storage;
  static const _pageSize = 20;

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    state = HistoryState(
      items: state.items,
      isLoading: true,
      hasMore: state.hasMore,
    );

    final newItems = await _storage.getTranscriptsWithStatus(
      limit: _pageSize,
      offset: state.items.length,
    );

    state = HistoryState(
      items: [...state.items, ...newItems],
      isLoading: false,
      hasMore: newItems.length == _pageSize,
    );
  }

  Future<void> refresh() async {
    state = const HistoryState();
    await loadNextPage();
  }

  Future<void> deleteItem(String id) async {
    await _storage.deleteTranscript(id);
    state = HistoryState(
      items: state.items.where((i) => i.id != id).toList(),
      hasMore: state.hasMore,
    );
  }

  Future<void> resendItem(String id) async {
    await _storage.reactivateForResend(id);
    // Update the item's status in the list
    state = HistoryState(
      items: state.items.map((i) {
        if (i.id == id) {
          return TranscriptWithStatus(
            id: i.id,
            text: i.text,
            createdAt: i.createdAt,
            status: DisplaySyncStatus.pending,
          );
        }
        return i;
      }).toList(),
      hasMore: state.hasMore,
    );
  }
}

final historyListProvider =
    StateNotifierProvider<HistoryNotifier, HistoryState>((ref) {
  return HistoryNotifier(ref.watch(storageServiceProvider));
});
