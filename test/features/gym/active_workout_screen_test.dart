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
import 'package:opennutritracker/features/gym/domain/gym_transfer.dart';
import 'package:opennutritracker/features/gym/presentation/active_workout_screen.dart';
import 'package:opennutritracker/features/gym/presentation/gym_page.dart';
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
    final bench = await cubit.createExercise('Bench Press');
    await cubit.startEmptyWorkout();
    await cubit.addExercise(bench);
  });

  tearDown(() async {
    await cubit.close();
    await Hive.close();
  });

  // The cubit sits above the Navigator, as in the real app, so screens pushed
  // from the workout can reach it too.
  Widget app({Widget home = const ActiveWorkoutScreen()}) =>
      BlocProvider<GymCubit>.value(
        value: cubit,
        child: MaterialApp(home: home),
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
    // No timers: nothing starts when a set is ticked.
    expect(find.textContaining('Rest'), findsNothing);

    // Typing keeps focus: the field text is not rebuilt out from under it.
    expect(tester.widget<TextField>(fields.at(0)).controller!.text, '62.5');
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

  testWidgets('add exercise opens the picker instead of a blank page', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget); // listed in the picker

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(cubit.state.active!.exercises, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('plan a workout, start it and log reps', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await cubit.discardWorkout();

    await tester.pumpWidget(app(home: const Scaffold(body: GymPage())));
    await tester.pumpAndSettle();
    expect(find.text('New workout'), findsOneWidget);

    await tester.tap(find.text('New workout'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Push day');
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
    expect(find.text('3 sets'), findsOneWidget);
    await tester.tap(find.byTooltip('More sets'));
    await tester.pump();
    expect(find.text('4 sets'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(cubit.state.routines.single.exercises.single.sets, hasLength(4));
    expect(find.text('Push day'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    // Four blank sets to fill in; log reps for the first.
    expect(find.byType(Checkbox), findsNWidgets(4));
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(cubit.state.active!.exercises.single.sets.first.reps, 12);
    expect(cubit.state.active!.exercises.single.sets.first.done, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows last time per set, a clock, and saves setting and note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final bench = cubit.state.exercises.first;
    // A finished workout to compare against.
    await cubit.updateSet(
      0,
      0,
      (s) => s.copyWith(weightKg: 60, reps: 8, done: true),
    );
    await cubit.setExerciseNote(0, 'Go heavier');
    await cubit.finishWorkout();
    await cubit.startEmptyWorkout();
    await cubit.addExercise(bench);

    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.textContaining('Started'), findsOneWidget);
    expect(find.text('60 kg × 8'), findsOneWidget); // last time, this set
    expect(find.textContaining('Go heavier'), findsOneWidget); // last note

    await tester.enterText(
      find.widgetWithText(TextField, 'Machine setting'),
      'Seat 5',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Note for next time'),
      'Slow reps',
    );
    await tester.pump();
    final exercise = cubit.state.active!.exercises.single;
    expect(exercise.setting, 'Seat 5');
    expect(exercise.note, 'Slow reps');

    // The progress screen opens (it used to be a blank page).
    await tester.tap(find.byIcon(Icons.show_chart_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Heaviest'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('muscle chips filter the picker and new exercises get a muscle', (
    tester,
  ) async {
    await cubit.createExercise('Squat', muscle: MuscleGroup.quads);
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);

    // The chip row scrolls sideways; bring Quads into view first.
    await tester.drag(
      find.widgetWithText(ChoiceChip, 'Chest'),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Quads'));
    await tester.pump();
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Import and Export buttons sit in the header without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await cubit.discardWorkout();
    await cubit.importJson(gymImportExample);

    await tester.pumpWidget(app(home: const Scaffold(body: GymPage())));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Import workouts'), findsOneWidget);
    expect(find.byTooltip('Export workouts'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Import workouts'));
    await tester.pumpAndSettle();
    expect(find.text('Import workouts'), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
    expect(find.text('Copy format'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a plates exercise is labelled in plates and keeps the number as typed',
    (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final deck = await cubit.createExercise('Pec Deck', plates: true);
      await cubit.addExercise(deck);

      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('plates'), findsOneWidget);

      // The second exercise card: its weight field is the 3rd text field
      // overall (bench: weight, reps; pec deck: weight, reps; then the boxes).
      final weightField = find
          .byType(TextField)
          .at(4); // weight, reps, setting, note per card
      await tester.enterText(weightField, '18');
      await tester.pump();
      final set = cubit.state.active!.exercises[1].sets.first;
      expect(set.weightKg, 18);
      expect(cubit.state.active!.exercises[1].plates, isTrue);
      expect(cubit.state.active!.exercises[0].plates, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tapping a workout opens it; the top card has no volume', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await cubit.discardWorkout();
    await cubit.importJson(gymImportExample);

    await tester.pumpWidget(app(home: const Scaffold(body: GymPage())));
    await tester.pumpAndSettle();
    expect(find.text('Volume'), findsNothing);
    expect(find.byTooltip('Reorder workouts'), findsOneWidget);

    // Tap the card itself (its name), not the Start button.
    await tester.tap(find.text('Push Day').first);
    await tester.pumpAndSettle();
    expect(cubit.state.active, isNotNull);
    expect(cubit.state.active!.name, 'Push Day');
    expect(find.textContaining('Started'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an exercise can be skipped for the day and brought back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.byTooltip('Exercise options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip today'));
    await tester.pumpAndSettle();
    expect(find.text('Skipped today'), findsOneWidget);
    expect(
      find.byType(Checkbox),
      findsNothing,
    ); // sets are hidden while skipped
    expect(cubit.state.active!.exercises.single.skipped, isTrue);

    await tester.tap(find.text('Bring back'));
    await tester.pumpAndSettle();
    expect(find.text('Skipped today'), findsNothing);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
