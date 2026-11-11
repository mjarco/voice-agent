import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voice_agent/core/models/shopping_proposal.dart';
import 'package:voice_agent/core/providers/shopping_list_changes_provider.dart';
import 'package:voice_agent/core/widgets/app_menu_button.dart';
import 'package:voice_agent/core/widgets/shopping_proposal_card.dart';
import 'package:voice_agent/features/shopping/domain/shopping_models.dart';
import 'package:voice_agent/features/shopping/domain/shopping_state.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_notifier.dart';
import 'package:voice_agent/features/shopping/presentation/shopping_providers.dart';

class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key, this.placeTypes = const [], this.tap});

  /// The store types of a place, from `/shopping?store=…`, the route a tap
  /// on an arrival alert opens: selected together.
  final List<String> placeTypes;

  /// New with every tap that opened this route, so a second tap to the same
  /// place selects it again after the chips were changed by hand.
  final Object? tap;

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
    _selectPlace();
  }

  /// The screen lives on in its branch, so a later tap comes here: new types,
  /// or the same ones from a new tap.
  @override
  void didUpdateWidget(ShoppingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.placeTypes, widget.placeTypes) ||
        !identical(oldWidget.tap, widget.tap)) {
      _selectPlace();
    }
  }

  /// After the frame: a provider is not changed while widgets build.
  void _selectPlace() {
    final types = widget.placeTypes;
    if (types.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(shoppingNotifierProvider.notifier).selectPlace(types);
    });
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
    } else if (result.text != null || result.types != null) {
      await _act(
        item.id,
        () => notifier.edit(
          item.id,
          text: result.text,
          storeTypes: result.types,
        ),
      );
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
    ref.listen<int>(shoppingListChangesProvider, (_, _) {
      ref.read(shoppingNotifierProvider.notifier).load();
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping'),
        actions: const [AppMenuButton()],
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
      ShoppingError(message: final message) => _buildError(message, notifier),
      ShoppingLoaded() => _buildLoaded(state, notifier),
    };
  }

  Widget _buildError(String message, ShoppingNotifier notifier) {
    return Center(
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
    );
  }

  Widget _buildLoaded(ShoppingLoaded state, ShoppingNotifier notifier) {
    final toBuy = state.view == ShoppingView.toBuy;
    // Counts are items to buy, so Bought offers every type. The active filter
    // stays after its last item goes.
    final filters = state.catalogue.storeTypes.where(
      (t) =>
          !toBuy ||
          t.count > 0 ||
          t.id == state.filter ||
          state.placeTypes.contains(t.id),
    );
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
              selected: state.filter == null && state.placeTypes.isEmpty,
              onSelected: (_) => notifier.selectFilter(null),
            ),
            for (final type in filters)
              ChoiceChip(
                key: Key('shopping-filter-${type.id}'),
                label: Text(
                  toBuy ? '${type.label} (${type.count})' : type.label,
                ),
                selected: type.id == state.filter ||
                    state.placeTypes.contains(type.id),
                onSelected: (_) => notifier.selectFilter(type.id),
              ),
          ],
        ),
        Expanded(child: _buildList(state, notifier)),
      ],
    );
  }

  Widget _buildList(ShoppingLoaded state, ShoppingNotifier notifier) {
    final readError = state.readError;
    if (readError != null) return _buildError(readError, notifier);
    if (state.reading) {
      return const Center(child: CircularProgressIndicator());
    }
    final toBuy = state.view == ShoppingView.toBuy;
    final proposals = toBuy ? state.proposals : <ShoppingProposalRow>[];
    return RefreshIndicator(
      onRefresh: notifier.load,
      child: state.items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final row in proposals) _buildProposal(row, notifier),
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
              itemCount: proposals.length + state.items.length,
              itemBuilder: (context, index) => index < proposals.length
                  ? _buildProposal(proposals[index], notifier)
                  : _buildItem(
                      state.items[index - proposals.length],
                      state.catalogue,
                      notifier,
                    ),
            ),
    );
  }

  Widget _buildProposal(ShoppingProposalRow row, ShoppingNotifier notifier) {
    final id = row.proposal.id;
    return ShoppingProposalCard(
      key: Key('shopping-proposal-$id'),
      row: row,
      onAccept: () => notifier.answerProposal(id, accept: true),
      onSkip: () => notifier.answerProposal(id, accept: false),
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
  const _ItemSheetResult.edit({this.text, this.types}) : remove = false;
  const _ItemSheetResult.remove()
      : text = null,
        types = null,
        remove = true;

  /// The corrected text, null when it did not change.
  final String? text;

  /// The corrected types, null when they did not change.
  final List<String>? types;
  final bool remove;
}

/// Corrects an item's text and store types; an item to buy can also be
/// removed here.
class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item, required this.catalogue});

  final ShoppingItem item;
  final ShoppingCatalogue catalogue;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final Set<String> _types = widget.item.storeTypes.toSet();
  late final _text = TextEditingController(text: widget.item.text);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  _ItemSheetResult _result() {
    final text = _text.text.trim();
    final typesChanged = !(_types.length == widget.item.storeTypes.length &&
        _types.containsAll(widget.item.storeTypes));
    return _ItemSheetResult.edit(
      text: text == widget.item.text ? null : text,
      types: typesChanged ? _types.toList() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _types.isNotEmpty && _text.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('shopping-edit-text'),
              controller: _text,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Item',
                border: OutlineInputBorder(),
                counterText: '',
              ),
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
                  onPressed: canSave
                      ? () => Navigator.of(context).pop(_result())
                      : null,
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
