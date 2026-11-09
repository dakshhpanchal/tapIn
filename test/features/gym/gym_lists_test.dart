import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/gym_page.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_picker_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/history_screen.dart';

class _FakeConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, true, AppThemeEntity.system);
}

WorkoutExercise _ex(
  String id,
  String name,
  MuscleGroup m,
  double kg,
  int reps,
) => WorkoutExercise(
  exerciseId: id,
  name: name,
  muscle: m,
  sets: [SetEntry(weightKg: kg, reps: reps, done: true)],
);

WorkoutSession _session(
  String id,
  String name,
  DateTime day,
  List<WorkoutExercise> exercises,
) => WorkoutSession(
  id: id,
  name: name,
  startedAt: day,
  endedAt: day.add(const Duration(hours: 1)),
  exercises: exercises,
);

void main() {
  late GymRepository repo;
  late GymCubit cubit;

  Future<void> boot() async {
    cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
  }

  setUp(() async {
    Future<Box<String>> memory(String name) =>
        Hive.openBox<String>(name, bytes: Uint8List(0));
    repo = GymRepository(
      await memory('ex'),
      await memory('ses'),
      await memory('rou'),
      await memory('meta'),
    );
  });

  tearDown(() async {
    await cubit.close();
    await Hive.close();
  });

  Future<void> open(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(360 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<GymCubit>.value(
        value: cubit,
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String tooltip, String label) async {
    final button = find.byTooltip(tooltip);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text).first).dy;

  group('Strength', () {
    setUp(() async {
      await repo.saveSession(
        _session('a', 'Mixed', DateTime(2026, 9, 1, 10), [
          _ex('bench', 'Bench press', MuscleGroup.chest, 60, 8),
          _ex('squat', 'Squat', MuscleGroup.quads, 100, 5),
          _ex('row', 'Row', MuscleGroup.back, 50, 10),
          _ex('curl', 'Curl', MuscleGroup.biceps, 20, 10),
        ]),
      );
      await repo.saveSession(
        _session('b', 'Mixed', DateTime(2026, 10, 1, 10), [
          _ex('bench', 'Bench press', MuscleGroup.chest, 70, 8),
          _ex('squat', 'Squat', MuscleGroup.quads, 100, 5),
          _ex('row', 'Row', MuscleGroup.back, 45, 10),
          _ex('curl', 'Curl', MuscleGroup.biceps, 20, 12),
          _ex('ohp', 'Overhead press', MuscleGroup.shoulders, 40, 6),
        ]),
      );
      await boot();
    });

    testWidgets('lists the biggest gain first, one-workout exercises last', (
      tester,
    ) async {
      await open(tester, const GymProgressScreen());
      expect(top(tester, 'Bench press') < top(tester, 'Curl'), isTrue);
      expect(top(tester, 'Curl') < top(tester, 'Squat'), isTrue);
      expect(top(tester, 'Squat') < top(tester, 'Row'), isTrue);
      expect(top(tester, 'Row') < top(tester, 'Overhead press'), isTrue);
      expect(find.text('1 workout'), findsOneWidget);
    });

    testWidgets('searches by name and says when nothing matches', (
      tester,
    ) async {
      await open(tester, const GymProgressScreen());
      // Curl is in the Strength list and, with more reps at the same weight, in
      // the recent records below it.
      expect(find.text('Curl'), findsNWidgets(2));
      await tester.enterText(find.byType(TextField), 'squ');
      await tester.pumpAndSettle();
      expect(find.text('Squat'), findsOneWidget);
      expect(find.text('Curl'), findsOneWidget); // only the records card

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No exercises match "zzz".'), findsOneWidget);
    });

    testWidgets('sorts by name and by most recently trained', (tester) async {
      await open(tester, const GymProgressScreen());
      await choose(tester, 'Sort', 'Name A-Z');
      expect(top(tester, 'Bench press') < top(tester, 'Curl'), isTrue);
      expect(top(tester, 'Curl') < top(tester, 'Overhead press'), isTrue);
      expect(top(tester, 'Overhead press') < top(tester, 'Row'), isTrue);
      expect(top(tester, 'Row') < top(tester, 'Squat'), isTrue);
    });

    testWidgets('groups by muscle group and by progress, with counts', (
      tester,
    ) async {
      await open(tester, const GymProgressScreen());
      await choose(tester, 'Group', 'By muscle group');
      expect(find.text('Chest · 1'), findsOneWidget);
      expect(find.text('Quads · 1'), findsOneWidget);
      expect(find.text('Shoulders · 1'), findsOneWidget);

      await choose(tester, 'Group', 'By progress');
      expect(find.text('Improved · 2'), findsOneWidget);
      expect(find.text('Same · 1'), findsOneWidget);
      expect(find.text('Less · 1'), findsOneWidget);
      expect(find.text('Only one workout · 1'), findsOneWidget);
      // Improved comes before Same, Less and the rest.
      expect(top(tester, 'Improved · 2') < top(tester, 'Same · 1'), isTrue);
    });

    test('gain status and single-workout exercises', () {
      final gains = exerciseGains(cubit.state.sessions, includeSingle: true);
      expect(gains.map((g) => g.id), ['bench', 'curl', 'squat', 'row', 'ohp']);
      expect(gains.map(gainStatus), [
        GainStatus.improved,
        GainStatus.improved,
        GainStatus.same,
        GainStatus.less,
        GainStatus.tooEarly,
      ]);
      // Without the flag only exercises done twice are listed.
      expect(exerciseGains(cubit.state.sessions), hasLength(4));
    });
  });

  group('History', () {
    setUp(() async {
      await repo.saveSession(
        _session('a', 'Push', DateTime(2026, 9, 7, 10), [
          _ex('bench', 'Bench press', MuscleGroup.chest, 60, 8),
        ]),
      );
      await repo.saveSession(
        _session('b', 'Pull', DateTime(2026, 9, 21, 10), [
          _ex('row', 'Row', MuscleGroup.back, 50, 10),
          _ex('curl', 'Curl', MuscleGroup.biceps, 20, 10),
        ]),
      );
      await repo.saveSession(
        _session('c', 'Push', DateTime(2026, 10, 5, 10), [
          _ex('bench', 'Bench press', MuscleGroup.chest, 62.5, 8),
        ]),
      );
      await repo.saveRestDays({'2026-10-03'});
      await boot();
    });

    testWidgets('shows workouts and rest days newest first', (tester) async {
      await open(tester, const HistoryScreen());
      expect(find.text('Rest day'), findsOneWidget);
      // Oct 5 (Push) is above the Oct 3 rest day, which is above Pull.
      expect(top(tester, 'Push') < top(tester, 'Rest day'), isTrue);
      expect(top(tester, 'Rest day') < top(tester, 'Pull'), isTrue);
    });

    testWidgets('searches workout and exercise names and hides rest days', (
      tester,
    ) async {
      await open(tester, const HistoryScreen());
      await tester.enterText(find.byType(TextField), 'curl');
      await tester.pumpAndSettle();
      expect(find.text('Pull'), findsOneWidget);
      expect(find.text('Push'), findsNothing);
      expect(find.text('Rest day'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nothing');
      await tester.pumpAndSettle();
      expect(find.text('No workouts match "nothing".'), findsOneWidget);
    });

    testWidgets('sorts by most sets and groups by month and by workout', (
      tester,
    ) async {
      await open(tester, const HistoryScreen());
      await choose(tester, 'Sort', 'Most sets');
      // Pull has two sets, the Pushes one each; no rest day under this sort.
      expect(find.text('Rest day'), findsNothing);
      expect(top(tester, 'Pull') < top(tester, 'Push'), isTrue);

      await choose(tester, 'Sort', 'Newest first');
      await choose(tester, 'Group', 'By month');
      expect(find.text('October 2026 · 2'), findsOneWidget); // Push + rest day
      expect(find.text('September 2026 · 2'), findsOneWidget);

      await choose(tester, 'Group', 'By workout');
      expect(find.text('Push · 2'), findsOneWidget);
      expect(find.text('Pull · 1'), findsOneWidget);
      expect(find.text('Rest days · 1'), findsOneWidget);
    });
  });

  group('Gym tab history', () {
    testWidgets('shows the latest 10 and opens everything from See all', (
      tester,
    ) async {
      for (var i = 0; i < 12; i++) {
        await repo.saveSession(
          _session('s$i', 'Workout $i', DateTime(2026, 9, 1 + i, 10), [
            _ex(
              'bench',
              'Bench press',
              MuscleGroup.chest,
              60 + i.toDouble(),
              8,
            ),
          ]),
        );
      }
      await boot();
      await open(tester, const GymPage());
      await tester.scrollUntilVisible(
        find.text('See all (12)'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      // Newest ten are on the tab; the two oldest are not.
      expect(find.text('Workout 11'), findsOneWidget);
      expect(find.text('Workout 2'), findsOneWidget);
      expect(find.text('Workout 1'), findsNothing);

      await tester.tap(find.text('See all (12)'));
      await tester.pumpAndSettle();
      expect(find.text('History'), findsWidgets);
      expect(find.text('Workout 0'), findsOneWidget);
    });

    testWidgets('with ten or fewer there is no See all row', (tester) async {
      await repo.saveSession(
        _session('only', 'Push', DateTime(2026, 9, 7, 10), [
          _ex('bench', 'Bench press', MuscleGroup.chest, 60, 8),
        ]),
      );
      await boot();
      await open(tester, const GymPage());
      expect(find.textContaining('See all'), findsNothing);
    });
  });

  group('first visit', () {
    testWidgets('a new user sees how it works, not empty summaries', (
      tester,
    ) async {
      await boot();
      await open(tester, const GymPage());
      expect(find.text('Track your training'), findsOneWidget);
      expect(find.text('Create a workout'), findsOneWidget);
      // The daily rest-day switch is always there; the summaries wait.
      expect(find.text('Rest day today'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
      expect(find.text('Progress'), findsNothing);
      // Both ways to begin are there, side by side, from the start.
      expect(find.text('New workout'), findsOneWidget);
      expect(find.text('Quick workout'), findsOneWidget);
    });

    testWidgets('someone with history keeps the usual cards', (tester) async {
      await repo.saveSession(
        _session('a', 'Push', DateTime(2026, 9, 7, 10), [
          _ex('bench', 'Bench press', MuscleGroup.chest, 60, 8),
        ]),
      );
      await boot();
      await open(tester, const GymPage());
      expect(find.text('Track your training'), findsNothing);
      expect(find.text('Rest day today'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
    });

    testWidgets('Quick workout starts a workout and is off while one runs', (
      tester,
    ) async {
      await boot();
      await open(tester, const GymPage());
      await tester.tap(find.text('Quick workout'));
      await tester.pumpAndSettle();
      expect(cubit.state.active, isNotNull);
    });

    testWidgets('logging a rest day keeps the tab steady', (tester) async {
      await boot();
      await open(tester, const GymPage());
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(cubit.state.restDays, isNotEmpty);
      // Still the first-visit tab, with the switch where it was.
      expect(find.text('Track your training'), findsOneWidget);
      expect(find.text('Rest day today'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(cubit.state.restDays, isEmpty);
      expect(find.text('Rest day today'), findsOneWidget);
    });
  });

  testWidgets('the exercise picker lists recently used first, then A-Z', (
    tester,
  ) async {
    for (final (id, name) in [
      ('a', 'Arnold press'),
      ('b', 'Bench press'),
      ('c', 'Curl'),
      ('d', 'Dips'),
    ]) {
      await repo.saveExercise(
        Exercise(id: id, name: name, muscle: MuscleGroup.chest),
      );
    }
    // Curl was done more recently than Dips; the other two never were.
    await repo.saveSession(
      _session('s1', 'One', DateTime(2026, 9, 1, 10), [
        _ex('d', 'Dips', MuscleGroup.chest, 0, 10),
      ]),
    );
    await repo.saveSession(
      _session('s2', 'Two', DateTime(2026, 10, 1, 10), [
        _ex('c', 'Curl', MuscleGroup.chest, 20, 10),
      ]),
    );
    await boot();
    await open(tester, const ExercisePickerScreen());
    expect(top(tester, 'Curl') < top(tester, 'Dips'), isTrue);
    expect(top(tester, 'Dips') < top(tester, 'Arnold press'), isTrue);
    expect(top(tester, 'Arnold press') < top(tester, 'Bench press'), isTrue);
  });
}
