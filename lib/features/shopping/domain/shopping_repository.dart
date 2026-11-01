import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';

sealed class ShoppingException implements Exception {
  String get message;

  @override
  String toString() => message;
}

class ShoppingGeneralException extends ShoppingException {
  ShoppingGeneralException(this.message);
  @override
  final String message;
}

class ShoppingConflictException extends ShoppingException {
  ShoppingConflictException([this.message = 'This item was removed']);
  @override
  final String message;
}

abstract class ShoppingRepository {
  Future<ShoppingCatalogue> fetchCatalogue();
  Future<List<ShoppingItem>> fetchItems(ShoppingView view, {String? storeType});
  Future<ShoppingAddResult> addItem(String text, {List<String> storeTypes});
  Future<void> setTypes(String id, List<String> storeTypes);
  Future<void> markBought(String id, {String? storeType});
  Future<ShoppingItem> restore(String id);
  Future<void> remove(String id);
}
