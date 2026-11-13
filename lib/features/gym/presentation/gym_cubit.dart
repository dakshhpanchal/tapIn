import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/domain/gym_transfer.dart';
import 'package:opennutritracker/features/gym/presentation/workout_live_update.dart';
import 'package:uuid/uuid.dart';

class GymState extends Equatable {
  final bool loaded;
  final List<WorkoutSession> sessions; // finished, newest first
  final List<Routine> routines;
  final List<Exercise> exercises;
  final WorkoutSession? active;
  final bool useLb;

  /// Days logged as rest days, as `yyyy-MM-dd` (see [dayKey]).
  final Set<String> restDays;

  const GymState({
    this.loaded = false,
    this.sessions = const [],
    this.routines = const [],
    this.exercises = const [],
    this.active,
    this.useLb = false,
    this.restDays = const {},
  });

  GymState copyWith({
    bool? loaded,
    List<WorkoutSession>? sessions,
    List<Routine>? routines,
    List<Exercise>? exercises,
    WorkoutSession? active,
    bool clearActive = false,
    bool? useLb,
    Set<String>? restDays,
  }) => GymState(
    loaded: loaded ?? this.loaded,
    sessions: sessions ?? this.sessions,
    routines: routines ?? this.routines,
    exercises: exercises ?? this.exercises,
    active: clearActive ? null : (active ?? this.active),
    useLb: useLb ?? this.useLb,
    restDays: restDays ?? this.restDays,
  );

  @override
  List<Object?> get props => [
    loaded,
    sessions,
    routines,
    exercises,
    active,
    useLb,
    restDays,
  ];
}

/// The result of finishing a workout, for the summary.
class FinishedWorkout {
  final WorkoutSession session;
  final Map<String, Set<RecordKind>> records;
  const FinishedWorkout(this.session, this.records);
}

/// Owns gym history, routines and the workout in progress. The workout in
/// progress is saved after every change, so closing the app mid-session
/// loses nothing.
class GymCubit extends Cubit<GymState> {
  final GymRepository _repo;
  final GetConfigUsecase _config;
  final WorkoutLiveUpdate? _liveUpdate;
  static const _uuid = Uuid();

  /// [liveUpdate] keeps the running-workout notification in step with the
  /// workout; without it (tests) there is none.
  GymCubit(this._repo, this._config, {WorkoutLiveUpdate? liveUpdate})
    : _liveUpdate = liveUpdate,
      super(const GymState());

  @override
  void onChange(Change<GymState> change) {
    super.onChange(change);
    // Only once the stored workout has been read, so the app opening does not
    // look like "no workout" and clear a notification that is still right.
    if (change.nextState.loaded) _liveUpdate?.sync(change.nextState.active);
  }

  Future<void> load() async {
    final exercises = await _repo.getExercises();
    final config = await _config.getConfig();
    emit(
      GymState(
        loaded: true,
        sessions: _repo.getSessions(),
        routines: _repo.getRoutines(),
        exercises: exercises,
        active: _repo.getActiveSession(),
        useLb: config.bodyWeightUnit == BodyWeightUnit.lb,
        restDays: _repo.getRestDays(),
      ),
    );
    await _catchUpPlans();
  }

