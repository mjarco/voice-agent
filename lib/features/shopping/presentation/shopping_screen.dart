import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_notifier.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_providers.dart';

class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final Set<String> _newTypes = {};
  final Set<String> _busyIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // A failed save keeps the text in the field: writes need a connection.
  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    final notifier = ref.read(shoppingNotifierProvider.notifier);
    final outcome = await notifier.add(text, storeTypes: _newTypes.toList());
    if (!mounted) return;
    setState(() => _saving = false);
    if (outcome == ShoppingAddOutcome.failed) {
      _say('Not saved: ${notifier.lastActionError ?? 'try again'}');
      return;
    }
    _text.clear();
    setState(_newTypes.clear);
    _focus.requestFocus();
    if (outcome == ShoppingAddOutcome.alreadyOnList) {
      _say('Already on the list');
    } else if (outcome == ShoppingAddOutcome.addedNotShown) {
      _say('Added, not shown in this view');
    }
  }

  Future<void> _act(String id, Future<bool> Function() action) async {
    setState(() => _busyIds.add(id));
    final success = await action();
    if (!mounted) return;
    setState(() => _busyIds.remove(id));
    if (!success) {
      final notifier = ref.read(shoppingNotifierProvider.notifier);
      _say(notifier.lastActionError ?? 'Failed');
    }
  }

  Future<void> _openItem(ShoppingItem item, ShoppingCatalogue catalogue) async {
    final notifier = ref.read(shoppingNotifierProvider.notifier);
    final result = await showModalBottomSheet<_ItemSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemSheet(item: item, catalogue: catalogue),
    );
    if (result == null || !mounted) return;
    if (result.remove) {
      final confirmed = await _confirmRemove(item);
      if (confirmed && mounted) {
        await _act(item.id, () => notifier.remove(item.id));
      }
    } else {
      await _act(item.id, () => notifier.setTypes(item.id, result.types));
    }
  }

  Future<bool> _confirmRemove(ShoppingItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from the list?'),
        content: Text(item.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('shopping-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shoppingNotifierProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildForm(),
          if (state is ShoppingLoaded && _text.text.trim().isNotEmpty)
            _buildNewTypes(state.catalogue),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('shopping-text'),
              controller: _text,
              focusNode: _focus,
              maxLength: 200,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                hintText: 'Add an item',
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('shopping-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildNewTypes(ShoppingCatalogue catalogue) {
    return _ChipRow(
      children: [
        for (final type in catalogue.storeTypes)
          FilterChip(
            key: Key('shopping-new-type-${type.id}'),
            label: Text(type.label),
            selected: _newTypes.contains(type.id),
            onSelected: (selected) => setState(() {
              selected ? _newTypes.add(type.id) : _newTypes.remove(type.id);
            }),
          ),
      ],
    );
  }

  Widget _buildBody(ShoppingState state) {
    final notifier = ref.read(shoppingNotifierProvider.notifier);
    return switch (state) {
      ShoppingLoading() => const Center(child: CircularProgressIndicator()),
      ShoppingError(message: final message) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: notifier.retry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ShoppingLoaded() => _buildLoaded(state, notifier),
    };
  }

  Widget _buildLoaded(ShoppingLoaded state, ShoppingNotifier notifier) {
    final toBuy = state.view == ShoppingView.toBuy;
    // Counts are items to buy, so Bought offers every type. The active filter
    // stays after its last item goes.
    final filters = state.catalogue.storeTypes
        .where((t) => !toBuy || t.count > 0 || t.id == state.filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SegmentedButton<ShoppingView>(
            segments: const [
              ButtonSegment(value: ShoppingView.toBuy, label: Text('To buy')),
              ButtonSegment(value: ShoppingView.bought, label: Text('Bought')),
            ],
            selected: {state.view},
            onSelectionChanged: (s) => notifier.selectView(s.first),
          ),
        ),
        _ChipRow(
          children: [
            ChoiceChip(
              key: const Key('shopping-filter-all'),
              label: Text(toBuy ? 'All (${state.catalogue.total})' : 'All'),
              selected: state.filter == null,
              onSelected: (_) => notifier.selectFilter(null),
            ),
            for (final type in filters)
              ChoiceChip(
                key: Key('shopping-filter-${type.id}'),
                label: Text(
                  toBuy ? '${type.label} (${type.count})' : type.label,
                ),
                selected: type.id == state.filter,
                onSelected: (_) => notifier.selectFilter(type.id),
              ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: notifier.load,
            child: state.items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          toBuy
                              ? 'Nothing to buy.'
                              : 'Nothing bought in the last 7 days.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: state.items.length,
                    itemBuilder: (context, index) => _buildItem(
                      state.items[index],
                      state.catalogue,
                      notifier,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(
    ShoppingItem item,
    ShoppingCatalogue catalogue,
    ShoppingNotifier notifier,
  ) {
    final busy = _busyIds.contains(item.id);
    final bought = item.state == 'bought';
    return ListTile(
      key: Key('shopping-item-${item.id}'),
      onTap: () => _openItem(item, catalogue),
      leading: bought
          ? null
          : IconButton(
              key: Key('shopping-bought-${item.id}'),
              tooltip: 'Bought',
              icon: const Icon(Icons.check_box_outline_blank),
              onPressed: busy
                  ? null
                  : () => _act(item.id, () => notifier.markBought(item.id)),
            ),
      title: Text(item.text),
      subtitle: _ItemTypes(item: item, catalogue: catalogue),
      trailing: bought
          ? TextButton(
              key: Key('shopping-restore-${item.id}'),
              onPressed: busy
                  ? null
                  : () => _act(item.id, () => notifier.restore(item.id)),
              child: const Text('Back to the list'),
            )
          : null,
    );
  }
}

/// A row of chips that scrolls sideways.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final chip in children)
            Padding(padding: const EdgeInsets.only(right: 6), child: chip),
        ],
      ),
    );
  }
}

class _ItemTypes extends StatelessWidget {
  const _ItemTypes({required this.item, required this.catalogue});

  final ShoppingItem item;
  final ShoppingCatalogue catalogue;

  @override
  Widget build(BuildContext context) {
    if (item.isTagging) {
      return const Text(
        'tagging…',
        style: TextStyle(fontStyle: FontStyle.italic),
      );
    }
    // An item with no types counts under "other", as the failed tag does.
    final types = item.storeTypes.isEmpty ? const ['other'] : item.storeTypes;
    final labels = types.map(catalogue.label).join(', ');
    final bought = item.boughtAt;
    if (bought == null) return Text(labels);
    final date = '${bought.day.toString().padLeft(2, '0')}.'
        '${bought.month.toString().padLeft(2, '0')}';
    return Text('$labels · bought $date');
  }
}

class _ItemSheetResult {
  const _ItemSheetResult.types(this.types) : remove = false;
  const _ItemSheetResult.remove()
      : types = const [],
        remove = true;

  final List<String> types;
  final bool remove;
}

/// Corrects an item's store types; an item to buy can also be removed here.
class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item, required this.catalogue});

  final ShoppingItem item;
  final ShoppingCatalogue catalogue;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final Set<String> _types = widget.item.storeTypes.toSet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item.text,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final type in widget.catalogue.storeTypes)
                  FilterChip(
                    key: Key('shopping-edit-type-${type.id}'),
                    label: Text(type.label),
                    selected: _types.contains(type.id),
                    onSelected: (selected) => setState(() {
                      selected ? _types.add(type.id) : _types.remove(type.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.item.state != 'bought')
                  TextButton(
                    key: const Key('shopping-remove'),
                    onPressed: () => Navigator.of(context)
                        .pop(const _ItemSheetResult.remove()),
                    child: const Text('Remove'),
                  ),
                const Spacer(),
                FilledButton(
                  key: const Key('shopping-edit-save'),
                  onPressed: _types.isEmpty
                      ? null
                      : () => Navigator.of(context)
                          .pop(_ItemSheetResult.types(_types.toList())),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
