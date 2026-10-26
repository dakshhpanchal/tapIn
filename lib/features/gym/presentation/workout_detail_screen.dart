import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/active_workout_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/workout_editor_screen.dart';

/// What is in a planned workout: its exercises, sets, weights and machine
/// settings. Looking does not start anything; Start is a button at the bottom.
class WorkoutDetailScreen extends StatelessWidget {
  final String routineId;
  const WorkoutDetailScreen({super.key, required this.routineId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GymCubit, GymState>(
      builder: (context, state) {
        final routine = state.routines
            .where((r) => r.id == routineId)
            .firstOrNull;
        // Deleted (or not loaded) while open: nothing left to show.
        if (routine == null) return const Scaffold();
        final text = Theme.of(context).textTheme;
        final inProgress = state.active != null;
        return Scaffold(
          appBar: AppBar(
            title: Text(routine.name),
            actions: [
              IconButton(
                tooltip: 'Edit workout',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkoutEditorScreen(existing: routine),
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing8,
              Dimens.spacing16,
              Dimens.spacing24,
            ),
            children: [
              for (final e in routine.exercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: Dimens.spacing8),
                  child: AppCard(
                    padding: const EdgeInsets.all(Dimens.spacing16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: text.titleSmall),
                        Text(
                          [
                            e.muscle.label,
                            '${e.sets.length} ${e.sets.length == 1 ? 'set' : 'sets'}',
                            if (e.setting.trim().isNotEmpty)
                              'Setting ${e.setting.trim()}',
                          ].join(' · '),
                          style: text.bodySmall?.copyWith(
                            color: mutedColor(context),
                          ),
                        ),
                        const SizedBox(height: Dimens.spacing8),
                        Text(_setsText(e, state.useLb), style: text.bodyMedium),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Dimens.spacing16),
              child: FilledButton.icon(
                icon: Icon(
                  inProgress
                      ? Icons.play_circle_outline_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  inProgress ? 'Resume current workout' : 'Start workout',
                ),
                onPressed: () async {
                  final cubit = context.read<GymCubit>();
                  final navigator = Navigator.of(context);
                  if (!inProgress) await cubit.startFromRoutine(routine);
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ActiveWorkoutScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// "8 · 7 plates" or "40 kg", the planned weight of each set, or nothing
  /// when no weights were planned.
  String _setsText(WorkoutExercise e, bool useLb) {
    final weights = [
      for (final s in e.sets)
        if (s.weightKg > 0)
          weightShown(s.weightKg, plates: e.plates, useLb: useLb),
    ];
    if (weights.isEmpty) return 'No weights planned';
    final unit = unitFor(plates: e.plates, useLb: useLb);
    final allSame = weights.every((w) => w == weights.first);
    return allSame && weights.length == e.sets.length && e.sets.length > 1
        ? '${e.sets.length} × ${weights.first} $unit'
        : '${weights.join(' · ')} $unit';
  }
}
