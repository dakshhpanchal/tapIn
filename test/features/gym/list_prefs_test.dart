import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';
import 'package:opennutritracker/features/gym/presentation/gym_progress_screen.dart';
import 'package:opennutritracker/features/gym/presentation/history_screen.dart';

class _FakeConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, true, AppThemeEntity.system);
}

class _FakeProvider extends Fake implements HiveDBProvider {
  @override
  final Box<String> gymMetaBox;
  _FakeProvider(this.gymMetaBox);
}

WorkoutExercise _ex(String id, String name, double kg, int reps) =>
    WorkoutExercise(
      exerciseId: id,
      name: name,
      muscle: MuscleGroup.chest,
      sets: [SetEntry(weightKg: kg, reps: reps, done: true)],
    );

WorkoutSession _session(
  String id,
  String name,
  DateTime day,
  List<WorkoutExercise> ex,
) => WorkoutSession(
  id: id,
  name: name,
  startedAt: day,
  endedAt: day.add(const Duration(hours: 1)),
  exercises: ex,
);

void main() {
  late GymCubit cubit;

  setUp(() async {
    Future<Box<String>> memory(String name) =>
        Hive.openBox<String>(name, bytes: Uint8List(0));
    final meta = await memory('meta');
    // The same box the lists save their choices in.
    locator.registerSingleton<HiveDBProvider>(_FakeProvider(meta));
    final repo = GymRepository(
      await memory('ex'),
      await memory('ses'),
      await memory('rou'),
      meta,
    );
    for (var i = 0; i < 4; i++) {
      await repo.saveSession(
        _session('a$i', 'Day $i', DateTime(2026, 9, 1 + 7 * i, 10), [
          _ex('e$i', 'Exercise ${String.fromCharCode(68 - i)}', 50.0 + i, 8),
          _ex('bench', 'Bench', 60.0 + i, 8),
        ]),
      );
    }
    cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
  });

  tearDown(() async {
    await cubit.close();
    await Hive.close();
    await GetIt.instance.reset();
  });

  Future<void> open(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(360 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // A fresh route every time, like leaving the screen and coming back.
    await tester.pumpWidget(const SizedBox());
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

  Future<bool> checked(
    WidgetTester tester,
    String tooltip,
    String label,
  ) async {
    final button = find.byTooltip(tooltip);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final item = tester.widget<CheckedPopupMenuItem<Object?>>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem),
      ),
    );
    await tester.tapAt(const Offset(2, 2)); // close the menu
    await tester.pumpAndSettle();
    return item.checked;
  }

  testWidgets('History opens with the sort and group it was left on', (
    tester,
  ) async {
    await open(tester, const HistoryScreen());
    expect(await checked(tester, 'Sort', 'Newest first'), isTrue);
    await choose(tester, 'Sort', 'Oldest first');
    await choose(tester, 'Group', 'By month');

    await open(tester, const HistoryScreen());
    expect(await checked(tester, 'Sort', 'Oldest first'), isTrue);
    expect(await checked(tester, 'Sort', 'Newest first'), isFalse);
    expect(await checked(tester, 'Group', 'By month'), isTrue);
    expect(find.text('September 2026 · 4'), findsOneWidget);
  });

  testWidgets('Strength remembers its sort and group', (tester) async {
    await open(tester, const GymProgressScreen());
    await choose(tester, 'Sort', 'Name A-Z');
    await choose(tester, 'Group', 'By progress');

    await open(tester, const GymProgressScreen());
    expect(await checked(tester, 'Sort', 'Name A-Z'), isTrue);
    expect(await checked(tester, 'Group', 'By progress'), isTrue);
  });

  testWidgets('an exercise list remembers its sort and group', (tester) async {
    await open(
      tester,
      const ExerciseProgressScreen(exerciseId: 'bench', name: 'Bench'),
    );
    await choose(tester, 'Sort', 'Heaviest first');
    await choose(tester, 'Group', 'By weight');

    await open(
      tester,
      const ExerciseProgressScreen(exerciseId: 'bench', name: 'Bench'),
    );
    expect(await checked(tester, 'Sort', 'Heaviest first'), isTrue);
    expect(await checked(tester, 'Group', 'By weight'), isTrue);
  });

  testWidgets('a saved name that no longer exists falls back to the default', (
    tester,
  ) async {
    await locator<HiveDBProvider>().gymMetaBox.put('gym_history_sort', 'gone');
    await open(tester, const HistoryScreen());
    expect(await checked(tester, 'Sort', 'Newest first'), isTrue);
  });
}
