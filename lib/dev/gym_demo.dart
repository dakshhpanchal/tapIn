import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';

/// Dev-only: eight weeks of a push / pull / legs split with steady progression,
/// so the gym screens have something to show next to the seeded diet data.
Future<void> seedGymDemo() async {
  final repo = locator<GymRepository>();
  await repo.clearAll();

  const bench = Exercise(
    id: 'demo_bench',
    name: 'Bench press',
    muscle: MuscleGroup.chest,
    equipment: 'Barbell',
  );
  const incline = Exercise(
    id: 'demo_incline',
    name: 'Incline dumbbell press',
    muscle: MuscleGroup.chest,
    equipment: 'Dumbbell',
  );
  const ohp = Exercise(
    id: 'demo_ohp',
    name: 'Overhead press',
    muscle: MuscleGroup.shoulders,
    equipment: 'Barbell',
  );
  const pushdown = Exercise(
    id: 'demo_pushdown',
    name: 'Triceps pushdown',
    muscle: MuscleGroup.triceps,
    equipment: 'Cable',
  );
  const row = Exercise(
    id: 'demo_row',
    name: 'Barbell row',
    muscle: MuscleGroup.back,
    equipment: 'Barbell',
  );
  const pullup = Exercise(
    id: 'demo_pullup',
    name: 'Pull-up',
    muscle: MuscleGroup.back,
    kind: ExerciseKind.bodyweight,
  );
  const curl = Exercise(
    id: 'demo_curl',
    name: 'Dumbbell curl',
    muscle: MuscleGroup.biceps,
    equipment: 'Dumbbell',
  );
  const squat = Exercise(
    id: 'demo_squat',
    name: 'Back squat',
    muscle: MuscleGroup.quads,
    equipment: 'Barbell',
  );
  const rdl = Exercise(
    id: 'demo_rdl',
    name: 'Romanian deadlift',
    muscle: MuscleGroup.hamstrings,
    equipment: 'Barbell',
  );
  const legPress = Exercise(
    id: 'demo_legpress',
    name: 'Leg press',
    muscle: MuscleGroup.quads,
    equipment: 'Machine',
  );
  const calf = Exercise(
    id: 'demo_calf',
    name: 'Calf raise',
    muscle: MuscleGroup.calves,
    equipment: 'Machine',
  );
  const all = [
    bench,
    incline,
    ohp,
    pushdown,
    row,
    pullup,
    curl,
    squat,
    rdl,
    legPress,
    calf,
  ];
  for (final e in all) {
    await repo.saveExercise(e);
  }

  // Exercise, starting weight (kg) and the sets x reps to plan.
  final days = <String, List<(Exercise, double, int, int)>>{
    'Push': [
      (bench, 60, 4, 8),
      (incline, 22, 3, 10),
      (ohp, 40, 3, 8),
      (pushdown, 30, 3, 12),
    ],
    'Pull': [(row, 55, 4, 8), (pullup, 0, 3, 8), (curl, 12, 3, 12)],
    'Legs': [
      (squat, 80, 4, 6),
      (rdl, 70, 3, 8),
      (legPress, 140, 3, 12),
      (calf, 60, 4, 15),
    ],
  };
  final names = days.keys.toList();

  var order = 0;
  for (final name in names) {
    await repo.saveRoutine(
      Routine(
        id: 'demo_routine_$name',
        name: name,
        order: order++,
        exercises: [
          for (final (e, kg, sets, reps) in days[name]!)
            WorkoutExercise.of(
              e,
              sets: [
                for (var i = 0; i < sets; i++)
                  SetEntry(weightKg: kg, reps: reps),
              ],
            ),
        ],
      ),
    );
  }

  final today = DateTime.now();
  final restDays = <String>{};
  var split = 0;
  for (var offset = 56; offset >= 1; offset--) {
    final day = DateTime(today.year, today.month, today.day - offset);
    // Train Mon, Tue, Thu, Fri, Sat; Wednesday and Sunday are rest days.
    if (day.weekday == DateTime.wednesday || day.weekday == DateTime.sunday) {
      restDays.add(_key(day));
      continue;
    }
    final name = names[split++ % names.length];
    final week = (56 - offset) ~/ 7;
    final start = day.add(const Duration(hours: 18));
    await repo.saveSession(
      WorkoutSession(
        id: 'demo_session_${_key(day)}',
        name: name,
        startedAt: start,
        endedAt: start.add(Duration(minutes: 55 + (week % 3) * 5)),
        exercises: [
          for (final (e, kg, sets, reps) in days[name]!)
            WorkoutExercise.of(
              e,
              sets: [
                for (var i = 0; i < sets; i++)
                  SetEntry(
                    // About 2.5 kg heavier every other week, a rep dropped on
                    // the last set now and then, as real logs look.
                    weightKg: e.kind == ExerciseKind.bodyweight
                        ? (week >= 4 ? 5 : 0)
                        : kg + (week ~/ 2) * 2.5,
                    reps: reps - (i == sets - 1 && week.isOdd ? 1 : 0),
                    done: true,
                  ),
              ],
            ),
        ],
      ),
    );
  }
  await repo.saveRestDays(restDays);
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