  /// Once: brings every plan in line with the last workout logged from it,
  /// for plans made before workouts updated them. The exercises and their
  /// order follow that workout (a swapped machine, an added exercise); the
  /// weights and machine settings of every exercise follow its last logged
  /// session. Reps and plan notes stay as they were.
  Future<void> _catchUpPlans() async {
    if (_repo.plansCaughtUp) return;
    for (final routine in state.routines) {
      // The latest finished workout from this plan (older ones were saved
      // with just its name).
      WorkoutSession? latest;
      for (final s in state.sessions) {
        if (!s.isFinished) continue;
        if (s.routineId != routine.id &&
            !(s.routineId == null && s.name == routine.name)) {
          continue;
        }
        if (latest == null || s.startedAt.isAfter(latest.startedAt)) {
          latest = s;
        }
      }
      final planned = <String, WorkoutExercise>{};
      final seen = <String, int>{};
      for (final e in routine.exercises) {
        planned['${e.exerciseId}#${seen.update(e.exerciseId, (n) => n + 1, ifAbsent: () => 1)}'] =
            e;
      }
      final source = latest == null
          ? routine.exercises
          : [for (final e in latest.exercises) _planned(e, planNote: '')];
      final counts = <String, int>{};
      final exercises = <WorkoutExercise>[];
      for (final e in source) {
        final n = counts.update(e.exerciseId, (n) => n + 1, ifAbsent: () => 1);
        // Keep the plan's own copy (reps, note) when it has this exercise.
        final plan = planned['${e.exerciseId}#$n'] ?? e;
        final last = lastPerformance(state.sessions, e.exerciseId);
        if (last == null || last.plates != plan.plates) {
          exercises.add(plan);
          continue;
        }
        final done = [
          for (final s in last.sets)
            if (!s.warmup) s,
        ];
        var w = 0;
        exercises.add(
          plan.copyWith(
            sets: [
              for (final s in plan.sets)
                if (s.warmup || done.isEmpty)
                  s
                else
                  s.copyWith(
                    weightKg: done[w++ < done.length ? w - 1 : done.length - 1]
                        .weightKg,
                  ),
            ],
            setting: last.setting.isNotEmpty ? last.setting : plan.setting,
          ),
        );
      }
      if ([for (final e in exercises) _key(e)].join() !=
          [for (final e in routine.exercises) _key(e)].join()) {
        await _repo.saveRoutine(routine.copyWith(exercises: exercises));
      }
    }
    await _repo.markPlansCaughtUp();
    emit(state.copyWith(routines: _repo.getRoutines()));
  }

  // Starting a workout ------------------------------------------------------

  Future<void> startEmptyWorkout() => _start('Workout', const [], null);

  Future<void> startFromRoutine(Routine routine) => _start(routine.name, [
    for (final e in routine.exercises) _forRoutine(e),
  ], routine.id);

  Future<void> _start(
    String name,
    List<WorkoutExercise> exercises,
    String? routineId,
  ) async {
    if (state.active != null) return;
    final session = WorkoutSession(
      id: _uuid.v4(),
      name: name,
      startedAt: DateTime.now(),
      exercises: exercises,
      routineId: routineId,
    );
    await _repo.saveActiveSession(session);
    emit(state.copyWith(active: session));
  }

  /// A routine exercise as it starts a workout: as many sets as planned, each
  /// prefilled with what was done in the same set last time (not yet done).
  WorkoutExercise _forRoutine(WorkoutExercise template) {
    final planned = template.sets.isEmpty ? 1 : template.sets.length;
    final found = lastPerformance(state.sessions, template.exerciseId);
    // Numbers logged in another unit (plates vs kg) would read wrong here.
    final last = found != null && found.plates == template.plates
        ? found
        : null;
    final earlier = last == null
        ? const <SetEntry>[]
        : [
            for (final s in last.sets)
              if (!s.warmup) s,
          ];
    return template.copyWith(
      // The machine setup usually stays the same, so it carries over; the
      // note was for this session, and the screen shows it from last time.
      setting: last?.setting ?? template.setting,
      planNote: template.planNote,
      note: '',
      sets: [
        for (var i = 0; i < planned; i++)
          if (earlier.isNotEmpty)
            SetEntry(
              weightKg:
                  earlier[i < earlier.length ? i : earlier.length - 1].weightKg,
              reps: earlier[i < earlier.length ? i : earlier.length - 1].reps,
            )
          else if (i < template.sets.length)
            SetEntry(
              weightKg: template.sets[i].weightKg,
              reps: template.sets[i].reps,
            )
          else
            const SetEntry(),
      ],
    );
  }

  /// An exercise added while working out: starts with what was done last
  /// time, or one empty set.
  WorkoutExercise _withHistory(WorkoutExercise template) {
    final found = lastPerformance(state.sessions, template.exerciseId);
    final last = found != null && found.plates == template.plates
        ? found
        : null;
    final source = last == null
        ? const <SetEntry>[]
        : [
            for (final s in last.sets)
              if (!s.warmup) s,
          ];
    return template.copyWith(
      setting: last?.setting ?? '',
      note: '',
      sets: source.isEmpty
          ? const [SetEntry()]
          : [
              for (final s in source)
                SetEntry(weightKg: s.weightKg, reps: s.reps),
            ],
    );
  }

  // Editing the workout in progress -------------------------------------------

  /// The plan the workout in progress came from, if it still exists.
  Routine? get activePlan {
    final id = state.active?.routineId;
    if (id == null) return null;
    return state.routines.where((r) => r.id == id).firstOrNull;
  }

