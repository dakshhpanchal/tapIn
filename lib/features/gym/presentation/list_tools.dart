import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// A small icon button that opens a menu of choices, one of them checked.
/// Used for the sort and group choices on the gym lists and for the chart look.
class OptionMenu<T> extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final List<T> values;
  final String Function(T) labelOf;

  /// An optional second line under a choice.
  final String Function(T)? descriptionOf;
  final T selected;
  final ValueChanged<T> onSelected;

  /// A stable name for UI automation.
  final String? identifier;

  const OptionMenu({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
    this.descriptionOf,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final button = PopupMenuButton<T>(
      tooltip: tooltip,
      icon: Icon(icon),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final v in values)
          CheckedPopupMenuItem<T>(
            value: v,
            checked: v == selected,
            child: descriptionOf == null
                ? Text(labelOf(v))
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 230),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(labelOf(v)),
                        Text(
                          descriptionOf!(v),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
          ),
      ],
    );
    return identifier == null
        ? button
        : Semantics(identifier: identifier, child: button);
  }
}

/// A compact search box with a clear button.
class ListSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final String? identifier;
  const ListSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.identifier,
  });

  @override
  State<ListSearchField> createState() => _ListSearchFieldState();
}

class _ListSearchFieldState extends State<ListSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onChanged: (v) {
        setState(() {});
        widget.onChanged(v);
      },
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
    );
    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
      child: field,
    );
    return widget.identifier == null
        ? padded
        : Semantics(identifier: widget.identifier, child: padded);
  }
}

/// Groups [items] by [keyOf], keeping groups in the order their first item
/// appears.
List<(K, List<V>)> groupInOrder<K, V>(Iterable<V> items, K Function(V) keyOf) {
  final groups = <K, List<V>>{};
  for (final item in items) {
    groups.putIfAbsent(keyOf(item), () => []).add(item);
  }
  return [for (final e in groups.entries) (e.key, e.value)];
}

/// A group heading with its count: "October 2026 · 4".
class GroupHeader extends StatelessWidget {
  final String title;
  final int count;
  const GroupHeader({super.key, required this.title, required this.count});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: Dimens.spacing16,
      bottom: Dimens.spacing4,
    ),
    child: Text(
      '$title · $count',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
