import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_repository.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';

ShoppingItem sampleItem({
  String id = 'i1',
  String text = 'kabel HDMI',
  String state = 'to_buy',
  List<String> storeTypes = const ['electrical'],
  String? typesSource = 'model',
  DateTime? boughtAt,
}) =>
    ShoppingItem(
      id: id,
      text: text,
      state: state,
      storeTypes: storeTypes,
      typesSource: typesSource,
      boughtAt: boughtAt,
    );

const sampleCatalogue = ShoppingCatalogue(
  storeTypes: [
    StoreType(id: 'grocery', label: 'Spożywczy', count: 0),
    StoreType(id: 'electrical', label: 'Elektryczny', count: 1),
    StoreType(id: 'other', label: 'Inne', count: 0),
  ],
  total: 1,
);

class FakeShoppingRepository implements ShoppingRepository {
  ShoppingCatalogue catalogue = sampleCatalogue;
  List<ShoppingItem> toBuy = [sampleItem()];
  List<ShoppingItem> bought = [];

  ShoppingAddResult? nextAdd;
  ShoppingItem? nextRestore;
  Exception? nextReadError;
  Exception? nextWriteError;

  int reads = 0;
  ShoppingView? lastView;
  String? lastStoreType;
  String? lastAddText;
  List<String>? lastAddTypes;
  String? lastBoughtId;
  String? lastBoughtStoreType;
  String? lastRemovedId;
  String? lastRestoredId;
  String? lastSetTypesId;
  List<String>? lastSetTypes;

  void _failIfAsked() {
    final error = nextWriteError;
    if (error != null) throw error;
  }

  @override
  Future<ShoppingCatalogue> fetchCatalogue() async {
    final error = nextReadError;
    if (error != null) throw error;
    return catalogue;
  }

  @override
  Future<List<ShoppingItem>> fetchItems(
    ShoppingView view, {
    String? storeType,
  }) async {
    reads++;
    lastView = view;
    lastStoreType = storeType;
    final items = view == ShoppingView.toBuy ? toBuy : bought;
    if (storeType == null) return items;
    return items.where((i) => i.storeTypes.contains(storeType)).toList();
  }

  @override
  Future<ShoppingAddResult> addItem(
    String text, {
    List<String> storeTypes = const [],
  }) async {
    _failIfAsked();
    lastAddText = text;
    lastAddTypes = storeTypes;
    return nextAdd ??
        ShoppingAddResult(
          item: sampleItem(
            id: 'new',
            text: text,
            storeTypes: storeTypes,
            typesSource: storeTypes.isEmpty ? null : 'owner',
          ),
          created: true,
        );
  }

  @override
  Future<void> setTypes(String id, List<String> storeTypes) async {
    _failIfAsked();
    lastSetTypesId = id;
    lastSetTypes = storeTypes;
  }

  @override
  Future<void> markBought(String id, {String? storeType}) async {
    _failIfAsked();
    lastBoughtId = id;
    lastBoughtStoreType = storeType;
  }

  @override
  Future<ShoppingItem> restore(String id) async {
    _failIfAsked();
    lastRestoredId = id;
    return nextRestore ?? sampleItem(id: id);
  }

  @override
  Future<void> remove(String id) async {
    _failIfAsked();
    lastRemovedId = id;
  }
}
