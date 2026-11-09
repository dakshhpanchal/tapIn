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
import 'package:opennutritracker/features/gym/presentation/session_detail_screen.dart';

class _FakeConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, true, AppThemeEntity.system);
}

WorkoutSession _session(
  String id,
  String name,
  DateTime day,
  double w,
  int reps, {
  bool plates = false,
}) => WorkoutSession(
  id: id,
  name: name,
  startedAt: day,
  endedAt: day.add(const Duration(hours: 1)),
  exercises: [
    WorkoutExercise(
      exerciseId: 'press',
      name: 'Press',
      muscle: MuscleGroup.chest,
      plates: plates,
      sets: [SetEntry(weightKg: w, reps: reps, done: true)],
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
    // Two workouts in kg, then the exercise is switched to plates.
    await repo.saveSession(
      _session('a', 'Day A', DateTime(2026, 9, 1, 10), 60, 8),
    );
    await repo.saveSession(
      _session('b', 'Day B', DateTime(2026, 9, 8, 10), 70, 8),
    );
    await repo.saveSession(
      _session('c', 'Day C', DateTime(2026, 9, 15, 10), 5, 10, plates: true),
    );
    await repo.saveSession(
      _session('d', 'Day D', DateTime(2026, 9, 22, 10), 6, 10, plates: true),
    );
    cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
  });

  tearDown(() async {
    await cubit.close();
    await Hive.close();
  });

  Future<void> open(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
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

  testWidgets('chart and stats use the latest unit; the list keeps each unit', (
    tester,
  ) async {
    await open(
      tester,
      const ExerciseProgressScreen(exerciseId: 'press', name: 'Press'),
    );
    // Latest workouts are in plates, so the readout and the heaviest stat are.
    expect(find.textContaining('6 plates × 10 reps'), findsOneWidget);
    expect(find.text('6 plates'), findsOneWidget);
    // The two kg workouts are explained, and still listed in kg.
    expect(
      find.textContaining('2 earlier workouts were logged in kg'),
      findsOneWidget,
    );
    expect(find.text('Heaviest 70 kg × 8'), findsOneWidget);
    expect(find.text('Heaviest 5 plates × 10'), findsOneWidget);
    expect(find.text('Workouts (4)'), findsOneWidget);
  });

  testWidgets('a list row opens that workout', (tester) async {
    await open(
      tester,
      const ExerciseProgressScreen(exerciseId: 'press', name: 'Press'),
    );
    final row = find.text('Heaviest 70 kg × 8');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(find.text('Day B'), findsWidgets);
  });

  testWidgets('View workout opens the chosen point, the latest by default', (
    tester,
  ) async {
    await open(
      tester,
      const ExerciseProgressScreen(exerciseId: 'press', name: 'Press'),
    );
    await tester.tap(find.text('View workout'));
    await tester.pumpAndSettle();
    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(find.text('Day D'), findsWidgets);
  });

  testWidgets('deleting a workout can be undone from the message', (
    tester,
  ) async {
    final session = cubit.state.sessions.firstWhere((s) => s.id == 'b');
    await open(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionDetailScreen(session: session),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(cubit.state.sessions.any((s) => s.id == 'b'), isFalse);
    expect(find.text('Workout deleted.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(cubit.state.sessions.any((s) => s.id == 'b'), isTrue);
  });
}