  Future<void> _update(
    WorkoutSession Function(WorkoutSession s) change, {
    bool prune = false,
  }) async {
    final current = state.active;
    if (current == null) return;
    final next = change(current);
    await _repo.saveActiveSession(next);
    emit(state.copyWith(active: next));
    await _syncPlan(current, next, prune: prune);
  }

  Future<void> renameWorkout(String name) =>
      _update((s) => s.copyWith(name: name));

  Future<void> setNotes(String notes) =>
      _update((s) => s.copyWith(notes: notes));

  Future<void> addExercise(Exercise e) => _update(
    (s) => s.copyWith(
      exercises: [...s.exercises, _withHistory(WorkoutExercise.of(e))],
    ),
  );

  /// Removes an exercise from this workout; with [prune] also from the plan.
  Future<void> removeExercise(int index, {bool prune = false}) => _update(
    (s) => s.copyWith(exercises: [...s.exercises]..removeAt(index)),
    prune: prune,
  );

  /// Takes an exercise (skipped today) out of the plan as well.
  Future<void> removeFromPlan(int exerciseIndex) async {
    final session = state.active;
    final routine = activePlan;
    if (session == null || routine == null) return;
    final id = session.exercises[exerciseIndex].exerciseId;
    final occurrence = session.exercises
        .take(exerciseIndex + 1)
        .where((e) => e.exerciseId == id)
        .length;
    var seen = 0;
    final kept = [
      for (final e in routine.exercises)
        if (e.exerciseId != id || ++seen != occurrence) e,
    ];
    if (kept.length == routine.exercises.length) return;
    await _repo.saveRoutine(routine.copyWith(exercises: kept));
    emit(state.copyWith(routines: _repo.getRoutines()));
  }

  Future<void> _updateExercise(
    int index,
    WorkoutExercise Function(WorkoutExercise e) change, {
    bool prune = false,
  }) => _update((s) {
    final list = [...s.exercises];
    list[index] = change(list[index]);
    return s.copyWith(exercises: list);
  }, prune: prune);

  Future<void> addSet(int exerciseIndex) => _updateExercise(exerciseIndex, (e) {
    // A new set starts from the one above it, the usual next step.
    final seed = e.sets.isEmpty
        ? const SetEntry()
        : SetEntry(weightKg: e.sets.last.weightKg, reps: e.sets.last.reps);
    return e.copyWith(sets: [...e.sets, seed]);
  });

  Future<void> removeSet(
    int exerciseIndex,
    int setIndex, {
    bool prune = false,
  }) => _updateExercise(
    exerciseIndex,
    (e) => e.copyWith(sets: [...e.sets]..removeAt(setIndex)),
    prune: prune,
  );

  Future<void> updateSet(
    int exerciseIndex,
    int setIndex,
    SetEntry Function(SetEntry s) change,
  ) async {
    await _updateExercise(exerciseIndex, (e) {
      final sets = [...e.sets];
      sets[setIndex] = change(sets[setIndex]);
      return e.copyWith(sets: sets);
    });
  }

  /// An exercise as a plan keeps it: sets with weight, reps and warm-up but
  /// nothing done, the machine setting and the unit. Notes for today and the
  /// skipped mark are not part of a plan; the plan's own note is kept.
  WorkoutExercise _planned(WorkoutExercise e, {String? planNote}) => e.copyWith(
    note: '',
    skipped: false,
    planNote: planNote ?? e.planNote,
    sets: [
      for (final s in e.sets)
        SetEntry(weightKg: s.weightKg, reps: s.reps, warmup: s.warmup),
    ],
  );

  static String _key(WorkoutExercise e) => jsonEncode(e.toJson());

