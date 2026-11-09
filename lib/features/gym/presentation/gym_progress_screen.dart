import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/list_tools.dart';
import 'package:opennutritracker/features/gym/presentation/list_prefs.dart';

/// How training is going over time: how regularly workouts happen, how each
/// exercise has moved since it was first logged, and the latest records.
class GymProgressScreen extends StatelessWidget {
  const GymProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: BlocBuilder<GymCubit, GymState>(
        builder: (context, state) {
          if (state.sessions.isEmpty) {
            return const EmptyHint(
              icon: Icons.show_chart_rounded,
              title: 'No workouts yet',
              subtitle: 'Finish a workout and your progress shows up here.',
            );
          }
          final now = DateTime.now();
          final weeks = workoutsPerWeek(state.sessions, now);
          final gains = exerciseGains(state.sessions, includeSingle: true);
          // The library's name wins, so a renamed exercise reads the same here.
          final names = {for (final e in state.exercises) e.id: e.name};
          final records = recentRecords(state.sessions);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing8,
              Dimens.spacing16,
              Dimens.spacing32,
            ),
            children: [
              _ConsistencyCard(weeks: weeks, total: state.sessions.length),
              const SizedBox(height: Dimens.spacing16),
              _StrengthCard(gains: gains, names: names, useLb: state.useLb),
              if (records.isNotEmpty) ...[
                const SizedBox(height: Dimens.spacing16),
                _RecordsCard(records: records),
              ],
            ],
          );
        },
      ),
    );
  }
}

Widget _stat(BuildContext context, String label, String value) => SizedBox(
  width: 100,
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

class _ConsistencyCard extends StatelessWidget {
  final List<WeekCount> weeks;
  final int total;
  const _ConsistencyCard({required this.weeks, required this.total});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final lastFour = weeks.sublist(weeks.length - 4);
    final perWeek = lastFour.fold(0, (n, w) => n + w.count) / 4;
    final maxCount = weeks.fold(1, (m, w) => w.count > m ? w.count : m);
    final streak = workoutWeekStreak(weeks);
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Consistency', style: text.titleMedium),
          const SizedBox(height: Dimens.spacing12),
          Wrap(
            spacing: Dimens.spacing24,
            runSpacing: Dimens.spacing12,
            children: [
              _stat(context, 'This week', '${weeks.last.count}'),
              _stat(
                context,
                'Per week',
                perWeek == perWeek.roundToDouble()
                    ? '${perWeek.round()}'
                    : perWeek.toStringAsFixed(1),
              ),
              _stat(context, 'Week streak', '$streak'),
              _stat(context, 'Workouts', '$total'),
            ],
          ),
          const SizedBox(height: Dimens.spacing16),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                maxY: maxCount * 1.2,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      '${rod.toY.round()} · week of '
                      '${DateFormat.MMMd().format(weeks[group.x].weekStart)}',
                      text.labelMedium ?? const TextStyle(),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < weeks.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: weeks[i].count.toDouble(),
                          width: 14,
                          color: i == weeks.length - 1
                              ? accent
                              : accent.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          Text(
            'Workouts per week, last ${weeks.length} weeks',
            style: text.bodySmall?.copyWith(color: mutedColor(context)),
          ),
        ],
      ),
    );
  }
}

enum _StrengthSort {
  biggestGain('Biggest gain'),
  name('Name A-Z'),
  mostWorkouts('Most workouts'),
  recent('Recently trained');

  final String label;
  const _StrengthSort(this.label);
}

enum _StrengthGroup {
  none('No grouping'),
  muscle('By muscle group'),
  progress('By progress');

  final String label;
  const _StrengthGroup(this.label);
}

const _statusLabels = {
  GainStatus.improved: 'Improved',
  GainStatus.same: 'Same',
  GainStatus.less: 'Less',
  GainStatus.tooEarly: 'Only one workout',
};

class _StrengthCard extends StatefulWidget {
  final List<ExerciseGain> gains;

  /// Exercise names from the library, by id.
  final Map<String, String> names;
  final bool useLb;
  const _StrengthCard({
    required this.gains,
    required this.names,
    required this.useLb,
  });

  @override
  State<_StrengthCard> createState() => _StrengthCardState();
}

class _StrengthCardState extends State<_StrengthCard> {
  String _query = '';
  _StrengthSort _sort = ListPrefs.restore(
    _StrengthSort.values,
    'gym_strength_sort',
    _StrengthSort.biggestGain,
  );
  _StrengthGroup _group = ListPrefs.restore(
    _StrengthGroup.values,
    'gym_strength_group',
    _StrengthGroup.none,
  );

  String _nameOf(ExerciseGain g) => widget.names[g.id] ?? g.name;

