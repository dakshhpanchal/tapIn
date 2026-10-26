import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// A sheet to drag [items] into a new order. Returns the old indexes in their
/// new order, or null when nothing changed or the sheet was dismissed.
Future<List<int>?> showReorderSheet(
  BuildContext context, {
  required String title,
  required List<String> items,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReorderSheet(title: title, items: items),
  );
}

class _ReorderSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  const _ReorderSheet({required this.title, required this.items});

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final List<int> _order = List<int>.generate(
    widget.items.length,
    (i) => i,
  );

  bool get _changed {
    for (var i = 0; i < _order.length; i++) {
      if (_order[i] != i) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_changed ? _order : null),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderItem: (from, to) =>
                    setState(() => _order.insert(to, _order.removeAt(from))),
                itemBuilder: (context, position) {
                  final index = _order[position];
                  return ListTile(
                    key: ValueKey('reorder-$index'),
                    title: Text(widget.items[index]),
                    trailing: ReorderableDragStartListener(
                      index: position,
                      child: const Padding(
                        padding: EdgeInsets.all(Dimens.spacing8),
                        child: Icon(Icons.drag_handle_rounded),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