  /// Carries what changed in the workout in progress into the plan it came
  /// from: added, removed and reordered exercises, added and removed sets,
  /// weights, reps, warm-ups, the machine setting and plates/kg. Only what
  /// the edit touched is written, so the rest of the plan stays as planned.
  /// Does nothing for a workout with no plan, or one whose plan was deleted.
  Future<void> _syncPlan(
    WorkoutSession before,
    WorkoutSession after, {
    bool everything = false,
    bool prune = false,
  }) async {
    final id = after.routineId;
    if (id == null) return;
    // Read from storage: a caller may have just changed the plans.
    final routine = _repo.getRoutines().where((r) => r.id == id).firstOrNull;
    if (routine == null) return;

    // "The 2nd time this exercise comes up": how plan and workout line up.
    String slot(List<WorkoutExercise> list, int i) {
      final n = list
          .take(i + 1)
          .where((e) => e.exerciseId == list[i].exerciseId);
      return '${list[i].exerciseId}#${n.length}';
    }

    final oldPlan = {
      for (var i = 0; i < routine.exercises.length; i++)
        slot(routine.exercises, i): routine.exercises[i],
    };
    final was = {
      for (var i = 0; i < before.exercises.length; i++)
        slot(before.exercises, i): _planned(before.exercises[i]),
    };

    final exercises = <WorkoutExercise>[];
    for (var i = 0; i < after.exercises.length; i++) {
      final now = after.exercises[i];
      final key = slot(after.exercises, i);
      final planned = oldPlan[key];
      // At the end of a workout every exercise done counts, so the plan
      // always holds what was last lifted, even if no number was touched.
      final changed = everything
          ? !now.skipped
          : was[key] == null || _key(was[key]!) != _key(_planned(now));
      if (planned == null) {
        // An exercise skipped today and taken out of the plan stays out.
        if (!now.skipped) exercises.add(_planned(now, planNote: ''));
      } else if (changed) {
        // Reps stay as planned, and a cleared weight does not blank the
        // plan; a set the plan did not have takes what was entered.
        final entered = _planned(now).sets;
        // A set removed today stays in the plan unless asked to go.
        final keepSets = !prune && entered.length < planned.sets.length;
        exercises.add(
          planned.copyWith(
            sets: keepSets
                ? planned.sets
                : [
                    for (var j = 0; j < entered.length; j++)
                      if (j < planned.sets.length)
                        planned.sets[j].copyWith(
                          weightKg: entered[j].weightKg > 0
                              ? entered[j].weightKg
                              : planned.sets[j].weightKg,
                          warmup: entered[j].warmup,
                        )
                      else
                        entered[j],
                  ],
            setting: now.setting,
            plates: now.plates,
          ),
        );
      } else {
        exercises.add(planned);
      }
    }

    if (!prune) {
      // Exercises dropped from today's workout stay in the plan, after the
      // one that came before them.
      final inResult = {
        for (var i = 0; i < exercises.length; i++) slot(exercises, i),
      };
      for (var i = 0; i < routine.exercises.length; i++) {
        final key = slot(routine.exercises, i);
        if (inResult.contains(key)) continue;
        final prev = i == 0 ? null : slot(routine.exercises, i - 1);
        var at = 0;
        if (prev != null) {
          for (var j = 0; j < exercises.length; j++) {
            if (slot(exercises, j) == prev) at = j + 1;
          }
        }
        exercises.insert(at, routine.exercises[i]);
        inResult.add(key);
      }
    }

    final same =
        exercises.length == routine.exercises.length &&
        [for (final e in exercises) _key(e)].join() ==
            [for (final e in routine.exercises) _key(e)].join();
    if (same) return;
    await _repo.saveRoutine(routine.copyWith(exercises: exercises));
    emit(state.copyWith(routines: _repo.getRoutines()));
  }

  /// Switches an exercise between machine plates and kg/lb, in this workout,
  /// in the exercise itself and in every plan that has it, so they all agree.
  /// The typed numbers stay as they are; logged history keeps what it was
  /// logged with.
  Future<void> setExercisePlates(int exerciseIndex, bool plates) async {
    final session = state.active;
    if (session == null) return;
    final id = session.exercises[exerciseIndex].exerciseId;
    await _updateExercise(exerciseIndex, (e) => e.copyWith(plates: plates));
    for (final routine in state.routines) {
      if (!routine.exercises.any((e) => e.exerciseId == id)) continue;
      await _repo.saveRoutine(
        routine.copyWith(
          exercises: [
            for (final e in routine.exercises)
              e.exerciseId == id ? e.copyWith(plates: plates) : e,
          ],
        ),
      );
    }
    final known = state.exercises.where((e) => e.id == id).firstOrNull;
    if (known != null && known.plates != plates) {
      await _repo.saveExercise(
        Exercise(
          id: known.id,
          name: known.name,
          muscle: known.muscle,
          kind: known.kind,
          equipment: known.equipment,
          isCustom: known.isCustom,
          plates: plates,
        ),
      );
    }
    emit(
      state.copyWith(
        routines: _repo.getRoutines(),
        exercises: await _repo.getExercises(),
      ),
    );
  }

