import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';

/// Shown right after a workout is finished: the totals and any records set.
class WorkoutSummaryScreen extends StatelessWidget {
  final FinishedWorkout finished;
  const WorkoutSummaryScreen({super.key, required this.finished});

  static String _recordText(Set<RecordKind> kinds) => [
    if (kinds.contains(RecordKind.weight)) 'Heaviest weight',
    if (kinds.contains(RecordKind.oneRepMax)) 'Est. 1RM',
    if (kinds.contains(RecordKind.volume)) 'Volume',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final session = finished.session;
    final useLb = context.read<GymCubit>().state.useLb;
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout complete')),
      body: ListView(
        padding: const EdgeInsets.all(Dimens.spacing16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(Dimens.spacing20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.name, style: text.titleLarge),
                const SizedBox(height: Dimens.spacing4),
                Text(
                  dateText(session.startedAt),
                  style: text.bodyMedium?.copyWith(color: mutedColor(context)),
                ),
                const SizedBox(height: Dimens.spacing16),
                Wrap(
                  spacing: Dimens.spacing24,
                  runSpacing: Dimens.spacing12,
                  children: [
                    _stat(context, 'Time', formatDuration(session.duration)),
                    _stat(
                      context,
                      'Volume',
                      volumeText(sessionVolume(session), useLb),
                    ),
                    _stat(context, 'Sets', '${sessionSetCount(session)}'),
                    _stat(context, 'Exercises', '${session.exercises.length}'),
                  ],
                ),
              ],
            ),
          ),
          if (finished.records.isNotEmpty) ...[
            const SizedBox(height: Dimens.spacing16),
            AppCard(
              padding: const EdgeInsets.all(Dimens.spacing20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.emoji_events_rounded, color: accent),
                      const SizedBox(width: Dimens.spacing8),
                      Text('New records', style: text.titleMedium),
                    ],
                  ),
                  const SizedBox(height: Dimens.spacing12),
                  for (final e in session.exercises)
                    if (finished.records[e.exerciseId] case final kinds?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Dimens.spacing8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.name, style: text.titleSmall),
                            Text(
                              _recordText(kinds),
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
          const SizedBox(height: Dimens.spacing24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) => SizedBox(
    width: 130,
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
