import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';

class _FakeConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, true, AppThemeEntity.system);
}

WorkoutSession _session(String id, DateTime day, double kg, int reps) =>
    WorkoutSession(
      id: id,
      name: 'Push',
      startedAt: day,
      endedAt: day.add(const Duration(hours: 1)),
      exercises: [
        WorkoutExercise(
          exerciseId: 'bench',
          name: 'Bench',
          muscle: MuscleGroup.chest,
          sets: [SetEntry(weightKg: kg, reps: reps, done: true)],
        ),
      ],
    );

void main() {
  late GymCubit cubit;

  setUp(() async {
    Future<Box<String>> memory(String name) =>
        Hive.openBox<String>(name, bytes: Uint8List(0));
    final repo = GymRepository(
      await memory('ex'),
      await memory('ses'),
      await memory('rou'),
      await memory('meta'),
    );
    // Oldest to newest: 20x10, 20x12 (September), 22.5x8, 22.5x10 (October).
    await repo.saveSession(_session('a', DateTime(2026, 9, 7, 10), 20, 10));
    await repo.saveSession(_session('b', DateTime(2026, 9, 21, 10), 20, 12));
    await repo.saveSession(_session('c', DateTime(2026, 10, 5, 10), 22.5, 8));
    await repo.saveSession(_session('d', DateTime(2026, 10, 19, 10), 22.5, 10));
    cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
  });

  tearDown(() async {
    await cubit.close();
    await Hive.close();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<GymCubit>.value(
        value: cubit,
        child: const MaterialApp(
          home: ExerciseProgressScreen(exerciseId: 'bench', name: 'Bench'),
        ),
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
      tester.getTopLeft(find.textContaining(text).first).dy;

  testWidgets('sorts by newest, oldest, heaviest and most reps', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Workouts (4)'), findsOneWidget);
    // Newest first is the default.
    expect(
      top(tester, 'Heaviest 22.5 kg × 10') < top(tester, 'Heaviest 20 kg × 10'),
      isTrue,
    );

    await choose(tester, 'Sort', 'Oldest first');
    expect(
      top(tester, 'Heaviest 20 kg × 10') < top(tester, 'Heaviest 22.5 kg × 10'),
      isTrue,
    );

    await choose(tester, 'Sort', 'Most reps first');
    // 12 reps comes before 10, which comes before 8.
    expect(
      top(tester, 'Heaviest 20 kg × 12') < top(tester, 'Heaviest 22.5 kg × 10'),
      isTrue,
    );
    expect(
      top(tester, 'Heaviest 22.5 kg × 10') <
          top(tester, 'Heaviest 22.5 kg × 8'),
      isTrue,
    );

    await choose(tester, 'Sort', 'Heaviest first');
    expect(
      top(tester, 'Heaviest 22.5 kg × 10') < top(tester, 'Heaviest 20 kg × 12'),
      isTrue,
    );
  });

  testWidgets('groups by month and by weight, with a count', (tester) async {
    await open(tester);
    await choose(tester, 'Group', 'By month');
    expect(find.text('October 2026 · 2'), findsOneWidget);
    expect(find.text('September 2026 · 2'), findsOneWidget);
    // Newest first, so October leads.
    expect(top(tester, 'October 2026') < top(tester, 'September 2026'), isTrue);

    await choose(tester, 'Group', 'By weight');
    expect(find.text('22.5 kg · 2'), findsOneWidget);
    expect(find.text('20 kg · 2'), findsOneWidget);

    await choose(tester, 'Group', 'No grouping');
    expect(
      find.text('October 2026 · 2'),
      findsNothing,
    ); // no group headers left
  });
}