  Future<void> setExerciseNote(int exerciseIndex, String note) =>
      _updateExercise(exerciseIndex, (e) => e.copyWith(note: note));

  /// Skips an exercise for today (or brings it back). It stays in the list so
  /// it can be undone, and is left out of the finished workout.
  Future<void> setExerciseSkipped(int exerciseIndex, bool skipped) =>
      _updateExercise(exerciseIndex, (e) => e.copyWith(skipped: skipped));

  Future<void> setExerciseSetting(int exerciseIndex, String setting) =>
      _updateExercise(exerciseIndex, (e) => e.copyWith(setting: setting));

  // Ending the workout ------------------------------------------------------

  /// Finishes the workout: drops sets that were never done, saves it to
  /// history, and reports any records it set. Null when there was nothing
  /// done (the workout is discarded).
  Future<FinishedWorkout?> finishWorkout() async {
    final current = state.active;
    if (current == null) return null;
    await _syncPlan(current, current, everything: true);
    final cleaned = current.copyWith(
      endedAt: DateTime.now(),
      exercises: [
        for (final e in current.exercises)
          if (!e.skipped && e.sets.any(isLoggedSet))
            e.copyWith(
              sets: [
                for (final s in e.sets)
                  if (isLoggedSet(s)) s,
              ],
            ),
      ],
    );
    await _repo.clearActiveSession();
    if (cleaned.exercises.isEmpty) {
      emit(state.copyWith(clearActive: true));
      return null;
    }
    final records = detectRecords(cleaned, state.sessions);
    await _repo.saveSession(cleaned);
    emit(
      state.copyWith(
        clearActive: true,
        sessions: [cleaned, ...state.sessions]
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
      ),
    );
    return FinishedWorkout(cleaned, records);
  }

  Future<void> discardWorkout() async {
    await _repo.clearActiveSession();
    emit(state.copyWith(clearActive: true));
  }

  // Rest days ---------------------------------------------------------------

  /// The key a calendar day is stored under: `2026-10-27`.
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Logs [day] as a rest day, or takes the mark off again.
  Future<void> setRestDay(DateTime day, bool rest) async {
    final days = {...state.restDays};
    rest ? days.add(dayKey(day)) : days.remove(dayKey(day));
    await _repo.saveRestDays(days);
    emit(state.copyWith(restDays: days));
  }

  // History, routines and exercises -------------------------------------------

  /// Saves a corrected finished workout in place of the one with the same id.
  Future<void> updateSession(WorkoutSession updated) async {
    await _repo.saveSession(updated);
    emit(
      state.copyWith(
        sessions: [
          for (final s in state.sessions) s.id == updated.id ? updated : s,
        ]..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
      ),
    );
  }

  /// Puts a deleted workout back, for the Undo on the delete message.
  Future<void> restoreSession(WorkoutSession session) async {
    await _repo.saveSession(session);
    emit(
      state.copyWith(
        sessions: [...state.sessions.where((s) => s.id != session.id), session]
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
      ),
    );
  }

  Future<void> deleteSession(String id) async {
    await _repo.deleteSession(id);
    emit(
      state.copyWith(
        sessions: [...state.sessions]..removeWhere((s) => s.id == id),
      ),
    );
  }

  Future<void> saveAsRoutine(WorkoutSession session, String name) async {
    final routine = Routine(
      id: _uuid.v4(),
      name: name,
      order: _nextRoutineOrder(),
      exercises: [
        for (final e in session.exercises)
          e.copyWith(
            note: '',
            setting: '',
            sets: [
              for (final s in e.sets.where((s) => !s.warmup))
                SetEntry(weightKg: s.weightKg, reps: s.reps),
            ],
          ),
      ],
    );
    await _repo.saveRoutine(routine);
    emit(state.copyWith(routines: _repo.getRoutines()));
  }

  /// Creates or (when [id] is given) updates a planned workout.
  Future<void> saveRoutine({
    String? id,
    required String name,
    required List<WorkoutExercise> exercises,
  }) async {
    final existing = state.routines.where((r) => r.id == id).firstOrNull;
    await _repo.saveRoutine(
      Routine(
        id: id ?? _uuid.v4(),
        name: name,
        exercises: exercises,
        order: existing?.order ?? _nextRoutineOrder(),
      ),
    );
    emit(state.copyWith(routines: _repo.getRoutines()));
  }

