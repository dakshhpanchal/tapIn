import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/gym/data/gym_repository.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';
import 'package:uuid/uuid.dart';

class GymState extends Equatable {
  final bool loaded;
  final List<WorkoutSession> sessions; // finished, newest first
  final List<Routine> routines;
  final List<Exercise> exercises;
  final WorkoutSession? active;
  final bool useLb;

  const GymState({
    this.loaded = false,
    this.sessions = const [],
    this.routines = const [],
    this.exercises = const [],
    this.active,
    this.useLb = false,
  });

  GymState copyWith({
    bool? loaded,
    List<WorkoutSession>? sessions,
    List<Routine>? routines,
    List<Exercise>? exercises,
    WorkoutSession? active,
    bool clearActive = false,
    bool? useLb,
  }) => GymState(
    loaded: loaded ?? this.loaded,
    sessions: sessions ?? this.sessions,
    routines: routines ?? this.routines,
    exercises: exercises ?? this.exercises,
    active: clearActive ? null : (active ?? this.active),
    useLb: useLb ?? this.useLb,
  );

  @override
  List<Object?> get props => [
    loaded,
    sessions,
    routines,
    exercises,
    active,
    useLb,
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
      ),
    );
  }

  // Starting a workout ------------------------------------------------------

  Future<void> startEmptyWorkout() => _start('Workout', const []);

  Future<void> startFromRoutine(Routine routine) => _start(
    routine.name,
    [for (final e in routine.exercises) _withHistory(e)],
  );

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

  /// [template] with its sets replaced by what was done last time (as new,
  /// unfinished sets) when there is history, otherwise its own sets, or one
  /// empty set.
  WorkoutExercise _withHistory(WorkoutExercise template) {
    final last = lastPerformance(state.sessions, template.exerciseId);
    final source = last == null
        ? template.sets
        : [
            for (final s in last.sets.where((s) => !s.warmup))
              SetEntry(weightKg: s.weightKg, reps: s.reps),
          ];
    return template.copyWith(
      sets: source.isEmpty
          ? const [SetEntry()]
          : [for (final s in source) s.copyWith(done: false)],
    );
  }

  // Editing the workout in progress -------------------------------------------

  Future<void> _update(
    WorkoutSession Function(WorkoutSession s) change,
  ) async {
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

  Future<void> removeExercise(int index) => _update(
    (s) => s.copyWith(exercises: [...s.exercises]..removeAt(index)),
  );

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

  Future<void> removeSet(int exerciseIndex, int setIndex) =>
      _updateExercise(
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
          if (e.sets.any((s) => s.done))
            e.copyWith(sets: [for (final s in e.sets) if (s.done) s]),
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

  // History, routines and exercises -------------------------------------------

  Future<void> deleteSession(String id) async {
    await _repo.deleteSession(id);
    emit(
      state.copyWith(sessions: [...state.sessions]..removeWhere((s) => s.id == id)),
    );
  }

  Future<void> saveAsRoutine(WorkoutSession session, String name) async {
    final routine = Routine(
      id: _uuid.v4(),
      name: name,
      exercises: [
        for (final e in session.exercises)
          e.copyWith(
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

  Future<void> deleteRoutine(String id) async {
    await _repo.deleteRoutine(id);
    emit(state.copyWith(routines: _repo.getRoutines()));
  }

  Future<Exercise> createExercise({
    required String name,
    required MuscleGroup muscle,
    required ExerciseKind kind,
  }) async {
    final exercise = Exercise(
      id: _uuid.v4(),
      name: name.trim(),
      muscle: muscle,
      kind: kind,
      isCustom: true,
    );
    await _repo.saveExercise(exercise);
    emit(state.copyWith(exercises: await _repo.getExercises()));
    return exercise;
  }

  Future<void> deleteExercise(String id) async {
    await _repo.deleteExercise(id);
    emit(state.copyWith(exercises: await _repo.getExercises()));
  }
}
