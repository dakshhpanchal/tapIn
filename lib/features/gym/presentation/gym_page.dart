import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/active_workout_screen.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_picker_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/session_detail_screen.dart';

/// The Gym tab: start or resume a workout, routines, this week's totals, and
/// workout history.
class GymPage extends StatefulWidget {
  const GymPage({super.key});

  @override
  State<GymPage> createState() => _GymPageState();
}

class _GymPageState extends State<GymPage> {
  // A lazy singleton shared with the workout screens, so provide it by value
  // rather than letting BlocProvider close it.
  final GymCubit _cubit = locator<GymCubit>();

  @override
  void initState() {
    super.initState();
    _cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GymCubit>.value(
      value: _cubit,
      child: const _GymView(),
    );
  }
}

class _GymView extends StatelessWidget {
  const _GymView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GymCubit, GymState>(
      builder: (context, state) {
        if (!state.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final cubit = context.read<GymCubit>();
        final text = Theme.of(context).textTheme;
        final weekStart = _startOfWeek(DateTime.now());
        final thisWeek = [
          for (final s in state.sessions)
            if (!s.startedAt.isBefore(weekStart)) s,
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing32,
          ),
          children: [
            if (state.active != null)
              _ActiveCard(session: state.active!)
            else
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start empty workout'),
                onPressed: () async {
                  await cubit.startEmptyWorkout();
                  if (context.mounted) _openActive(context);
                },
              ),
            const SizedBox(height: Dimens.spacing16),
            AppCard(
              padding: const EdgeInsets.all(Dimens.spacing20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This week', style: text.titleMedium),
                  const SizedBox(height: Dimens.spacing12),
                  Wrap(
                    spacing: Dimens.spacing24,
                    runSpacing: Dimens.spacing12,
                    children: [
                      _stat(context, 'Workouts', '${thisWeek.length}'),
                      _stat(
                        context,
                        'Sets',
                        '${thisWeek.fold(0, (n, s) => n + sessionSetCount(s))}',
                      ),
                      _stat(
                        context,
                        'Volume',
                        volumeText(
                          thisWeek.fold(0.0, (n, s) => n + sessionVolume(s)),
                          state.useLb,
                        ),
                      ),
                    ],
                  ),
                  ..._muscleBalance(context, thisWeek),
                ],
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.fitness_center_rounded, size: 18),
                label: const Text('Exercises & progress'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BlocProvider<GymCubit>.value(
                      value: cubit,
                      child: const ExercisePickerScreen(browse: true),
                    ),
                  ),
                ),
              ),
            ),
            if (state.routines.isNotEmpty) ...[
              const SizedBox(height: Dimens.spacing8),
              Text('Routines', style: text.titleMedium),
              const SizedBox(height: Dimens.spacing8),
              for (final r in state.routines)
                _RoutineTile(routine: r, canStart: state.active == null),
            ],
            const SizedBox(height: Dimens.spacing16),
            Text('History', style: text.titleMedium),
            const SizedBox(height: Dimens.spacing8),
            if (state.sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Dimens.spacing24),
                child: Text(
                  'No workouts yet. Start one and it will show up here.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: mutedColor(context)),
                ),
              )
            else
              for (final s in state.sessions)
                _SessionTile(session: s, useLb: state.useLb),
          ],
        );
      },
    );
  }

  static DateTime _startOfWeek(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

  /// Sets per muscle group this week, as thin bars scaled to the largest.
  List<Widget> _muscleBalance(BuildContext context, List<WorkoutSession> week) {
    final counts = setsPerMuscle(week);
    if (counts.isEmpty) return const [];
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    return [
      const SizedBox(height: Dimens.spacing16),
      for (final e in entries.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  e.key.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: e.value / max,
                    minHeight: 8,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${e.value}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
    ];
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
}

void _openActive(BuildContext context) {
  final cubit = context.read<GymCubit>();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider<GymCubit>.value(
        value: cubit,
        child: const ActiveWorkoutScreen(),
      ),
    ),
  );
}

class _ActiveCard extends StatelessWidget {
  final WorkoutSession session;
  const _ActiveCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = session.exercises.fold<int>(
      0,
      (n, e) => n + e.sets.where((s) => s.done).length,
    );
    return AppCard(
      color: scheme.primaryContainer,
      onTap: () => _openActive(context),
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: scheme.onPrimaryContainer),
          const SizedBox(width: Dimens.spacing16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workout in progress',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  '${session.name} · $done sets done',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _openActive(context),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }
}

class _RoutineTile extends StatelessWidget {
  final Routine routine;
  final bool canStart;
  const _RoutineTile({required this.routine, required this.canStart});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GymCubit>();
    final names = routine.exercises.map((e) => e.name).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing16),
        onTap: canStart
            ? () async {
                await cubit.startFromRoutine(routine);
                if (context.mounted) _openActive(context);
              }
            : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    names.isEmpty ? 'No exercises' : names,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: mutedColor(context),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Delete routine',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => cubit.deleteRoutine(routine.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final WorkoutSession session;
  final bool useLb;
  const _SessionTile({required this.session, required this.useLb});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: AppCard(
        padding: const EdgeInsets.all(Dimens.spacing16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BlocProvider<GymCubit>.value(
              value: context.read<GymCubit>(),
              child: SessionDetailScreen(session: session),
            ),
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
              '${formatDuration(session.duration)} · '
              '${volumeText(sessionVolume(session), useLb)} · '
              '${sessionSetCount(session)} sets',
              style: text.bodySmall?.copyWith(color: mutedColor(context)),
            ),
            const SizedBox(height: 2),
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
