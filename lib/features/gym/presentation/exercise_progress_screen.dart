import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';

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
          // Plate-based exercises are shown in plates, and have no 1RM or
          // volume (those only mean something in kilograms).
          final plates = state.sessions.any(
            (s) =>
                s.exercises.any((e) => e.exerciseId == exerciseId && e.plates),
          );
          final unit = unitFor(plates: plates, useLb: useLb);
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
          double maxOf(double Function(ExercisePoint) f) =>
              history.map(f).reduce((a, b) => a > b ? a : b);
          final text = Theme.of(context).textTheme;
          final accent = Theme.of(context).colorScheme.primary;
          final spots = [
            for (var i = 0; i < history.length; i++)
              FlSpot(
                i.toDouble(),
                plates
                    ? history[i].bestWeightKg
                    : toDisplayWeight(history[i].oneRepMaxKg, useLb),
              ),
          ];
          final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
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
                    if (!plates) ...[
                      _stat(
                        context,
                        'Est. 1RM',
                        '${weightText(maxOf((p) => p.oneRepMaxKg), useLb)} '
                            '$unit',
                      ),
                      _stat(
                        context,
                        'Best volume',
                        volumeText(maxOf((p) => p.volumeKg), useLb),
                      ),
                    ],
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
                    Text(
                      plates ? 'Heaviest ($unit)' : 'Estimated 1RM ($unit)',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: Dimens.spacing16),
                    SizedBox(
                      height: 160,
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          maxY: maxY * 1.15 + 1,
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipItems: (touched) => [
                                for (final t in touched)
                                  LineTooltipItem(
                                    '${formatWeight(t.y)} · '
                                    '${dateText(history[t.x.toInt()].date)}',
                                    text.labelMedium ?? const TextStyle(),
                                  ),
                              ],
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: history.length > 2,
                              preventCurveOverShooting: true,
                              color: accent,
                              barWidth: 3,
                              dotData: FlDotData(show: history.length <= 12),
                              belowBarData: BarAreaData(
                                show: true,
                                color: accent.withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Dimens.spacing16),
              for (final p in history.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dateText(p.date)),
                  subtitle: Text(
                    'Heaviest ${weightShown(p.bestWeightKg, plates: plates, useLb: useLb)} '
                    '$unit'
                    '${plates ? '' : ' · volume ${volumeText(p.volumeKg, useLb)}'}',
                    style: TextStyle(color: mutedColor(context)),
                  ),
                ),
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
