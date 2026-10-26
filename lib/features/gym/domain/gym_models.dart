import 'dart:convert';

/// Muscle groups an exercise is filed under, in the order the picker lists
/// them.
enum MuscleGroup {
  chest('Chest'),
  back('Back'),
  shoulders('Shoulders'),
  biceps('Biceps'),
  triceps('Triceps'),
  forearms('Forearms'),
  quads('Quads'),
  hamstrings('Hamstrings'),
  glutes('Glutes'),
  calves('Calves'),
  abs('Abs'),
  fullBody('Full body');

  final String label;
  const MuscleGroup(this.label);

  static MuscleGroup fromName(String? name) => MuscleGroup.values.firstWhere(
    (m) => m.name == name,
    orElse: () => MuscleGroup.fullBody,
  );
}

/// How an exercise is logged: weight × reps, or reps with optional extra
/// weight (pull-ups, dips).
enum ExerciseKind {
  weighted,
  bodyweight;

  static ExerciseKind fromName(String? name) => ExerciseKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => ExerciseKind.weighted,
  );
}

class Exercise {
  final String id;
  final String name;
  final MuscleGroup muscle;
  final ExerciseKind kind;
  final String equipment;
  final bool isCustom;

  /// Weight is logged in machine plates (stack position), not kg or lb.
  final bool plates;

  const Exercise({
    required this.id,
    required this.name,
    required this.muscle,
    this.kind = ExerciseKind.weighted,
    this.equipment = '',
    this.isCustom = false,
    this.plates = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'muscle': muscle.name,
    'kind': kind.name,
    'equipment': equipment,
    'isCustom': isCustom,
    'plates': plates,
  };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    name: json['name'] as String,
    muscle: MuscleGroup.fromName(json['muscle'] as String?),
    kind: ExerciseKind.fromName(json['kind'] as String?),
    equipment: (json['equipment'] as String?) ?? '',
    isCustom: (json['isCustom'] as bool?) ?? false,
    plates: (json['plates'] as bool?) ?? false,
  );
}

/// One set. Weight is always stored in kilograms; the UI converts for display.
class SetEntry {
  final double weightKg;
  final int reps;
  final bool done;
  final bool warmup;

  const SetEntry({
    this.weightKg = 0,
    this.reps = 0,
    this.done = false,
    this.warmup = false,
  });

  SetEntry copyWith({double? weightKg, int? reps, bool? done, bool? warmup}) =>
      SetEntry(
        weightKg: weightKg ?? this.weightKg,
        reps: reps ?? this.reps,
        done: done ?? this.done,
        warmup: warmup ?? this.warmup,
      );

  Map<String, dynamic> toJson() => {
    'w': weightKg,
    'r': reps,
    'd': done,
    'wu': warmup,
  };

  factory SetEntry.fromJson(Map<String, dynamic> json) => SetEntry(
    weightKg: (json['w'] as num?)?.toDouble() ?? 0,
    reps: (json['r'] as num?)?.toInt() ?? 0,
    done: (json['d'] as bool?) ?? false,
    warmup: (json['wu'] as bool?) ?? false,
  );
}

/// An exercise inside a workout (or routine), with the name and muscle group
/// copied in so history stays readable if the exercise is later renamed or
/// deleted.
class WorkoutExercise {
  final String exerciseId;
  final String name;
  final MuscleGroup muscle;
  final ExerciseKind kind;
  final List<SetEntry> sets;

  /// A note for next time, shown the next time this exercise comes up.
  final String note;

  /// Free text for the machine or equipment setup (seat height, pin, grip).
  final String setting;

  /// Weights are machine plates; `SetEntry.weightKg` then holds the plate
  /// count as is, with no kg/lb conversion.
  final bool plates;

  /// Skipped for today: kept in the workout so it can be brought back, but
  /// left out when the workout is finished.
  final bool skipped;

