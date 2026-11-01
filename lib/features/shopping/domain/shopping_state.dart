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
    required this.view,
    this.filter,
  });

  final ShoppingCatalogue catalogue;
  final List<ShoppingItem> items;
  final ShoppingView view;

  /// A store type id; null for all.
  final String? filter;
}

class ShoppingError extends ShoppingState {
  const ShoppingError({required this.message});
  final String message;
}
