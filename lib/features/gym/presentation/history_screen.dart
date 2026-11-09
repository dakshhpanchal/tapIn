import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/history_tiles.dart';
import 'package:opennutritracker/features/gym/presentation/list_tools.dart';
import 'package:opennutritracker/features/gym/presentation/list_prefs.dart';

enum _HistorySort {
  newest('Newest first'),
  oldest('Oldest first'),
  mostSets('Most sets'),
  longest('Longest');

  final String label;
  const _HistorySort(this.label);
}

enum _HistoryGroup {
  none('No grouping'),
  month('By month'),
  workout('By workout');

  final String label;
  const _HistoryGroup(this.label);
}

/// Every finished workout and rest day, with search, sorting and grouping.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _query = '';
  _HistorySort _sort = ListPrefs.restore(
    _HistorySort.values,
    'gym_history_sort',
    _HistorySort.newest,
  );
  _HistoryGroup _group = ListPrefs.restore(
    _HistoryGroup.values,
    'gym_history_group',
    _HistoryGroup.none,
  );

  DateTime _dateOf((WorkoutSession?, String?) e) =>
      e.$1?.startedAt ?? DateTime.parse(e.$2!).add(const Duration(hours: 12));

  /// Entries after search and sort. Rest days have no sets or duration and no
  /// exercise names, so they only show when nothing is searched and the order
  /// is by date.
  List<(WorkoutSession?, String?)> _entries(GymState state) {
    final q = _query.trim().toLowerCase();
    final byDate = _sort == _HistorySort.newest || _sort == _HistorySort.oldest;
    final list = [
      for (final e in historyEntries(state))
        if (e.$1 != null
            ? q.isEmpty ||
                  e.$1!.name.toLowerCase().contains(q) ||
                  e.$1!.exercises.any((x) => x.name.toLowerCase().contains(q))
            : q.isEmpty && byDate)
          e,
    ];
    int newestFirst((WorkoutSession?, String?) a, (WorkoutSession?, String?) b) =>
        _dateOf(b).compareTo(_dateOf(a));
    switch (_sort) {
      case _HistorySort.newest:
        list.sort(newestFirst);
      case _HistorySort.oldest:
        list.sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));
      case _HistorySort.mostSets:
        list.sort((a, b) {
          final c = sessionSetCount(b.$1!).compareTo(sessionSetCount(a.$1!));
          return c != 0 ? c : newestFirst(a, b);
        });
      case _HistorySort.longest:
        list.sort((a, b) {
          final c = b.$1!.duration.compareTo(a.$1!.duration);
          return c != 0 ? c : newestFirst(a, b);
        });
    }
    return list;
  }

  List<Widget> _rows(List<(WorkoutSession?, String?)> entries, bool useLb) {
    Widget tile((WorkoutSession?, String?) e) => e.$1 != null
        ? SessionTile(session: e.$1!, useLb: useLb)
        : RestDayTile(dayKey: e.$2!);
    if (_group == _HistoryGroup.none) return [for (final e in entries) tile(e)];
    final groups = groupInOrder<String, (WorkoutSession?, String?)>(
      entries,
      (e) => _group == _HistoryGroup.month
          ? DateFormat.yMMMM().format(_dateOf(e))
          : (e.$1?.name ?? 'Rest days'),
    );
    return [
      for (final (title, items) in groups) ...[
        GroupHeader(title: title, count: items.length),
        for (final e in items) tile(e),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          OptionMenu<_HistorySort>(
            icon: Icons.sort_rounded,
            tooltip: 'Sort',
            identifier: 'gym-history-sort',
            values: _HistorySort.values,
            labelOf: (v) => v.label,
            selected: _sort,
            onSelected: (v) {
              setState(() => _sort = v);
              ListPrefs.remember('gym_history_sort', v);
            },
          ),
          OptionMenu<_HistoryGroup>(
            icon: Icons.view_agenda_outlined,
            tooltip: 'Group',
            identifier: 'gym-history-group',
            values: _HistoryGroup.values,
            labelOf: (v) => v.label,
            selected: _group,
            onSelected: (v) {
              setState(() => _group = v);
              ListPrefs.remember('gym_history_group', v);
            },
          ),
        ],
      ),
      body: BlocBuilder<GymCubit, GymState>(
        builder: (context, state) {
          final entries = _entries(state);
          final rows = _rows(entries, state.useLb);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Dimens.spacing16,
                ),
                child: ListSearchField(
                  hint: 'Search workouts or exercises',
                  identifier: 'gym-history-search',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          _query.trim().isEmpty
                              ? 'Finished workouts show up here.'
                              : 'No workouts match "${_query.trim()}".',
                          style: TextStyle(color: mutedColor(context)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          Dimens.spacing16,
                          0,
                          Dimens.spacing16,
                          Dimens.spacing32,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (_, i) => rows[i],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
