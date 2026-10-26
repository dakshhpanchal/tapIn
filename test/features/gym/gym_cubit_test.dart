import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';

class _FakeConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    true,
    AppThemeEntity.system,
  );
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

  Future<GymCubit> loaded() async {
    final cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
    return cubit;
  }

  Future<void> logSet(GymCubit c, double kg, int reps) async {
    await c.addSet(0);
    final last = c.state.active!.exercises[0].sets.length - 1;
    await c.updateSet(0, last, (s) => s.copyWith(weightKg: kg, reps: reps, done: true));
  }

  test('seeds the exercise library once', () async {
    final cubit = await loaded();
    final count = cubit.state.exercises.length;
    expect(count, greaterThan(50));
    await cubit.load();
    expect(cubit.state.exercises.length, count);
  });

  test('a workout is saved as it is edited and survives a restart', () async {
    final cubit = await loaded();
    await cubit.startEmptyWorkout();
    await cubit.addExercise(cubit.state.exercises.first);
    expect(repo.getActiveSession()!.exercises, hasLength(1));

    final restarted = await loaded();
    expect(restarted.state.active, isNotNull);
    expect(restarted.state.active!.exercises.single.name,
        cubit.state.exercises.first.name);
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

  test('only custom exercises can be deleted', () async {
    final cubit = await loaded();
    final seeded = cubit.state.exercises.first;
    await cubit.deleteExercise(seeded.id);
    expect(cubit.state.exercises.any((e) => e.id == seeded.id), isTrue);

    final custom = await cubit.createExercise(
      name: 'Zercher Squat',
      muscle: MuscleGroup.quads,
      kind: ExerciseKind.weighted,
    );
    expect(cubit.state.exercises.any((e) => e.id == custom.id), isTrue);
    await cubit.deleteExercise(custom.id);
    expect(cubit.state.exercises.any((e) => e.id == custom.id), isFalse);
  });
}
