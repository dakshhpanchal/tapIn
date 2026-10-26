import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';

WorkoutExercise _ex(String id, List<SetEntry> sets) => WorkoutExercise(
  exerciseId: id,
  name: id,
  muscle: MuscleGroup.chest,
  sets: sets,
);

SetEntry _set(double kg, int reps, {bool done = true, bool warmup = false}) =>
    SetEntry(weightKg: kg, reps: reps, done: done, warmup: warmup);

WorkoutSession _session(
  String id,
  DateTime start,
  List<WorkoutExercise> exercises, {
  bool finished = true,
}) => WorkoutSession(
  id: id,
  name: id,
  startedAt: start,
  endedAt: finished ? start.add(const Duration(hours: 1)) : null,
  exercises: exercises,
);

void main() {
  test('estimateOneRepMax uses Epley and caps extrapolation at 12 reps', () {
    expect(estimateOneRepMax(100, 1), 100);
    expect(estimateOneRepMax(100, 5), closeTo(116.67, 0.01));
    expect(estimateOneRepMax(100, 30), estimateOneRepMax(100, 12));
    expect(estimateOneRepMax(0, 5), 0);
    expect(estimateOneRepMax(100, 0), 0);
  });

  test('volume counts finished working sets only', () {
    final e = _ex('bench', [
      _set(40, 10, warmup: true),
      _set(60, 10),
      _set(60, 8),
      _set(60, 8, done: false),
    ]);
    expect(exerciseVolume(e), 60 * 10 + 60 * 8);
    expect(bestWeight(e), 60);
    expect(sessionSetCount(_session('s', DateTime(2026), [e])), 2);
  });

  test('exerciseHistory is oldest first and skips unfinished sessions', () {
    final sessions = [
      _session('b', DateTime(2026, 2), [
        _ex('bench', [_set(70, 5)]),
      ]),
      _session('a', DateTime(2026, 1), [
        _ex('bench', [_set(60, 5)]),
      ]),
      _session('open', DateTime(2026, 3), [
        _ex('bench', [_set(90, 5)]),
      ], finished: false),
    ];
    final history = exerciseHistory(sessions, 'bench');
    expect(history.map((p) => p.bestWeightKg), [60, 70]);
  });

  test('lastPerformance returns the newest finished session', () {
    final sessions = [
      _session('old', DateTime(2026, 1), [
        _ex('bench', [_set(60, 5)]),
      ]),
      _session('new', DateTime(2026, 2), [
        _ex('bench', [_set(65, 5)]),
      ]),
    ];
    expect(lastPerformance(sessions, 'bench')!.sets.first.weightKg, 65);
    expect(
      lastPerformance(
        sessions,
        'bench',
        excludeSessionId: 'new',
      )!.sets.first.weightKg,
      60,
    );
    expect(lastPerformance(sessions, 'squat'), isNull);
  });

  test('detectRecords flags new bests but not a first performance', () {
    final before = [
      _session('a', DateTime(2026, 1), [
        _ex('bench', [_set(60, 8)]),
      ]),
    ];
    final first = _session('f', DateTime(2026, 2), [
      _ex('squat', [_set(100, 5)]),
    ]);
    expect(detectRecords(first, before), isEmpty);

    final better = _session('b', DateTime(2026, 2), [
      _ex('bench', [_set(62.5, 8)]),
    ]);
    final records = detectRecords(better, before)['bench']!;
    expect(records, containsAll([RecordKind.weight, RecordKind.oneRepMax]));
    expect(records, contains(RecordKind.volume));

    final worse = _session('w', DateTime(2026, 2), [
      _ex('bench', [_set(50, 8)]),
    ]);
    expect(detectRecords(worse, before), isEmpty);
  });

  test('setsPerMuscle tallies working sets', () {
    final s = _session('s', DateTime(2026), [
      _ex('bench', [_set(60, 5), _set(60, 5)]),
    ]);
    expect(setsPerMuscle([s]), {MuscleGroup.chest: 2});
  });

  test('session JSON round-trips', () {
    final s = _session('s', DateTime(2026, 5, 4, 10), [
      _ex('bench', [_set(60, 5), _set(40, 10, warmup: true, done: false)]),
    ]);
    final back = WorkoutSession.decode(s.encode());
    expect(back.id, 's');
    expect(back.isFinished, isTrue);
    expect(back.exercises.single.sets[1].warmup, isTrue);
    expect(back.exercises.single.sets[0].weightKg, 60);
  });

  test('weight conversion and formatting', () {
    expect(formatWeight(60), '60');
    expect(formatWeight(62.5), '62.5');
    expect(formatWeight(62.25), '62.25');
    expect(lbToKg(kgToLb(80)), closeTo(80, 1e-9));
  });
}
