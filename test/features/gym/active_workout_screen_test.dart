import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/presentation/active_workout_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_cubit.dart';

class _FakeConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, true, AppThemeEntity.system);
}

void main() {
  late GymCubit cubit;

  setUp(() async {
    // In-memory boxes: file I/O never completes under the widget-test clock.
    Future<Box<String>> memory(String name) =>
        Hive.openBox<String>(name, bytes: Uint8List(0));
    final repo = GymRepository(
      await memory('ex'),
      await memory('ses'),
      await memory('rou'),
      await memory('meta'),
    );
    cubit = GymCubit(repo, _FakeConfig());
    await cubit.load();
    await cubit.startEmptyWorkout();
    await cubit.addExercise(cubit.state.exercises.first);
  });

  tearDown(() async {
    await cubit.close();
    await Hive.close();
  });

  Widget app() => MaterialApp(
    home: BlocProvider<GymCubit>.value(
      value: cubit,
      child: const ActiveWorkoutScreen(),
    ),
  );

  testWidgets('typing weight and reps and ticking a set logs it', (
    tester,
  ) async {
    // A small phone, to surface overflow in the set rows.
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '62.5');
    await tester.enterText(fields.at(1), '8');
    await tester.pump();

    var set = cubit.state.active!.exercises.single.sets.single;
    expect(set.weightKg, 62.5);
    expect(set.reps, 8);
    expect(set.done, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    set = cubit.state.active!.exercises.single.sets.single;
    expect(set.done, isTrue);
    // Ticking a set starts the rest timer.
    expect(find.textContaining('Rest'), findsOneWidget);

    // Typing keeps focus: the field text is not rebuilt out from under it.
    expect(
      tester.widget<TextField>(fields.at(0)).controller!.text,
      '62.5',
    );
    expect(tester.takeException(), isNull);

    // Advance past the ticker so no timer is left pending.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('adding a set copies the previous one and the menu deletes it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), '40');
    await tester.enterText(find.byType(TextField).at(1), '10');
    await tester.pump();

    await tester.tap(find.text('Add set'));
    await tester.pump();
    final sets = cubit.state.active!.exercises.single.sets;
    expect(sets, hasLength(2));
    expect(sets[1].weightKg, 40);
    expect(sets[1].reps, 10);

    // Delete the first set through the number menu.
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete set'));
    await tester.pumpAndSettle();
    expect(cubit.state.active!.exercises.single.sets, hasLength(1));
    // The remaining row shows the surviving set's values.
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '40',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