  int _nextRoutineOrder() => state.routines.isEmpty
      ? 0
      : state.routines.map((r) => r.order).reduce((a, b) => a > b ? a : b) + 1;

  /// Saves the workouts in the given order (first = top of the list).
  Future<void> reorderRoutines(List<Routine> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      await _repo.saveRoutine(ordered[i].copyWith(order: i));
    }
    emit(state.copyWith(routines: _repo.getRoutines()));
  }

  /// Reorders the exercises of the workout in progress. [order] lists the
  /// current indexes in their new order.
  Future<void> reorderExercises(List<int> order) => _update(
    (s) => s.copyWith(exercises: [for (final i in order) s.exercises[i]]),
  );

  Future<void> deleteRoutine(String id) async {
    await _repo.deleteRoutine(id);
    emit(state.copyWith(routines: _repo.getRoutines()));
  }

  Future<Exercise> createExercise(
    String name, {
    MuscleGroup muscle = MuscleGroup.fullBody,
    bool plates = false,
  }) async {
    final exercise = Exercise(
      id: _uuid.v4(),
      name: name.trim(),
      muscle: muscle,
      plates: plates,
      isCustom: true,
    );
    await _repo.saveExercise(exercise);
    emit(state.copyWith(exercises: await _repo.getExercises()));
    return exercise;
  }

  /// Everything as one JSON file's text; see `gym_transfer.dart`.
  String exportJson() => exportGymJson(
    exercises: state.exercises,
    routines: state.routines,
    sessions: state.sessions,
    restDays: state.restDays,
  );

  /// Merges an import file into what is stored. Throws [GymImportException]
  /// when the file is not a workouts file; otherwise returns what happened.
  Future<GymImportPlan> importJson(String raw) async {
    final plan = parseGymImport(
      raw,
      exercises: state.exercises,
      routines: state.routines,
      sessions: state.sessions,
      newId: _uuid.v4,
    );
    for (final e in [...plan.newExercises, ...plan.updatedExercises]) {
      await _repo.saveExercise(e);
    }
    for (final r in plan.workouts) {
      await _repo.saveRoutine(r);
    }
    for (final s in plan.sessions) {
      await _repo.saveSession(s);
    }
    final restDays = {...state.restDays, ...plan.restDays};
    if (plan.restDays.isNotEmpty) await _repo.saveRestDays(restDays);
    emit(
      state.copyWith(
        exercises: await _repo.getExercises(),
        routines: _repo.getRoutines(),
        sessions: _repo.getSessions(),
        restDays: restDays,
      ),
    );
    return plan;
  }

  /// Renames an exercise or changes its muscle group or plates setting.
  /// Logged workouts keep the values they were logged with.
  Future<void> updateExercise(
    Exercise e, {
    required String name,
    required MuscleGroup muscle,
    required bool plates,
  }) async {
    await _repo.saveExercise(
      Exercise(
        id: e.id,
        name: name.trim(),
        muscle: muscle,
        kind: e.kind,
        equipment: e.equipment,
        isCustom: e.isCustom,
        plates: plates,
      ),
    );
    // Plans and the workout in progress hold their own copy of the name,
    // muscle group and unit, so carry the change into them. Finished workouts
    // stay as they were logged.
    WorkoutExercise sync(WorkoutExercise x) => x.exerciseId == e.id
        ? x.copyWith(name: name.trim(), muscle: muscle, plates: plates)
        : x;
    for (final routine in state.routines) {
      if (!routine.exercises.any((x) => x.exerciseId == e.id)) continue;
      await _repo.saveRoutine(
        routine.copyWith(
          exercises: [for (final x in routine.exercises) sync(x)],
        ),
      );
    }
    final active = state.active;
    if (active != null && active.exercises.any((x) => x.exerciseId == e.id)) {
      await _update(
        (s) => s.copyWith(exercises: [for (final x in s.exercises) sync(x)]),
      );
    }
    emit(
      state.copyWith(
        routines: _repo.getRoutines(),
        exercises: await _repo.getExercises(),
      ),
    );
  }

  Future<void> deleteExercise(String id) async {
    await _repo.deleteExercise(id);
    emit(state.copyWith(exercises: await _repo.getExercises()));
  }
}
