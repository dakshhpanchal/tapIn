import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:opennutritracker/features/gym/domain/gym_transfer.dart';
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
  static const _uuid = Uuid();

  GymCubit(this._repo, this._config) : super(const GymState());

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
  }

  // Starting a workout ------------------------------------------------------

  Future<void> startEmptyWorkout() => _start('Workout', const []);

  Future<void> startFromRoutine(Routine routine) =>
      _start(routine.name, [for (final e in routine.exercises) _forRoutine(e)]);

  Future<void> _start(String name, List<WorkoutExercise> exercises) async {
    if (state.active != null) return;
    final session = WorkoutSession(
      id: _uuid.v4(),
      name: name,
      startedAt: DateTime.now(),
      exercises: exercises,
    );
    await _repo.saveActiveSession(session);
    emit(state.copyWith(active: session));
  }

  /// A routine exercise as it starts a workout: as many sets as planned, each
  /// prefilled with what was done in the same set last time (not yet done).
  WorkoutExercise _forRoutine(WorkoutExercise template) {
    final planned = template.sets.isEmpty ? 1 : template.sets.length;
    final last = lastPerformance(state.sessions, template.exerciseId);
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
    final last = lastPerformance(state.sessions, template.exerciseId);
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

  Future<void> _update(WorkoutSession Function(WorkoutSession s) change) async {
    final current = state.active;
    if (current == null) return;
    final next = change(current);
    await _repo.saveActiveSession(next);
    emit(state.copyWith(active: next));
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

  Future<void> removeExercise(int index) =>
      _update((s) => s.copyWith(exercises: [...s.exercises]..removeAt(index)));

  Future<void> _updateExercise(
    int index,
    WorkoutExercise Function(WorkoutExercise e) change,
  ) => _update((s) {
    final list = [...s.exercises];
    list[index] = change(list[index]);
    return s.copyWith(exercises: list);
  });

  Future<void> addSet(int exerciseIndex) => _updateExercise(exerciseIndex, (e) {
    // A new set starts from the one above it, the usual next step.
    final seed = e.sets.isEmpty
        ? const SetEntry()
        : SetEntry(weightKg: e.sets.last.weightKg, reps: e.sets.last.reps);
    return e.copyWith(sets: [...e.sets, seed]);
  });

  Future<void> removeSet(int exerciseIndex, int setIndex) => _updateExercise(
    exerciseIndex,
    (e) => e.copyWith(sets: [...e.sets]..removeAt(setIndex)),
  );

  Future<void> updateSet(
    int exerciseIndex,
    int setIndex,
    SetEntry Function(SetEntry s) change,
  ) => _updateExercise(exerciseIndex, (e) {
    final sets = [...e.sets];
    sets[setIndex] = change(sets[setIndex]);
    return e.copyWith(sets: sets);
  });

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
    emit(state.copyWith(exercises: await _repo.getExercises()));
  }

  Future<void> deleteExercise(String id) async {
    await _repo.deleteExercise(id);
    emit(state.copyWith(exercises: await _repo.getExercises()));
  }
}
