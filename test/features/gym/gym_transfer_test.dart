import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/domain/gym_transfer.dart';

int _n = 0;
String _id() => 'id${_n++}';

GymImportPlan _parse(
  String json, {
  List<Exercise> exercises = const [],
  List<Routine> routines = const [],
  List<WorkoutSession> sessions = const [],
}) => parseGymImport(
  json,
  exercises: exercises,
  routines: routines,
  sessions: sessions,
  newId: _id,
);

void main() {
  setUp(() => _n = 0);

  test(
    'the bundled example imports: exercises are created from their names',
    () {
      final plan = _parse(gymImportExample);
      expect(plan.workouts.single.name, 'Push Day');
      expect(plan.workouts.single.exercises.map((e) => e.sets.length), [
        3,
        2,
        1,
      ]);
      expect(
        plan.newExercises.map((e) => e.name),
        containsAll(['Bench Press', 'Pec Deck', 'Overhead Press']),
      );
      // Plates, machine setting and per-set weights come through.
      final pecDeck = plan.workouts.single.exercises[1];
      expect(pecDeck.plates, isTrue);
      expect(pecDeck.setting, 'Seat 3');
      expect(pecDeck.sets.map((s) => s.weightKg), [18, 18]);
      expect(
        plan.newExercises.firstWhere((e) => e.name == 'Pec Deck').plates,
        isTrue,
      );
      expect(plan.workouts.single.exercises[0].plates, isFalse);
      final session = plan.sessions.single;
      expect(session.isFinished, isTrue);
      expect(session.duration.inMinutes, 55);
      final bench = session.exercises.single;
      expect(bench.setting, 'Flat Bench');
      expect(bench.sets.map((s) => s.reps), [8, 7]);
      expect(bench.sets.every((s) => s.done), isTrue);
      expect(plan.warnings, isEmpty);
    },
  );

  test('existing exercises are matched by name, ignoring case and spacing', () {
    const bench = Exercise(
      id: 'b',
      name: 'Bench Press',
      muscle: MuscleGroup.chest,
    );
    final plan = _parse(
      '{"workouts":[{"name":"A","exercises":[{"exercise":"  bench   PRESS "}]}]}',
      exercises: [bench],
    );
    expect(plan.newExercises, isEmpty);
    expect(plan.workouts.single.exercises.single.exerciseId, 'b');
  });

  test('declared muscles are used, by name or label', () {
    final plan = _parse(
      '{"exercises":[{"name":"Squat","muscle":"Quads"},{"name":"Plank","muscle":"full body"}]}',
    );
    final muscles = {for (final e in plan.newExercises) e.name: e.muscle};
    expect(muscles['Squat'], MuscleGroup.quads);
    expect(muscles['Plank'], MuscleGroup.fullBody);
  });

  test('a workout with the same name replaces it and keeps its id', () {
    final old = Routine(id: 'keep', name: 'push day', exercises: const []);
    final plan = _parse(
      '{"workouts":[{"name":"Push Day","exercises":["Bench Press"]}]}',
      routines: [old],
    );
    expect(plan.workouts.single.id, 'keep');
    expect(plan.workoutsUpdated, 1);
  });

  test('importing history twice does not duplicate it', () {
    final first = _parse(gymImportExample);
    final again = _parse(
      gymImportExample,
      exercises: first.newExercises,
      sessions: first.sessions,
    );
    expect(again.sessions, isEmpty);
    expect(again.sessionsSkipped, 1);
  });

  test('bad entries are skipped with a reason, the rest still import', () {
    final plan = _parse('''{
      "workouts":[{"exercises":["x"]},{"name":"Empty","exercises":[]},
                  {"name":"Good","exercises":["Row"]}],
      "history":[{"name":"No date","exercises":[]},
                 {"date":"2026-01-02T10:00:00","exercises":[{"exercise":"Row","sets":[{"weight":50,"reps":0}]}]}]
    }''');
    expect(plan.workouts.map((w) => w.name), ['Good']);
    expect(plan.sessions, isEmpty);
    expect(plan.warnings, hasLength(4));
  });

  test('files that are not workouts fail with a readable message', () {
    expect(() => _parse('not json'), throwsA(isA<GymImportException>()));
    expect(() => _parse('[1,2]'), throwsA(isA<GymImportException>()));
    expect(
      () => _parse('{"format":"something-else"}'),
      throwsA(isA<GymImportException>()),
    );
    expect(() => _parse('{"version":99}'), throwsA(isA<GymImportException>()));
  });

  test('export then import round-trips planned workouts and history', () {
    final source = _parse(gymImportExample);
    final json = exportGymJson(
      exercises: source.newExercises,
      routines: source.workouts,
      sessions: source.sessions,
    );
    final back = parseGymImport(
      json,
      exercises: const [],
      routines: const [],
      sessions: const [],
      newId: _id,
    );
    expect(back.workouts.single.name, 'Push Day');
    expect(back.workouts.single.exercises.map((e) => e.name), [
      'Bench Press',
      'Pec Deck',
      'Overhead Press',
    ]);
    final backPecDeck = back.workouts.single.exercises[1];
    expect(backPecDeck.plates, isTrue);
    expect(backPecDeck.setting, 'Seat 3');
    expect(back.sessions.single.startedAt, source.sessions.single.startedAt);
    expect(back.sessions.single.exercises.single.sets.map((s) => s.weightKg), [
      60,
      60,
    ]);
    expect(back.sessions.single.exercises.single.setting, 'Flat Bench');
    expect(back.warnings, isEmpty);
  });

  test('a note on a workout exercise is kept as its plan note, both ways', () {
    final plan = _parse(
      '{"workouts":[{"name":"A","exercises":['
      '{"exercise":"Row","note":"Pull to the hip","setting":"Seat 3",'
      '"sets":[{"weight":30,"reps":0}]}]}]}',
    );
    final row = plan.workouts.single.exercises.single;
    expect(row.planNote, 'Pull to the hip');
    expect(row.note, isEmpty); // not the note for next time
    expect(row.setting, 'Seat 3');

    final json = exportGymJson(
      exercises: plan.newExercises,
      routines: plan.workouts,
      sessions: const [],
    );
    expect(json, contains('"note": "Pull to the hip"'));
    final back = parseGymImport(
      json,
      exercises: const [],
      routines: const [],
      sessions: const [],
      newId: _id,
    );
    expect(back.workouts.single.exercises.single.planNote, 'Pull to the hip');
  });
}
