import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/workout_live_update.dart';

class _FakeConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, true, AppThemeEntity.system);
}

WorkoutExercise _ex(String name, List<bool> done, {bool skipped = false}) =>
    WorkoutExercise(
      exerciseId: name,
      name: name,
      muscle: MuscleGroup.chest,
      skipped: skipped,
      sets: [for (final d in done) SetEntry(weightKg: 50, reps: 8, done: d)],
    );

WorkoutSession _session(List<WorkoutExercise> exercises) => WorkoutSession(
  id: 's',
  name: 'Push day',
  startedAt: DateTime(2026, 11, 11, 7, 30),
  exercises: exercises,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the notification says', () {
    test('names the exercise and set you are up to', () {
      final s = summarizeWorkout(
        _session([
          _ex('Bench press', [true, true, false]),
          _ex('Row', [false, false]),
        ]),
      );
      expect(s.title, 'Push day');
      expect(s.text, 'Bench press · set 3 of 3');
      expect(s.doneSets, 2);
      expect(s.totalSets, 5);
      expect(s.segments, [3, 2]);
    });

    test('moves on to the next exercise once one is finished', () {
      final s = summarizeWorkout(
        _session([
          _ex('Bench press', [true, true, true]),
          _ex('Row', [true, false]),
        ]),
      );
      expect(s.text, 'Row · set 2 of 2');
      expect(s.doneSets, 4);
    });

    test('a set ticked out of order does not hide the one still to do', () {
      final s = summarizeWorkout(
        _session([
          _ex('Bench press', [false, true, true]),
        ]),
      );
      expect(s.text, 'Bench press · set 1 of 3');
    });

    test('leaves out skipped exercises, like the workout screen', () {
      final s = summarizeWorkout(
        _session([
          _ex('Bench press', [true], skipped: true),
          _ex('Row', [false, false]),
        ]),
      );
      expect(s.text, 'Row · set 1 of 2');
      expect(s.totalSets, 2);
      expect(s.doneSets, 0);
      expect(s.segments, [2]);
    });

    test('says so when everything is done', () {
      final s = summarizeWorkout(
        _session([
          _ex('Row', [true, true]),
        ]),
      );
      expect(s.text, 'All sets done. Finish when you are ready.');
      expect(s.doneSets, s.totalSets);
    });

    test('an empty workout asks for an exercise', () {
      final s = summarizeWorkout(_session(const []));
      expect(s.text, 'Add an exercise to start logging');
      expect(s.totalSets, 0);
      expect(s.segments, isEmpty);
    });

    test('the clock alone never changes the key', () {
      final a = summarizeWorkout(
        _session([
          _ex('Row', [false]),
        ]),
      );
      final b = summarizeWorkout(
        _session([
          _ex('Row', [false]),
        ]),
      );
      expect(a.key, b.key);
      final c = summarizeWorkout(
        _session([
          _ex('Row', [true]),
        ]),
      );
      expect(a.key, isNot(c.key));
    });
  });

  group('posting it', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.tapin.app/workout_live'),
            (call) async {
              calls.add(call);
              if (call.method == 'areNotificationsEnabled') return true;
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.tapin.app/workout_live'),
            null,
          );
    });

    List<MethodCall> shown() => [
      for (final c in calls)
        if (c.method == 'show') c,
    ];

    test('shows the workout with its start time and progress', () async {
      final live = WorkoutLiveUpdate();
      await live.sync(
        _session([
          _ex('Bench press', [true, false]),
        ]),
      );
      final args = shown().single.arguments as Map;
      expect(args['title'], 'Push day');
      expect(args['text'], 'Bench press · set 2 of 2');
      expect(args['doneSets'], 1);
      expect(args['totalSets'], 2);
      expect(args['segments'], [2]);
      expect(
        args['startedAtMillis'],
        DateTime(2026, 11, 11, 7, 30).millisecondsSinceEpoch,
      );
    });

    test('posts again only when something visible changed', () async {
      final live = WorkoutLiveUpdate();
      final session = _session([
        _ex('Row', [false, false]),
      ]);
      await live.sync(session);
      await live.sync(session);
      expect(shown(), hasLength(1));

      await live.sync(
        _session([
          _ex('Row', [true, false]),
        ]),
      );
      expect(shown(), hasLength(2));
    });

    test('removes it when the workout ends, once', () async {
      final live = WorkoutLiveUpdate();
      await live.sync(
        _session([
          _ex('Row', [false]),
        ]),
      );
      await live.sync(null);
      await live.sync(null);
      expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
    });

    test('clears a leftover one when the app opens with no workout', () async {
      final live = WorkoutLiveUpdate();
      await live.sync(null);
      expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
      expect(shown(), isEmpty);
    });

    test('a failing native side never breaks the workout', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.tapin.app/workout_live'),
            (call) async => throw PlatformException(code: 'nope'),
          );
      final live = WorkoutLiveUpdate();
      await live.sync(
        _session([
          _ex('Row', [false]),
        ]),
      );
      await live.sync(null);
    });
  });

  group('from the cubit', () {
    late GymCubit cubit;
    late List<WorkoutSession?> seen;

    setUp(() async {
      seen = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.tapin.app/workout_live'),
            (call) async {
              if (call.method == 'areNotificationsEnabled') return true;
              seen.add(null);
              return null;
            },
          );
      Future<Box<String>> memory(String name) =>
          Hive.openBox<String>(name, bytes: Uint8List(0));
      final repo = GymRepository(
        await memory('ex'),
        await memory('ses'),
        await memory('rou'),
        await memory('meta'),
      );
      cubit = GymCubit(repo, _FakeConfig(), liveUpdate: WorkoutLiveUpdate());
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.tapin.app/workout_live'),
            null,
          );
      await cubit.close();
      await Hive.close();
    });

    test('nothing is posted before the workout has been read', () async {
      // Constructing the cubit and listening must not look like "no workout".
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
    });

    test('starting, ticking and finishing drive the notification', () async {
      await cubit.load(); // no workout stored: clears anything stale
      expect(seen, hasLength(1));

      final bench = await cubit.createExercise('Bench press');
      await cubit.startEmptyWorkout();
      await cubit.addExercise(bench);
      await Future<void>.delayed(Duration.zero);
      final afterStart = seen.length;
      expect(afterStart, greaterThan(1));

      await cubit.updateSet(0, 0, (s) => s.copyWith(done: true, reps: 5));
      await Future<void>.delayed(Duration.zero);
      expect(seen.length, greaterThan(afterStart));

      await cubit.discardWorkout();
      await Future<void>.delayed(Duration.zero);
      // The last call removed it.
      expect(cubit.state.active, isNull);
    });
  });
}
