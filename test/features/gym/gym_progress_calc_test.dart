import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';

WorkoutSession _session(String id, DateTime day, double kg, {int reps = 5}) =>
    WorkoutSession(
      id: id,
      name: 'Push',
      startedAt: day,
      endedAt: day.add(const Duration(hours: 1)),
      exercises: [
        WorkoutExercise(
          exerciseId: 'bench',
          name: 'Bench press',
          muscle: MuscleGroup.chest,
          sets: [SetEntry(weightKg: kg, reps: reps, done: true)],
        ),
      ],
    );

void main() {
  // A Wednesday, so "this week" starts Monday the 12th.
  final now = DateTime(2026, 10, 14, 12);

  test('workouts are counted per week, oldest first, ending this week', () {
    final weeks = workoutsPerWeek([
      _session('a', DateTime(2026, 10, 13), 60), // this week
      _session('b', DateTime(2026, 10, 14), 60), // this week
      _session('c', DateTime(2026, 10, 6), 60), // last week
    ], now, weeks: 4);
    expect(weeks.map((w) => w.count), [0, 0, 1, 2]);
    expect(weeks.last.weekStart, DateTime(2026, 10, 12));
  });

  test('the streak is not broken by a week that has just begun', () {
    final weeks = workoutsPerWeek([
      _session('a', DateTime(2026, 10, 6), 60),
      _session('b', DateTime(2026, 9, 29), 60),
    ], now, weeks: 4);
    expect(weeks.last.count, 0);
    expect(workoutWeekStreak(weeks), 2);
  });

  test('an exercise done twice shows its gain from first to latest', () {
    final gains = exerciseGains([
      _session('a', DateTime(2026, 9, 1), 60),
      _session('b', DateTime(2026, 10, 1), 70),
    ]);
    expect(gains, hasLength(1));
    expect(gains.single.name, 'Bench press');
    expect(gains.single.first, (weightKg: 60.0, reps: 5));
    expect(gains.single.latest, (weightKg: 70.0, reps: 5));
    expect(gains.single.sessions, 2);
  });

  test('more reps at the same weight also counts as progress', () {
    final gains = exerciseGains([
      _session('a', DateTime(2026, 9, 1), 60, reps: 5),
      _session('b', DateTime(2026, 10, 1), 60, reps: 8),
    ]);
    expect(gains.single.first.weightKg, gains.single.latest.weightKg);
    expect(gains.single.latest.reps - gains.single.first.reps, 3);
  });

  test('the top set is the heaviest weight, with the most reps at it', () {
    final e = WorkoutExercise(
      exerciseId: 'x',
      name: 'X',
      muscle: MuscleGroup.back,
      sets: const [
        SetEntry(weightKg: 50, reps: 12, done: true),
        SetEntry(weightKg: 60, reps: 6, done: true),
        SetEntry(weightKg: 60, reps: 8, done: true),
        SetEntry(weightKg: 70, reps: 3, done: true, warmup: true),
      ],
    );
    expect(topSet(e), (weightKg: 60.0, reps: 8));
  });

  test('an exercise done only once has nothing to compare yet', () {
    expect(exerciseGains([_session('a', DateTime(2026, 9, 1), 60)]), isEmpty);
  });

  test('records are found only when a past best is beaten', () {
    final records = recentRecords([
      _session('a', DateTime(2026, 9, 1), 60),
      _session('b', DateTime(2026, 10, 1), 70),
    ]);
    expect(records, hasLength(1));
    expect(records.single.date, DateTime(2026, 10, 1));
    expect(records.single.kinds, contains(RecordKind.weight));
    expect(records.single.kinds, isNot(contains(RecordKind.volume)));
  });
}
