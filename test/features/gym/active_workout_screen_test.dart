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
import 'package:opennutritracker/features/gym/presentation/session_detail_screen.dart';
import 'package:opennutritracker/features/gym/presentation/today_workout_row.dart';
import 'package:opennutritracker/features/gym/presentation/session_edit_screen.dart';
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
    expect(find.byTooltip('Delete set'), findsNWidgets(3)); // starts with 3
    await tester.tap(find.text('Add set'));
    await tester.pump();
    expect(find.byTooltip('Delete set'), findsNWidgets(4));
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

  testWidgets('tapping a workout shows what is in it without starting it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await cubit.discardWorkout();
    await cubit.importJson(gymImportExample);

    await tester.pumpWidget(app(home: const Scaffold(body: GymPage())));
    await tester.pumpAndSettle();
    expect(find.text('Volume'), findsNothing); // no volume on the top card
    expect(find.byTooltip('Reorder workouts'), findsOneWidget);

    // Tap the card itself (its name), not the Start button.
    await tester.tap(find.text('Push Day').first);
    await tester.pumpAndSettle();

    // The contents are listed: exercises, set counts, weights and settings.
    expect(cubit.state.active, isNull, reason: 'looking must not start it');
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Pec Deck'), findsOneWidget);
    expect(find.text('3 × 60 kg'), findsOneWidget);
    expect(find.text('2 × 18 plates'), findsOneWidget);
    expect(find.textContaining('Setting Seat 3'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.textContaining('Started'), findsNothing);

    // Start is the explicit step.
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
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

  /// A home screen with one button that opens the workout, the way the Gym tab
  /// does, so Finish has somewhere to go back to.
  Widget homeWithWorkoutButton() => Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ActiveWorkoutScreen(),
            ),
          ),
          child: const Text('Open workout'),
        ),
      ),
    ),
  );

  testWidgets('finishing lands on the summary, never on a blank screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await cubit.updateSet(
      0,
      0,
      (s) => s.copyWith(weightKg: 60, reps: 8, done: true),
    );

    await tester.pumpWidget(app(home: homeWithWorkoutButton()));
    await tester.tap(find.text('Open workout'));
    await tester.pumpAndSettle();
    expect(find.text('Finish'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();

    // The summary is showing, and the finished workout screen is gone.
    expect(find.text('Workout complete'), findsOneWidget);
    expect(find.byType(ActiveWorkoutScreen), findsNothing);
    expect(cubit.state.active, isNull);
    expect(cubit.state.sessions, hasLength(1));

    // Done goes back to where the workout was opened from.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open workout'), findsOneWidget);
    expect(find.text('Workout complete'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('discarding a workout leaves the screen cleanly', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(home: homeWithWorkoutButton()));
    await tester.tap(find.text('Open workout'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show menu')); // the app bar's menu
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutScreen), findsNothing);
    expect(find.text('Open workout'), findsOneWidget);
    expect(cubit.state.active, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a logged workout can be edited and saved', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // A finished workout: Bench Press, 60 x 8 and 60 x 7.
    await cubit.updateSet(
      0,
      0,
      (s) => s.copyWith(weightKg: 60, reps: 8, done: true),
    );
    await cubit.addSet(0);
    await cubit.updateSet(
      0,
      1,
      (s) => s.copyWith(weightKg: 60, reps: 7, done: true),
    );
    await cubit.finishWorkout();
    final logged = cubit.state.sessions.single;

    await tester.pumpWidget(app(home: SessionDetailScreen(session: logged)));
    await tester.pumpAndSettle();
    expect(find.text('60 kg × 8'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit workout'));
    await tester.pumpAndSettle();
    // name, then per set weight + reps: set 1 = fields 1,2; set 2 = 3,4.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Chest day');
    await tester.enterText(fields.at(2), '10'); // set 1: 8 -> 10 reps
    await tester.tap(find.text('Add set'));
    await tester.pump();
    // The new third set starts from the one above (60 x 7); make it 5 reps.
    await tester.enterText(find.byType(TextField).at(6), '5');
    // Drop the second set (60 x 7).
    await tester.tap(find.byTooltip('Delete set').at(1));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = cubit.state.sessions.single;
    expect(saved.id, logged.id);
    expect(saved.name, 'Chest day');
    expect(saved.exercises.single.sets.map((s) => s.reps), [10, 5]);
    expect(saved.exercises.single.sets.every((s) => s.weightKg == 60), isTrue);
    // The detail screen behind shows the corrected numbers.
    expect(find.text('Chest day'), findsWidgets);
    expect(find.text('60 kg × 10'), findsOneWidget);
    expect(find.text('60 kg × 8'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an edit with no sets left is refused, not saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await cubit.updateSet(
      0,
      0,
      (s) => s.copyWith(weightKg: 60, reps: 8, done: true),
    );
    await cubit.finishWorkout();
    final logged = cubit.state.sessions.single;

    await tester.pumpWidget(app(home: SessionEditScreen(session: logged)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete set'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.textContaining('Add at least one set'), findsOneWidget);
    expect(cubit.state.sessions.single.exercises.single.sets, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'adding an exercise to a plan takes weights, a setting and a note',
    (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await cubit.discardWorkout();

      await tester.pumpWidget(app(home: const Scaffold(body: GymPage())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New workout'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Push day');
      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();

      // Fields in order: name, then 3 weights, setting, note.
      final fields = find.byType(TextField);
      expect(find.text('Machine setting'), findsOneWidget);
      expect(find.text('Note (shown during the workout)'), findsOneWidget);
      await tester.enterText(fields.at(1), '40');
      await tester.enterText(fields.at(2), '45');
      await tester.enterText(fields.at(3), '50');
      await tester.enterText(fields.at(4), 'Seat 4, pin 7');
      await tester.enterText(fields.at(5), 'Keep elbows tucked');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final planned = cubit.state.routines.single.exercises.single;
      expect(planned.sets.map((s) => s.weightKg), [40, 45, 50]);
      expect(planned.setting, 'Seat 4, pin 7');
      expect(planned.planNote, 'Keep elbows tucked');
      expect(planned.note, isEmpty); // the note for next time stays separate

      // Reopening the plan shows what was saved.
      await tester.tap(find.byTooltip('Show menu').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Seat 4, pin 7'), findsOneWidget);
      expect(find.text('Keep elbows tucked'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Starting it carries the weights, setting and plan note into the workout.
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      final active = cubit.state.active!.exercises.single;
      expect(active.sets.map((s) => s.weightKg), [40, 45, 50]);
      expect(active.setting, 'Seat 4, pin 7');
      expect(active.planNote, 'Keep elbows tucked');
      expect(find.text('Plan: Keep elbows tucked'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the exercises of a logged workout can be reordered while editing',
    (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // A finished workout with Bench Press, then Squat.
      final squat = await cubit.createExercise('Squat');
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
      await cubit.finishWorkout();
      final logged = cubit.state.sessions.single;
      expect(logged.exercises.map((e) => e.name), ['Bench Press', 'Squat']);

      await tester.pumpWidget(app(home: SessionEditScreen(session: logged)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reorder exercises'));
      await tester.pumpAndSettle();
      // Drag Bench Press's handle down past Squat, then confirm.
      await tester.drag(
        find.byIcon(Icons.drag_handle_rounded).first,
        const Offset(0, 120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = cubit.state.sessions.single;
      expect(saved.exercises.map((e) => e.name), ['Squat', 'Bench Press']);
      // Each exercise keeps its own sets.
      expect(saved.exercises.first.sets.single.weightKg, 80);
      expect(saved.exercises.last.sets.single.weightKg, 60);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Home shows what kind of day today is, above the meals', (
    tester,
  ) async {
    await cubit.discardWorkout();
    await tester.pumpWidget(
      app(
        home: Scaffold(body: TodayWorkoutRow(cubit: cubit)),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing yet: a nudge with a one-tap rest day.
    expect(find.text('No workout yet'), findsOneWidget);
    await tester.tap(find.text('Rest day'));
    await tester.pumpAndSettle();
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('No workout yet'), findsNothing);
    expect(cubit.state.restDays, contains(GymCubit.dayKey(DateTime.now())));

    // Undo.
    await tester.tap(find.byTooltip('Not a rest day'));
    await tester.pumpAndSettle();
    expect(find.text('No workout yet'), findsOneWidget);
    expect(cubit.state.restDays, isEmpty);

    // A workout in progress shows its name.
    await cubit.startFromRoutine(
      Routine(
        id: 'u',
        name: 'Upper',
        exercises: [WorkoutExercise.of(cubit.state.exercises.first)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Upper'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);

    // Finished, it still shows the name, and a rest day mark no longer wins.
    await cubit.updateSet(
      0,
      0,
      (s) => s.copyWith(weightKg: 40, reps: 8, done: true),
    );
    await cubit.finishWorkout();
    await cubit.setRestDay(DateTime.now(), true);
    await tester.pumpAndSettle();
    expect(find.text('Upper'), findsOneWidget);
    expect(find.text('In progress'), findsNothing);
    expect(find.text('Rest day'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Gym tab logs rest days and lists them in the history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await cubit.discardWorkout();
    await tester.pumpWidget(app(home: const Scaffold(body: GymPage())));
    await tester.pumpAndSettle();

    expect(find.text('Rest day today'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final today = GymCubit.dayKey(DateTime.now());
    expect(cubit.state.restDays, contains(today));
    // It shows up in the history as its own row.
    expect(find.text('Rest day'), findsOneWidget);

    // An older rest day is listed too, and can be removed from there.
    await cubit.setRestDay(DateTime(2026, 1, 5), true);
    await tester.pumpAndSettle();
    expect(find.text('Rest day'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Remove rest day').last);
    await tester.pumpAndSettle();
    expect(cubit.state.restDays, {today});

    // Switching today off removes it.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(cubit.state.restDays, isEmpty);
    expect(find.text('Rest day'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