  const WorkoutExercise({
    required this.exerciseId,
    required this.name,
    required this.muscle,
    this.kind = ExerciseKind.weighted,
    this.sets = const [],
    this.note = '',
    this.setting = '',
    this.plates = false,
    this.skipped = false,
  });

  factory WorkoutExercise.of(Exercise e, {List<SetEntry> sets = const []}) =>
      WorkoutExercise(
        exerciseId: e.id,
        name: e.name,
        muscle: e.muscle,
        kind: e.kind,
        sets: sets,
        plates: e.plates,
      );

  WorkoutExercise copyWith({
    List<SetEntry>? sets,
    String? note,
    String? setting,
    bool? plates,
    bool? skipped,
  }) => WorkoutExercise(
    exerciseId: exerciseId,
    name: name,
    muscle: muscle,
    kind: kind,
    sets: sets ?? this.sets,
    note: note ?? this.note,
    setting: setting ?? this.setting,
    plates: plates ?? this.plates,
    skipped: skipped ?? this.skipped,
  );

  Map<String, dynamic> toJson() => {
    'exerciseId': exerciseId,
    'name': name,
    'muscle': muscle.name,
    'kind': kind.name,
    'sets': [for (final s in sets) s.toJson()],
    'note': note,
    'setting': setting,
    'plates': plates,
    if (skipped) 'skipped': true,
  };

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) =>
      WorkoutExercise(
        exerciseId: json['exerciseId'] as String,
        name: json['name'] as String,
        muscle: MuscleGroup.fromName(json['muscle'] as String?),
        kind: ExerciseKind.fromName(json['kind'] as String?),
        sets: [
          for (final s in (json['sets'] as List? ?? const []))
            SetEntry.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        note: (json['note'] as String?) ?? '',
        setting: (json['setting'] as String?) ?? '',
        plates: (json['plates'] as bool?) ?? false,
        skipped: (json['skipped'] as bool?) ?? false,
      );
}

class WorkoutSession {
  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String notes;
  final List<WorkoutExercise> exercises;

  const WorkoutSession({
    required this.id,
    required this.name,
    required this.startedAt,
    this.endedAt,
    this.notes = '',
    this.exercises = const [],
  });

  bool get isFinished => endedAt != null;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  WorkoutSession copyWith({
    String? name,
    DateTime? endedAt,
    String? notes,
    List<WorkoutExercise>? exercises,
  }) => WorkoutSession(
    id: id,
    name: name ?? this.name,
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    notes: notes ?? this.notes,
    exercises: exercises ?? this.exercises,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'notes': notes,
    'exercises': [for (final e in exercises) e.toJson()],
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String,
    name: json['name'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    endedAt: json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt'] as String),
    notes: (json['notes'] as String?) ?? '',
    exercises: [
      for (final e in (json['exercises'] as List? ?? const []))
        WorkoutExercise.fromJson(Map<String, dynamic>.from(e as Map)),
    ],
  );

  String encode() => jsonEncode(toJson());
  factory WorkoutSession.decode(String raw) =>
      WorkoutSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// A reusable workout plan: the exercises and how many sets to start with.
class Routine {
  final String id;
  final String name;
  final List<WorkoutExercise> exercises;

  /// Position in the "My workouts" list; the user can reorder it.
  final int order;

  const Routine({
    required this.id,
    required this.name,
    this.exercises = const [],
    this.order = 0,
  });

  Routine copyWith({List<WorkoutExercise>? exercises, int? order}) => Routine(
    id: id,
    name: name,
    exercises: exercises ?? this.exercises,
    order: order ?? this.order,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'exercises': [for (final e in exercises) e.toJson()],
    'order': order,
  };

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
    id: json['id'] as String,
    name: json['name'] as String,
    exercises: [
      for (final e in (json['exercises'] as List? ?? const []))
        WorkoutExercise.fromJson(Map<String, dynamic>.from(e as Map)),
    ],
    order: (json['order'] as num?)?.toInt() ?? 0,
  );

  String encode() => jsonEncode(toJson());
  factory Routine.decode(String raw) =>
      Routine.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
