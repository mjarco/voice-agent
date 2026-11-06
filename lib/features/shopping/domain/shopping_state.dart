import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';

/// The two lists of the tab. Bought holds the last 7 days.
enum ShoppingView { toBuy, bought }

sealed class ShoppingState {
  const ShoppingState();
}

class ShoppingLoading extends ShoppingState {
  const ShoppingLoading();
}

class ShoppingLoaded extends ShoppingState {
  const ShoppingLoaded({
    required this.catalogue,
    required this.items,
    required this.proposals,
    required this.view,
    this.filter,
    this.placeTypes = const [],
    this.reading = false,
    this.readError,
  });

  final ShoppingCatalogue catalogue;
  final List<ShoppingItem> items;

  /// The waiting proposals, whichever view is shown; only To buy shows them.
  final List<ShoppingProposalRow> proposals;
  final ShoppingView view;

  /// A store type id; null for all.
  final String? filter;

  /// The store types of a place, from an arrival alert's tap (ADR-NOTIF-003):
  /// items under any of them, as the alert counted. Empty unless set, and then
  /// [filter] is null.
  final List<String> placeTypes;

  /// [items] belong to the previous selection and its list is being read, so
  /// they are not shown.
  final bool reading;

  /// The read of a new selection failed; [items] still belong to the previous
  /// one and are not shown.
  final String? readError;
}

class ShoppingError extends ShoppingState {
  const ShoppingError({required this.message});
  final String message;
}