  List<ExerciseGain> get _shown {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final g in widget.gains)
        if (q.isEmpty || _nameOf(g).toLowerCase().contains(q)) g,
    ];
    // `gains` already arrives biggest gain first; the others re-sort it.
    switch (_sort) {
      case _StrengthSort.biggestGain:
        break;
      case _StrengthSort.name:
        list.sort(
          (a, b) => _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase()),
        );
      case _StrengthSort.mostWorkouts:
        list.sort((a, b) {
          final c = b.sessions.compareTo(a.sessions);
          return c != 0
              ? c
              : _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
        });
      case _StrengthSort.recent:
        list.sort((a, b) => b.lastDate.compareTo(a.lastDate));
    }
    return list;
  }

  /// Groups in a fixed, sensible order (muscle list order, or improved first),
  /// leaving out the empty ones; rows keep the chosen sort inside each group.
  List<(String?, List<ExerciseGain>)> _grouped(List<ExerciseGain> shown) {
    switch (_group) {
      case _StrengthGroup.none:
        return [(null, shown)];
      case _StrengthGroup.muscle:
        final by = groupInOrder(shown, (g) => g.muscle);
        return [
          for (final m in MuscleGroup.values)
            for (final (key, items) in by)
              if (key == m) (m.label, items),
        ];
      case _StrengthGroup.progress:
        final by = groupInOrder(shown, gainStatus);
        return [
          for (final st in GainStatus.values)
            for (final (key, items) in by)
              if (key == st) (_statusLabels[st], items),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final shown = _shown;
    // Search and ordering only matter once there is a list to search.
    final showTools = widget.gains.length > 3;
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Strength', style: text.titleMedium)),
              if (showTools) ...[
                OptionMenu<_StrengthSort>(
                  icon: Icons.sort_rounded,
                  tooltip: 'Sort',
                  identifier: 'gym-strength-sort',
                  values: _StrengthSort.values,
                  labelOf: (v) => v.label,
                  selected: _sort,
                  onSelected: (v) {
                    setState(() => _sort = v);
                    ListPrefs.remember('gym_strength_sort', v);
                  },
                ),
                OptionMenu<_StrengthGroup>(
                  icon: Icons.view_agenda_outlined,
                  tooltip: 'Group',
                  identifier: 'gym-strength-group',
                  values: _StrengthGroup.values,
                  labelOf: (v) => v.label,
                  selected: _group,
                  onSelected: (v) {
                    setState(() => _group = v);
                    ListPrefs.remember('gym_strength_group', v);
                  },
                ),
              ],
            ],
          ),
          Text(
            'Your heaviest set, from the first workout to the latest.',
            style: text.bodySmall?.copyWith(color: mutedColor(context)),
          ),
          if (showTools)
            ListSearchField(
              hint: 'Search exercises',
              identifier: 'gym-strength-search',
              onChanged: (v) => setState(() => _query = v),
            ),
          const SizedBox(height: Dimens.spacing8),
          if (widget.gains.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Dimens.spacing12),
              child: Text(
                'Finish a workout to see how your exercises are moving.',
                style: text.bodyMedium?.copyWith(color: mutedColor(context)),
              ),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Dimens.spacing12),
              child: Text(
                'No exercises match "${_query.trim()}".',
                style: text.bodyMedium?.copyWith(color: mutedColor(context)),
              ),
            )
          else
            for (final (title, items) in _grouped(shown)) ...[
              if (title != null) GroupHeader(title: title, count: items.length),
              for (final g in items)
                _GainRow(
                  gain: g,
                  name: _nameOf(g),
                  useLb: widget.useLb,
                  accent: accent,
                ),
            ],
        ],
      ),
    );
  }
}

class _GainRow extends StatelessWidget {
  final ExerciseGain gain;
  final String name;
  final bool useLb;
  final Color accent;
  const _GainRow({
    required this.gain,
    required this.name,
    required this.useLb,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final unit = unitFor(plates: gain.plates, useLb: useLb);
    String shown(double kg) =>
        weightShown(kg, plates: gain.plates, useLb: useLb);
    String setText(TopSet t) => '${shown(t.weightKg)} $unit × ${t.reps}';
    // What changed: a heavier set, or more reps at the same weight.
    final weightDiff = gain.latest.weightKg - gain.first.weightKg;
    final repDiff = gain.latest.reps - gain.first.reps;
    final String change;
    final bool up;
    if (gain.sessions < 2) {
      change = '1 workout';
      up = false;
    } else if (weightDiff > 0) {
      change = '+${shown(weightDiff)} $unit';
      up = true;
    } else if (weightDiff == 0 && repDiff > 0) {
      change = '+$repDiff reps';
      up = true;
    } else if (weightDiff == 0 && repDiff == 0) {
      change = 'Same';
      up = false;
    } else {
      change = weightDiff < 0 ? '−${shown(-weightDiff)} $unit' : '$repDiff reps';
      up = false;
    }
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ExerciseProgressScreen(exerciseId: gain.id, name: name),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  Text(
                    gain.sessions < 2
                        ? setText(gain.latest)
                        : '${setText(gain.first)} → ${setText(gain.latest)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: mutedColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Dimens.spacing12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing12,
                vertical: Dimens.spacing4,
              ),
              decoration: BoxDecoration(
                color: (up ? accent : mutedColor(context)).withValues(
                  alpha: 0.16,
                ),
                borderRadius: BorderRadius.circular(Dimens.radiusL),
              ),
              child: Text(
                change,
                style: text.labelLarge?.copyWith(
                  color: up ? accent : mutedColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsCard extends StatelessWidget {
  final List<RecordEntry> records;
  const _RecordsCard({required this.records});

  static String _kinds(Set<RecordKind> kinds) => [
    if (kinds.contains(RecordKind.weight)) 'Heaviest weight',
    if (kinds.contains(RecordKind.reps)) 'More reps at your heaviest weight',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent records', style: text.titleMedium),
          const SizedBox(height: Dimens.spacing8),
          for (final r in records)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
              child: Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: accent, size: 22),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.exerciseName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall,
                        ),
                        Text(
                          '${_kinds(r.kinds)} · ${dateText(r.date)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: mutedColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
