/// One store type of the catalogue, with its count of items to buy.
class StoreType {
  const StoreType({required this.id, required this.label, required this.count});

  factory StoreType.fromMap(Map<String, dynamic> map) => StoreType(
        id: map['id'] as String,
        label: map['label'] as String,
        count: (map['count'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String label;
  final int count;
}

class ShoppingCatalogue {
  const ShoppingCatalogue({required this.storeTypes, required this.total});

  factory ShoppingCatalogue.fromMap(Map<String, dynamic> map) =>
      ShoppingCatalogue(
        storeTypes: (map['store_types'] as List<dynamic>? ?? const [])
            .map((e) => StoreType.fromMap(e as Map<String, dynamic>))
            .toList(),
        total: (map['total'] as num?)?.toInt() ?? 0,
      );

  final List<StoreType> storeTypes;
  final int total;

  /// The label of [id], or [id] when the catalogue does not hold it.
  String label(String id) {
    for (final type in storeTypes) {
      if (type.id == id) return type.label;
    }
    return id;
  }
}

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.text,
    required this.state,
    required this.storeTypes,
    this.typesSource,
    this.boughtAt,
  });

  factory ShoppingItem.fromMap(Map<String, dynamic> map) => ShoppingItem(
        id: map['id'] as String,
        text: map['text'] as String,
        state: map['state'] as String,
        storeTypes: (map['store_types'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        typesSource: map['types_source'] as String?,
        boughtAt: DateTime.tryParse(map['bought_at'] as String? ?? '')
            ?.toLocal(),
      );

  final String id;
  final String text;
  final String state;
  final List<String> storeTypes;

  /// `model`, `lookup`, `owner` or `failed`; null until the item is tagged.
  final String? typesSource;
  final DateTime? boughtAt;

  bool get isTagging => typesSource == null && storeTypes.isEmpty;
}

/// The saved item, and whether the save created it: an active text returns the
/// existing item.
class ShoppingAddResult {
  const ShoppingAddResult({required this.item, required this.created});

  final ShoppingItem item;
  final bool created;
}
