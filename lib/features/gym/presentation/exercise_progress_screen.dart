import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_chart.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/list_tools.dart';
import 'package:opennutritracker/features/gym/presentation/list_prefs.dart';
import 'package:opennutritracker/features/gym/presentation/session_detail_screen.dart';

/// Personal records and a progress chart for one exercise.
class ExerciseProgressScreen extends StatelessWidget {
  final String exerciseId;
  final String name;
  const ExerciseProgressScreen({
    super.key,
    required this.exerciseId,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: BlocBuilder<GymCubit, GymState>(
        builder: (context, state) {
          final history = exerciseHistory(state.sessions, exerciseId);
          final useLb = state.useLb;
          if (history.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing32),
                child: Text(
                  'No finished sets yet. Log this exercise in a workout to see '
                  'your progress here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedColor(context)),
                ),
              ),
            );
          }
          // The chart and stats use the unit the exercise was last logged in
          // (plates or kg/lb). Workouts logged in the other unit stay in the
          // list below, each in its own unit, but cannot share an axis.
          final plates = history.last.plates;
          final unit = unitFor(plates: plates, useLb: useLb);
          final inUnit = [
            for (final p in history)
              if (p.plates == plates) p,
          ];
          final earlier = history.length - inUnit.length;
          double maxOf(double Function(ExercisePoint) f) =>
              inUnit.map(f).reduce((a, b) => a > b ? a : b);
          void openWorkout(String sessionId) {
            final session = state.sessions
                .where((s) => s.id == sessionId)
                .firstOrNull;
            if (session == null) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SessionDetailScreen(session: session),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(Dimens.spacing16),
            children: [
              AppCard(
                padding: const EdgeInsets.all(Dimens.spacing20),
                child: Wrap(
                  spacing: Dimens.spacing24,
                  runSpacing: Dimens.spacing16,
                  children: [
                    _stat(
                      context,
                      'Heaviest',
                      '${weightShown(maxOf((p) => p.bestWeightKg), plates: plates, useLb: useLb)} '
                          '$unit',
                    ),
                    _stat(context, 'Sessions', '${history.length}'),
                  ],
                ),
              ),
              const SizedBox(height: Dimens.spacing16),
              AppCard(
                padding: const EdgeInsets.all(Dimens.spacing20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExerciseProgressChart(
                      key: ValueKey(exerciseId),
                      points: progressPoints(
                        inUnit,
                        plates: plates,
                        useLb: useLb,
                      ),
                      unit: unit,
                      onView: openWorkout,
                    ),
                    if (earlier > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: Dimens.spacing12),
                        child: Text(
                          '$earlier earlier ${earlier == 1 ? 'workout was' : 'workouts were'} '
                          'logged in ${plates ? weightUnitLabel(useLb) : 'plates'}, '
                          'so ${earlier == 1 ? 'it is' : 'they are'} not drawn here. '
                          '${earlier == 1 ? 'It is' : 'They are'} still in the list below.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: mutedColor(context)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Dimens.spacing16),
              _HistoryList(history: history, useLb: useLb, onOpen: openWorkout),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) => SizedBox(
    width: 140,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: mutedColor(context)),
        ),
      ],
    ),
  );
}

enum _Sort {
  newest('Newest first'),
  oldest('Oldest first'),
  heaviest('Heaviest first'),
  mostReps('Most reps first');

  final String label;
  const _Sort(this.label);
}

enum _Group {
  none('No grouping'),
  month('By month'),
  weight('By weight');

  final String label;
  const _Group(this.label);
}

/// Every workout of the exercise, with a way to sort it and to group it by
/// month or by the weight used.
class _HistoryList extends StatefulWidget {
  final List<ExercisePoint> history; // oldest first
  final bool useLb;
  final void Function(String sessionId) onOpen;
  const _HistoryList({
    required this.history,
    required this.useLb,
    required this.onOpen,
  });

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  _Sort _sort = ListPrefs.restore(_Sort.values, 'gym_exercise_sort', _Sort.newest);
  _Group _group = ListPrefs.restore(
    _Group.values,
    'gym_exercise_group',
    _Group.none,
  );

  List<ExercisePoint> get _sorted {
    final list = [...widget.history];
    int byDateDesc(ExercisePoint a, ExercisePoint b) =>
        b.date.compareTo(a.date);
    switch (_sort) {
      case _Sort.newest:
        list.sort(byDateDesc);
      case _Sort.oldest:
        list.sort((a, b) => a.date.compareTo(b.date));
      case _Sort.heaviest:
        list.sort((a, b) {
          final w = b.bestWeightKg.compareTo(a.bestWeightKg);
          return w != 0 ? w : byDateDesc(a, b);
        });
      case _Sort.mostReps:
        list.sort((a, b) {
          final r = b.topReps.compareTo(a.topReps);
          if (r != 0) return r;
          final w = b.bestWeightKg.compareTo(a.bestWeightKg);
          return w != 0 ? w : byDateDesc(a, b);
        });
    }
    return list;
  }

  /// Groups in the order their first workout appears in the sorted list.
  List<(String?, List<ExercisePoint>)> _grouped(List<ExercisePoint> sorted) {
    if (_group == _Group.none) return [(null, sorted)];
    final groups = <String, List<ExercisePoint>>{};
    for (final p in sorted) {
      final key = _group == _Group.month
          ? DateFormat.yMMMM().format(p.date)
          : '${weightShown(p.bestWeightKg, plates: p.plates, useLb: widget.useLb)} '
                '${unitFor(plates: p.plates, useLb: widget.useLb)}';
      groups.putIfAbsent(key, () => []).add(p);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sorted = _sorted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Workouts (${sorted.length})',
                style: text.titleMedium,
              ),
            ),
            OptionMenu<_Sort>(
              icon: Icons.sort_rounded,
              tooltip: 'Sort',
              identifier: 'gym-exercise-sort',
              values: _Sort.values,
              labelOf: (v) => v.label,
              selected: _sort,
              onSelected: (v) {
                setState(() => _sort = v);
                ListPrefs.remember('gym_exercise_sort', v);
              },
            ),
            OptionMenu<_Group>(
              icon: Icons.view_agenda_outlined,
              tooltip: 'Group',
              identifier: 'gym-exercise-group',
              values: _Group.values,
              labelOf: (v) => v.label,
              selected: _group,
              onSelected: (v) {
                setState(() => _group = v);
                ListPrefs.remember('gym_exercise_group', v);
              },
            ),
          ],
        ),
        for (final (title, items) in _grouped(sorted)) ...[
          if (title != null) GroupHeader(title: title, count: items.length),
          for (final p in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(dateText(p.date)),
              subtitle: Text(
                'Heaviest ${weightShown(p.bestWeightKg, plates: p.plates, useLb: widget.useLb)} '
                '${unitFor(plates: p.plates, useLb: widget.useLb)} \u00d7 ${p.topReps}',
                style: TextStyle(color: mutedColor(context)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => widget.onOpen(p.sessionId),
            ),
        ],
      ],
    );
  }
}
