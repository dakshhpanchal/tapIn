import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/session_detail_screen.dart';

/// Workouts and rest days as one list, newest first: `(session, null)` or
/// `(null, dayKey)`. A rest day on a day you also trained is left out, since
/// the workout says more.
List<(WorkoutSession?, String?)> historyEntries(GymState state) {
  final trained = {
    for (final s in state.sessions) GymCubit.dayKey(s.startedAt),
  };
  final entries = <(DateTime, (WorkoutSession?, String?))>[
    for (final s in state.sessions) (s.startedAt, (s, null)),
    for (final day in state.restDays)
      if (!trained.contains(day))
        (DateTime.parse(day).add(const Duration(hours: 12)), (null, day)),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final e in entries) e.$2];
}

class SessionTile extends StatelessWidget {
  final WorkoutSession session;
  final bool useLb;
  const SessionTile({super.key, required this.session, required this.useLb});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionDetailScreen(session: session),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(session.name, style: text.titleSmall)),
                Text(
                  dateText(session.startedAt),
                  style: text.bodySmall?.copyWith(color: mutedColor(context)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${sessionSetCount(session)} sets',
              style: text.bodySmall?.copyWith(color: mutedColor(context)),
            ),
            Text(
              session.exercises.map((e) => e.name).join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: mutedColor(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class RestDayTile extends StatelessWidget {
  final String dayKey;
  const RestDayTile({super.key, required this.dayKey});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: Dimens.spacing16,
          vertical: Dimens.spacing4,
        ),
        child: Row(
          children: [
            Icon(
              Icons.self_improvement_rounded,
              size: 20,
              color: mutedColor(context),
            ),
            const SizedBox(width: Dimens.spacing12),
            Expanded(child: Text('Rest day', style: text.titleSmall)),
            Text(
              dateText(DateTime.parse(dayKey)),
              style: text.bodySmall?.copyWith(color: mutedColor(context)),
            ),
            IconButton(
              tooltip: 'Remove rest day',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => context.read<GymCubit>().setRestDay(
                DateTime.parse(dayKey),
                false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
