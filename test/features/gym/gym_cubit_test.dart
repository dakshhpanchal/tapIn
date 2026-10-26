import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/domain/gym_transfer.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';

class _FakeConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, true, AppThemeEntity.system);
}

void main() {
  late Directory dir;
  late GymRepository repo;

  Future<GymRepository> openRepo() async => GymRepository(
    await Hive.openBox<String>('ex'),
    await Hive.openBox<String>('ses'),
    await Hive.openBox<String>('rou'),
    await Hive.openBox<String>('meta'),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gym_cubit_test');
    Hive.init(dir.path);
    repo = await openRepo();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<GymRepository> freshRepo() async => GymRepository(
    await Hive.openBox<String>('ex2'),
    await Hive.openBox<String>('ses2'),
    await Hive.openBox<String>('rou2'),
    await Hive.openBox<String>('meta2'),
  );

  Future<GymCubit> loaded() async {
    final cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
    if (cubit.state.exercises.isEmpty) {
      await cubit.createExercise('Bench Press');
    }
    return cubit;
  }

  Future<void> logSet(GymCubit c, double kg, int reps) async {
    await c.addSet(0);
    final last = c.state.active!.exercises[0].sets.length - 1;
    await c.updateSet(
      0,
      last,
      (s) => s.copyWith(weightKg: kg, reps: reps, done: true),
    );
  }

  test(
    'starts with no built-in exercises and drops ones seeded earlier',
    () async {
      // An earlier build seeded a library with `seed_` ids.
      await repo.saveExercise(
        const Exercise(id: 'seed_1', name: 'Old', muscle: MuscleGroup.chest),
      );
      final cubit = GymCubit(repo, _FakeConfig());
      await cubit.load();
      expect(cubit.state.exercises, isEmpty);
    },
  );

  test('a workout is saved as it is edited and survives a restart', () async {
    final cubit = await loaded();
    await cubit.startEmptyWorkout();
    await cubit.addExercise(cubit.state.exercises.first);
    expect(repo.getActiveSession()!.exercises, hasLength(1));

    final restarted = await loaded();
    expect(restarted.state.active, isNotNull);
    expect(
      restarted.state.active!.exercises.single.name,
      cubit.state.exercises.first.name,
    );
  });

  test('finishing keeps only done sets and stores the session', () async {
    final cubit = await loaded();
    await cubit.startEmptyWorkout();
    await cubit.addExercise(cubit.state.exercises.first);
    // addExercise leaves one empty, unfinished set.
    await logSet(cubit, 60, 8);
    final result = await cubit.finishWorkout();

    expect(result, isNotNull);
    expect(result!.session.exercises.single.sets, hasLength(1));
    expect(cubit.state.active, isNull);
    expect(repo.getActiveSession(), isNull);
    expect(cubit.state.sessions, hasLength(1));
    expect(sessionVolume(cubit.state.sessions.single), 480);
  });

  test('a workout with nothing done is discarded', () async {
    final cubit = await loaded();
    await cubit.startEmptyWorkout();
    await cubit.addExercise(cubit.state.exercises.first);
    expect(await cubit.finishWorkout(), isNull);
    expect(cubit.state.sessions, isEmpty);
    expect(cubit.state.active, isNull);
  });

  test('next workout prefills from last time and flags a record', () async {
    final cubit = await loaded();
    final bench = cubit.state.exercises.first;

    await cubit.startEmptyWorkout();
    await cubit.addExercise(bench);
    await logSet(cubit, 60, 8);
    await cubit.finishWorkout();

    await cubit.startEmptyWorkout();
    await cubit.addExercise(bench);
    final prefilled = cubit.state.active!.exercises.single.sets;
    expect(prefilled.single.weightKg, 60);
    expect(prefilled.single.reps, 8);
    expect(prefilled.single.done, isFalse);

    await cubit.updateSet(0, 0, (s) => s.copyWith(weightKg: 65, done: true));
    final result = await cubit.finishWorkout();
    expect(result!.records[bench.id], contains(RecordKind.weight));
  });

  test('routines start with their exercises and can be deleted', () async {
    final cubit = await loaded();
    await cubit.startEmptyWorkout();
    await cubit.addExercise(cubit.state.exercises.first);
    await logSet(cubit, 50, 10);
    final done = await cubit.finishWorkout();

    await cubit.saveAsRoutine(done!.session, 'Push');
    expect(cubit.state.routines.single.name, 'Push');

    await cubit.startFromRoutine(cubit.state.routines.single);
    expect(cubit.state.active!.name, 'Push');
    expect(cubit.state.active!.exercises, hasLength(1));
    await cubit.discardWorkout();

    await cubit.deleteRoutine(cubit.state.routines.single.id);
    expect(cubit.state.routines, isEmpty);
  });

  test('exercises can be created and deleted', () async {
    final cubit = await loaded();
    final squat = await cubit.createExercise('Squat');
    expect(cubit.state.exercises.any((e) => e.id == squat.id), isTrue);
    await cubit.deleteExercise(squat.id);
    expect(cubit.state.exercises.any((e) => e.id == squat.id), isFalse);
  });

  test('a planned workout starts with its planned sets, prefilled', () async {
    final cubit = await loaded();
    final bench = cubit.state.exercises.first;

    // Plan: 3 sets of bench.
    await cubit.saveRoutine(
      name: 'Push',
      exercises: [
        WorkoutExercise.of(
          bench,
          sets: const [SetEntry(), SetEntry(), SetEntry()],
        ),
      ],
    );
    final planned = cubit.state.routines.single;
    await cubit.startFromRoutine(planned);
    var sets = cubit.state.active!.exercises.single.sets;
    expect(sets, hasLength(3));
    expect(sets.every((s) => !s.done && s.reps == 0), isTrue);

    // Log reps after each set, then finish.
    for (var i = 0; i < 3; i++) {
      await cubit.updateSet(
        0,
        i,
        (s) => s.copyWith(weightKg: 50, reps: 10 - i, done: true),
      );
    }
    await cubit.finishWorkout();

    // Next time the same plan prefills each set from last time.
    await cubit.startFromRoutine(planned);
    sets = cubit.state.active!.exercises.single.sets;
    expect(sets.map((s) => s.reps), [10, 9, 8]);
    expect(sets.every((s) => s.weightKg == 50 && !s.done), isTrue);
    await cubit.discardWorkout();

    // Editing the plan keeps its id.
    await cubit.saveRoutine(
      id: planned.id,
      name: 'Push day',
      exercises: planned.exercises,
    );
    expect(cubit.state.routines, hasLength(1));
    expect(cubit.state.routines.single.name, 'Push day');
  });

  test(
    'the machine setting carries over; the note stays with its workout',
    () async {
      final cubit = await loaded();
      final bench = cubit.state.exercises.first;

      await cubit.startEmptyWorkout();
      await cubit.addExercise(bench);
      await cubit.setExerciseSetting(0, 'Seat 4, pin 7');
      await cubit.setExerciseNote(0, 'Try 62.5 next time');
      await cubit.updateSet(
        0,
        0,
        (s) => s.copyWith(weightKg: 60, reps: 8, done: true),
      );
      final finished = await cubit.finishWorkout();
      expect(finished!.session.exercises.single.note, 'Try 62.5 next time');

      // Next workout: setting prefilled, note box empty, and last time's note is
      // still readable through the history the screen shows.
      await cubit.startEmptyWorkout();
      await cubit.addExercise(bench);
      final next = cubit.state.active!.exercises.single;
      expect(next.setting, 'Seat 4, pin 7');
      expect(next.note, isEmpty);
      expect(
        lastPerformance(cubit.state.sessions, bench.id)!.note,
        'Try 62.5 next time',
      );
      await cubit.discardWorkout();

      // A routine saved from that workout keeps neither the note nor the setting.
      await cubit.saveAsRoutine(finished.session, 'Chest');
      final routine = cubit.state.routines.single.exercises.single;
      expect(routine.note, isEmpty);
      expect(routine.setting, isEmpty);
    },
  );

  test(
    'importing a workouts file fills the app; export gives it back',
    () async {
      final cubit = GymCubit(repo, _FakeConfig());
      await cubit.load();

      final plan = await cubit.importJson(gymImportExample);
      expect(plan.warnings, isEmpty);
      expect(cubit.state.routines.single.name, 'Push Day');
      expect(cubit.state.sessions.single.exercises.single.name, 'Bench Press');
      expect(
        cubit.state.exercises.map((e) => e.name),
        containsAll(['Bench Press', 'Pec Deck', 'Overhead Press']),
      );

      // Same file again: nothing new.
      final again = await cubit.importJson(gymImportExample);
      expect(again.sessions, isEmpty);
      expect(again.newExercises, isEmpty);
      expect(cubit.state.sessions, hasLength(1));
      expect(cubit.state.routines, hasLength(1));

      // The imported workout can be started and prefills from imported history.
      await cubit.startFromRoutine(cubit.state.routines.single);
      final bench = cubit.state.active!.exercises.firstWhere(
        (e) => e.name == 'Bench Press',
      );
      expect(bench.sets.first.weightKg, 60);
      expect(bench.setting, 'Flat Bench');
      await cubit.discardWorkout();

      // Export is a file this same import accepts.
      final restored = GymCubit(await freshRepo(), _FakeConfig());
      await restored.load();
      await restored.importJson(cubit.exportJson());
      expect(restored.state.routines.single.name, 'Push Day');
      expect(restored.state.sessions, hasLength(1));
    },
  );

  test(
    'a real plates-and-settings plan (UPPER / LOWER) imports and starts',
    () async {
      final cubit = GymCubit(repo, _FakeConfig());
      await cubit.load();
      final raw = File(
        'test/features/gym/fixtures/upper_lower.json',
      ).readAsStringSync();

      final plan = await cubit.importJson(raw);
      expect(plan.warnings, isEmpty);
      expect(cubit.state.routines.map((r) => r.name).toSet(), {
        'Upper',
        'Lower',
      });
      final upper = cubit.state.routines.firstWhere((r) => r.name == 'Upper');
      final lower = cubit.state.routines.firstWhere((r) => r.name == 'Lower');
      expect(upper.exercises, hasLength(14));
      expect(lower.exercises, hasLength(7));
      // 'x 2' on lateral raises etc: sets counted from the weights given.
      expect(upper.exercises.fold<int>(0, (n, e) => n + e.sets.length), 18);

      WorkoutExercise find(Routine r, String name) =>
          r.exercises.firstWhere((e) => e.name == name);

      // Plates vs kg, per-set weights, and the machine setting.
      final laterals = find(upper, 'Lateral Raises');
      expect(laterals.plates, isTrue);
      expect(laterals.setting, '10');
      expect(laterals.sets.map((s) => s.weightKg), [5, 5]);
      expect(find(upper, 'Tbar Rowing').plates, isFalse);
      expect(find(upper, 'Smith Incline Press').sets.single.weightKg, 22.5);
      final legExt = find(lower, 'Single Leg Extension');
      expect(legExt.sets.map((s) => s.weightKg), [8, 7]);
      expect(legExt.setting, '0 1 3');
      expect(find(lower, 'Leg Curls').setting, '0 1/2');
      expect(find(lower, 'Calves').plates, isFalse);
      expect(find(lower, 'Adductors').plates, isTrue);

      // Starting UPPER gives the planned sets, weights and settings, no reps yet.
      await cubit.startFromRoutine(upper);
      final active = cubit.state.active!;
      final legSets = active.exercises.firstWhere((e) => e.name == 'Peck Deck');
      expect(legSets.plates, isTrue);
      expect(legSets.setting, '0');
      expect(legSets.sets.map((s) => s.weightKg), [18, 18]);
      expect(
        active.exercises.every(
          (e) => e.sets.every((s) => s.reps == 0 && !s.done),
        ),
        isTrue,
      );

      // Log reps on a plates exercise: it counts as a set but not as kg volume.
      final idx = active.exercises.indexWhere((e) => e.name == 'Peck Deck');
      await cubit.updateSet(idx, 0, (s) => s.copyWith(reps: 10, done: true));
      final done = await cubit.finishWorkout();
      expect(sessionSetCount(done!.session), 1);
      expect(sessionVolume(done.session), 0);

      // The exported file keeps plates and settings.
      final back = GymCubit(await freshRepo(), _FakeConfig());
      await back.load();
      await back.importJson(cubit.exportJson());
      final restored = back.state.routines
          .firstWhere((r) => r.name == 'Lower')
          .exercises
          .firstWhere((e) => e.name == 'Single Leg Extension');
      expect(restored.plates, isTrue);
      expect(restored.setting, '0 1 3');
      expect(restored.sets.map((s) => s.weightKg), [8, 7]);
    },
  );

  test('plate weights are not converted to lb', () {
    expect(weightShown(8, plates: true, useLb: true), '8');
    expect(weightStored(8, plates: true, useLb: true), 8);
    expect(weightShown(100, plates: false, useLb: true), '220.46');
    expect(unitFor(plates: true, useLb: true), 'plates');
  });

  test('workouts keep file order on import and can be reordered', () async {
    final cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
    final raw = File(
      'test/features/gym/fixtures/upper_lower.json',
    ).readAsStringSync();
    await cubit.importJson(raw);
    // File order (UPPER, LOWER), not alphabetical.
    expect(cubit.state.routines.map((r) => r.name), ['Upper', 'Lower']);

    await cubit.reorderRoutines([...cubit.state.routines.reversed]);
    expect(cubit.state.routines.map((r) => r.name), ['Lower', 'Upper']);

    // The order survives a restart, and a new workout goes last.
    await cubit.saveRoutine(
      name: 'ARMS',
      exercises: [WorkoutExercise.of(await cubit.createExercise('Curl'))],
    );
    final restarted = GymCubit(repo, _FakeConfig());
    await restarted.load();
    expect(restarted.state.routines.map((r) => r.name), [
      'Lower',
      'Upper',
      'ARMS',
    ]);

    // Editing a workout does not move it.
    final upper = restarted.state.routines.firstWhere((r) => r.name == 'Upper');
    await restarted.saveRoutine(
      id: upper.id,
      name: 'Upper',
      exercises: upper.exercises,
    );
    expect(restarted.state.routines.map((r) => r.name), [
      'Lower',
      'Upper',
      'ARMS',
    ]);
  });

  test('exercises of the workout in progress can be reordered', () async {
    final cubit = await loaded();
    final bench = cubit.state.exercises.first;
    final squat = await cubit.createExercise('Squat');
    final row = await cubit.createExercise('Row');
    await cubit.startEmptyWorkout();
    for (final e in [bench, squat, row]) {
      await cubit.addExercise(e);
    }
    await cubit.reorderExercises([2, 0, 1]);
    expect(cubit.state.active!.exercises.map((e) => e.name), [
      'Row',
      'Bench Press',
      'Squat',
    ]);
    expect(repo.getActiveSession()!.exercises.first.name, 'Row');
  });

  test('importing the Title Case file over an earlier lowercase import fixes it, '
      'without duplicates', () async {
    final cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
    // What an earlier import left behind: lowercase names, no muscle groups.
    await cubit.importJson(
      '{"workouts":[{"name":"UPPER","exercises":['
      '{"exercise":"tbar rowing","sets":[{"weight":40,"reps":0}]},'
      '{"exercise":"peck deck","plates":true,"sets":[{"weight":18,"reps":0}]}]}]}',
    );
    final oldIds = {for (final e in cubit.state.exercises) e.name: e.id};
    final oldRoutineId = cubit.state.routines.single.id;
    expect(
      cubit.state.exercises.every((e) => e.muscle == MuscleGroup.fullBody),
      isTrue,
    );

    final raw = File(
      'test/features/gym/fixtures/upper_lower.json',
    ).readAsStringSync();
    final plan = await cubit.importJson(raw);

    // The two exercises were updated in place; the rest are new.
    expect(
      plan.updatedExercises.map((e) => e.name),
      containsAll(['Tbar Rowing', 'Peck Deck']),
    );
    final byName = {for (final e in cubit.state.exercises) e.name: e};
    expect(byName.containsKey('tbar rowing'), isFalse);
    expect(byName['Tbar Rowing']!.id, oldIds['tbar rowing']);
    expect(byName['Tbar Rowing']!.muscle, MuscleGroup.back);
    expect(byName['Peck Deck']!.id, oldIds['peck deck']);
    expect(byName['Peck Deck']!.muscle, MuscleGroup.chest);
    expect(byName['Peck Deck']!.plates, isTrue);
    expect(
      cubit.state.exercises,
      hasLength(21),
    ); // 14 upper + 7 lower, no duplicates

    // The workout was replaced in place, and its name follows the file.
    expect(cubit.state.routines.map((r) => r.name), ['Upper', 'Lower']);
    expect(cubit.state.routines.first.id, oldRoutineId);
    expect(cubit.state.routines.first.exercises.first.name, 'Tbar Rowing');
  });

  test('a skipped exercise stays out of the finished workout', () async {
    final cubit = await loaded();
    final bench = cubit.state.exercises.first;
    final squat = await cubit.createExercise('Squat');
    await cubit.startEmptyWorkout();
    await cubit.addExercise(bench);
    await cubit.addExercise(squat);
    await cubit.updateSet(
      0,
      0,
      (s) => s.copyWith(weightKg: 60, reps: 8, done: true),
    );
    await cubit.updateSet(
      1,
      0,
      (s) => s.copyWith(weightKg: 80, reps: 5, done: true),
    );

    // Skip squat even though a set was ticked, then change your mind, then skip.
    await cubit.setExerciseSkipped(1, true);
    expect(cubit.state.active!.exercises[1].skipped, isTrue);
    expect(repo.getActiveSession()!.exercises[1].skipped, isTrue);
    await cubit.setExerciseSkipped(1, false);
    expect(cubit.state.active!.exercises[1].skipped, isFalse);
    await cubit.setExerciseSkipped(1, true);

    final done = await cubit.finishWorkout();
    expect(done!.session.exercises.map((e) => e.name), ['Bench Press']);
    expect(cubit.state.sessions.single.exercises, hasLength(1));
  });

  test('a workout where everything is skipped is discarded', () async {
    final cubit = await loaded();
    await cubit.startEmptyWorkout();
    await cubit.addExercise(cubit.state.exercises.first);
    await cubit.updateSet(
      0,
      0,
      (s) => s.copyWith(weightKg: 60, reps: 8, done: true),
    );
    await cubit.setExerciseSkipped(0, true);
    expect(await cubit.finishWorkout(), isNull);
    expect(cubit.state.sessions, isEmpty);
  });
}
