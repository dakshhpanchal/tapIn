import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';

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
          final gains = exerciseGains(state.sessions);
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
              _StrengthCard(gains: gains, useLb: state.useLb),
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

class _StrengthCard extends StatelessWidget {
  final List<ExerciseGain> gains;
  final bool useLb;
  const _StrengthCard({required this.gains, required this.useLb});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Strength', style: text.titleMedium),
          const SizedBox(height: Dimens.spacing4),
          Text(
            'Your heaviest set, from the first workout to the latest.',
            style: text.bodySmall?.copyWith(color: mutedColor(context)),
          ),
          const SizedBox(height: Dimens.spacing8),
          if (gains.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Dimens.spacing12),
              child: Text(
                'Do an exercise in two workouts to see how it is moving.',
                style: text.bodyMedium?.copyWith(color: mutedColor(context)),
              ),
            )
          else
            for (final g in gains)
              _GainRow(gain: g, useLb: useLb, accent: accent),
        ],
      ),
    );
  }
}

class _GainRow extends StatelessWidget {
  final ExerciseGain gain;
  final bool useLb;
  final Color accent;
  const _GainRow({
    required this.gain,
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
    if (weightDiff > 0) {
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
              ExerciseProgressScreen(exerciseId: gain.id, name: gain.name),
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
                    gain.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  Text(
                    '${setText(gain.first)} → ${setText(gain.latest)}',
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
