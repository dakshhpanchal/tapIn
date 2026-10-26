import 'dart:convert';

import 'package:opennutritracker/features/gym/domain/gym_models.dart';

/// Moving workouts in and out as one JSON file.
///
/// The file is meant to be easy to write by hand or generate: only names and
/// numbers, weights in kilograms, exercises referred to by name. Anything not
/// in your list yet is created on import.
///
/// ```json
/// {
///   "format": "tapin-workouts", "version": 1,
///   "exercises": [{"name": "Bench Press", "muscle": "chest"}],
///   "workouts": [
///     {"name": "Push day", "exercises": [
///       {"exercise": "Bench Press", "sets": 3},
///       {"exercise": "Overhead Press", "sets": [{"weight": 40, "reps": 8}]}
///     ]}
///   ],
///   "history": [
///     {"name": "Push day", "date": "2026-10-20T18:05:00", "durationMinutes": 55,
///      "exercises": [{"exercise": "Bench Press", "setting": "Seat 4",
///        "note": "Go heavier", "sets": [{"weight": 60, "reps": 8}]}]}
///   ]
/// }
/// ```
///
/// Per exercise: `"plates": true` means the weights are machine plates (the
/// stack position) rather than kg, and `"setting"` is free text for the
/// machine setup. `"sets"` is a number (that many empty sets) or a list with a
/// `weight` and `reps` per set; leave `reps` at 0 for a plan, the reps are
/// logged when the workout is done.
const gymTransferFormat = 'tapin-workouts';
const gymTransferVersion = 1;

/// A readable problem with the file as a whole (not valid JSON, wrong format).
class GymImportException implements Exception {
  final String message;
  const GymImportException(this.message);
  @override
  String toString() => message;
}

/// What an import would write, and what it did not understand.
class GymImportPlan {
  final List<Exercise> newExercises;

  /// Exercises you already had whose name spelling, muscle group or plates
  /// setting the file changes. The file is the source of truth for those.
  final List<Exercise> updatedExercises;
  final List<Routine> workouts;
  final int workoutsUpdated;
  final List<WorkoutSession> sessions;
  final int sessionsSkipped;
  final List<String> warnings;

  const GymImportPlan({
    required this.newExercises,
    this.updatedExercises = const [],
    required this.workouts,
    required this.workoutsUpdated,
    required this.sessions,
    required this.sessionsSkipped,
    required this.warnings,
  });

  bool get isEmpty =>
      newExercises.isEmpty &&
      updatedExercises.isEmpty &&
      workouts.isEmpty &&
      sessions.isEmpty;
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

MuscleGroup? _muscle(Object? raw) {
  if (raw is! String) return null;
  final key = _norm(raw).replaceAll(' ', '');
  for (final m in MuscleGroup.values) {
    if (m.name.toLowerCase() == key ||
        _norm(m.label).replaceAll(' ', '') == key) {
      return m;
    }
  }
  return null;
}

double _number(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v'.replaceAll(',', '.')) ?? 0;

/// Builds the JSON text for [exercises], [routines] (as "workouts") and
/// finished [sessions] (as "history").
String exportGymJson({
  required List<Exercise> exercises,
  required List<Routine> routines,
  required List<WorkoutSession> sessions,
}) {
  Object plannedSets(List<SetEntry> sets) =>
      sets.every((s) => s.weightKg == 0 && s.reps == 0)
      ? sets.length
      : [
          for (final s in sets) {'weight': s.weightKg, 'reps': s.reps},
        ];

  final data = {
    'format': gymTransferFormat,
    'version': gymTransferVersion,
    'exercises': [
      for (final e in exercises)
        {'name': e.name, 'muscle': e.muscle.name, if (e.plates) 'plates': true},
    ],
    'workouts': [
      for (final r in routines)
        {
          'name': r.name,
          'exercises': [
            for (final e in r.exercises)
              {
                'exercise': e.name,
                if (e.plates) 'plates': true,
                if (e.setting.isNotEmpty) 'setting': e.setting,
                if (e.planNote.isNotEmpty) 'note': e.planNote,
                'sets': plannedSets(e.sets),
              },
          ],
        },
    ],
    'history': [
      for (final s in sessions.where((s) => s.isFinished))
        {
          'name': s.name,
          'date': s.startedAt.toIso8601String(),
          'durationMinutes': s.duration.inMinutes,
          if (s.notes.isNotEmpty) 'notes': s.notes,
          'exercises': [
            for (final e in s.exercises)
              {
                'exercise': e.name,
                if (e.plates) 'plates': true,
                if (e.setting.isNotEmpty) 'setting': e.setting,
                if (e.note.isNotEmpty) 'note': e.note,
                'sets': [
                  for (final set in e.sets)
                    {
                      'weight': set.weightKg,
                      'reps': set.reps,
                      if (set.warmup) 'warmup': true,
                    },
                ],
              },
          ],
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// Reads an import file against what already exists.
///
/// Matching is by name, ignoring case and extra spaces: exercises you already
/// have are reused, a workout with the same name as one you have replaces it,
/// and a logged session with the same date and name is skipped, so importing
/// the same file twice changes nothing. Entries that can't be understood are
/// left out and reported in [GymImportPlan.warnings]; the rest still import.
GymImportPlan parseGymImport(
  String raw, {
  required List<Exercise> exercises,
  required List<Routine> routines,
  required List<WorkoutSession> sessions,
  required String Function() newId,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const GymImportException('This is not a valid JSON file.');
  }
  if (decoded is! Map) {
    throw const GymImportException(
      'Expected a JSON object with "workouts" and/or "history".',
    );
  }
  final Map root = decoded;
  final format = root['format'];
  if (format != null && format != gymTransferFormat) {
    throw GymImportException(
      'This file is "$format", not a $gymTransferFormat file.',
    );
  }
  final version = root['version'];
  if (version is num && version > gymTransferVersion) {
    throw const GymImportException(
      'This file was made by a newer version of the app.',
    );
  }

  final warnings = <String>[];
  final byName = {for (final e in exercises) _norm(e.name): e};
  final created = <Exercise>[];
  final changed = <String, Exercise>{};
  final declaredMuscle = <String, MuscleGroup>{};

  List<dynamic> listOf(String key) {
    final v = root[key];
    if (v == null) return const [];
    if (v is List) return v;
    warnings.add('"$key" should be a list, so it was skipped.');
    return const [];
  }

  for (final entry in listOf('exercises')) {
    final name = entry is String
        ? entry
        : (entry is Map ? entry['name'] : null);
    if (name is! String || name.trim().isEmpty) continue;
    final muscle = entry is Map ? _muscle(entry['muscle']) : null;
    if (muscle != null) declaredMuscle[_norm(name)] = muscle;
    _resolve(
      name,
      byName,
      created,
      changed,
      declaredMuscle,
      newId,
      plates: entry is Map && entry['plates'] == true,
      muscle: muscle,
    );
  }

  Exercise? exerciseFor(
    Object? name, {
    bool plates = false,
    MuscleGroup? muscle,
  }) {
    if (name is! String || name.trim().isEmpty) return null;
    return _resolve(
      name,
      byName,
      created,
      changed,
      declaredMuscle,
      newId,
      plates: plates,
      muscle: muscle,
    );
  }

  // Planned workouts -----------------------------------------------------
  final routineByName = {for (final r in routines) _norm(r.name): r};
  // Workouts new to the list go after the existing ones, in file order.
  var nextOrder = routines.isEmpty
      ? 0
      : routines.map((r) => r.order).reduce((a, b) => a > b ? a : b) + 1;
  final workouts = <Routine>[];
  var updated = 0;
  final w = listOf('workouts');
  for (var i = 0; i < w.length; i++) {
    final item = w[i];
    final label = 'Workout ${i + 1}';
    if (item is! Map || '${item['name'] ?? ''}'.trim().isEmpty) {
      warnings.add('$label has no name, so it was skipped.');
      continue;
    }
    final name = '${item['name']}'.trim();
    final planned = <WorkoutExercise>[];
    for (final ex in (item['exercises'] as List? ?? const [])) {
      final map = ex is Map ? ex : {'exercise': ex};
      final usesPlates = map['plates'] == true;
      final exercise = exerciseFor(
        map['exercise'] ?? map['name'],
        plates: usesPlates,
        muscle: _muscle(map['muscle']),
      );
      if (exercise == null) {
        warnings.add('"$name": an exercise without a name was skipped.');
        continue;
      }
      final sets = map['sets'];
      final list = <SetEntry>[
        if (sets is num)
          for (var n = 0; n < sets.toInt().clamp(1, 50); n++) const SetEntry()
        else if (sets is List)
          for (final s in sets)
            if (s is Map)
              SetEntry(
                weightKg: _number(s['weight']),
                reps: _number(s['reps']).round(),
              )
            else
              const SetEntry()
        else
          const SetEntry(),
      ];
      planned.add(
        WorkoutExercise.of(
          exercise,
          sets: list.isEmpty ? const [SetEntry()] : list,
        ).copyWith(
          setting: '${map['setting'] ?? ''}'.trim(),
          planNote: '${map['note'] ?? ''}'.trim(),
          plates: usesPlates,
        ),
      );
    }
    if (planned.isEmpty) {
      warnings.add('"$name" has no exercises, so it was skipped.');
      continue;
    }
    final existing = routineByName[_norm(name)];
    if (existing != null) updated++;
    workouts.add(
      Routine(
        id: existing?.id ?? newId(),
        name: name,
        exercises: planned,
        order: existing?.order ?? nextOrder++,
      ),
    );
  }

  // Logged history -------------------------------------------------------
  String key(DateTime d, String n) => '${d.toIso8601String()}|${_norm(n)}';
  final known = {for (final s in sessions) key(s.startedAt, s.name)};
  final imported = <WorkoutSession>[];
  var skipped = 0;
  final h = listOf('history');
  for (var i = 0; i < h.length; i++) {
    final item = h[i];
    final label = 'History entry ${i + 1}';
    if (item is! Map) {
      warnings.add('$label is not an object, so it was skipped.');
      continue;
    }
    final started = DateTime.tryParse(
      '${item['date'] ?? item['startedAt'] ?? ''}',
    );
    if (started == null) {
      warnings.add(
        '$label has no valid "date" (like 2026-10-20T18:05:00), so it was skipped.',
      );
      continue;
    }
    final name = '${item['name'] ?? 'Workout'}'.trim();
    final logged = <WorkoutExercise>[];
    for (final ex in (item['exercises'] as List? ?? const [])) {
      if (ex is! Map) continue;
      final usesPlates = ex['plates'] == true;
      final exercise = exerciseFor(
        ex['exercise'] ?? ex['name'],
        plates: usesPlates,
        muscle: _muscle(ex['muscle']),
      );
      if (exercise == null) continue;
      final sets = <SetEntry>[
        for (final s in (ex['sets'] as List? ?? const []))
          if (s is Map && _number(s['reps']) > 0)
            SetEntry(
              weightKg: _number(s['weight']),
              reps: _number(s['reps']).round(),
              done: true,
              warmup: s['warmup'] == true,
            ),
      ];
      if (sets.isEmpty) continue;
      logged.add(
        WorkoutExercise.of(exercise, sets: sets).copyWith(
          setting: '${ex['setting'] ?? ''}'.trim(),
          note: '${ex['note'] ?? ''}'.trim(),
          plates: usesPlates,
        ),
      );
    }
    if (logged.isEmpty) {
      warnings.add(
        '$label ("$name") has no sets with reps, so it was skipped.',
      );
      continue;
    }
    if (!known.add(key(started, name))) {
      skipped++;
      continue;
    }
    final minutes = _number(item['durationMinutes']).round();
    imported.add(
      WorkoutSession(
        id: newId(),
        name: name,
        startedAt: started,
        endedAt: started.add(Duration(minutes: minutes < 0 ? 0 : minutes)),
        notes: '${item['notes'] ?? ''}'.trim(),
        exercises: logged,
      ),
    );
  }

  return GymImportPlan(
    newExercises: created,
    updatedExercises: [
      for (final e in changed.values)
        if (!created.any((c) => c.id == e.id)) e,
    ],
    workouts: workouts,
    workoutsUpdated: updated,
    sessions: imported,
    sessionsSkipped: skipped,
    warnings: warnings,
  );
}

Exercise _resolve(
  String name,
  Map<String, Exercise> byName,
  List<Exercise> created,
  Map<String, Exercise> changed,
  Map<String, MuscleGroup> declaredMuscle,
  String Function() newId, {
  bool plates = false,
  MuscleGroup? muscle,
}) {
  final key = _norm(name);
  final cleaned = name.trim();
  if (muscle != null) declaredMuscle.putIfAbsent(key, () => muscle);
  final found = byName[key];
  if (found != null) {
    // An exercise you already have follows the file where the file says
    // something: the spelling of its name, a declared muscle group, plates.
    // One created earlier in this same file keeps the spelling it first had.
    final createdHere = created.any((c) => c.id == found.id);
    final newMuscle = muscle ?? declaredMuscle[key];
    final renamed = !createdHere && found.name != cleaned;
    final remuscled = newMuscle != null && newMuscle != found.muscle;
    final newlyPlates = plates && !found.plates;
    if (!renamed && !remuscled && !newlyPlates) return found;
    final updated = Exercise(
      id: found.id,
      name: renamed ? cleaned : found.name,
      muscle: newMuscle ?? found.muscle,
      kind: found.kind,
      equipment: found.equipment,
      isCustom: found.isCustom,
      plates: found.plates || plates,
    );
    byName[key] = updated;
    final at = created.indexWhere((c) => c.id == found.id);
    if (at >= 0) {
      created[at] = updated;
    } else {
      changed[found.id] = updated;
    }
    return updated;
  }
  final exercise = Exercise(
    id: newId(),
    name: cleaned,
    muscle: declaredMuscle[key] ?? MuscleGroup.fullBody,
    isCustom: true,
    plates: plates,
  );
  byName[key] = exercise;
  created.add(exercise);
  return exercise;
}

/// A starter file for the import dialog: copy it, fill in your own workouts.
const gymImportExample = '''{
  "format": "tapin-workouts",
  "version": 1,
  "workouts": [
    {
      "name": "Push Day",
      "exercises": [
        {"exercise": "Bench Press", "muscle": "chest", "sets": [{"weight": 60, "reps": 0}, {"weight": 60, "reps": 0}, {"weight": 60, "reps": 0}]},
        {"exercise": "Pec Deck", "muscle": "chest", "plates": true, "setting": "Seat 3", "sets": [{"weight": 18, "reps": 0}, {"weight": 18, "reps": 0}]},
        {"exercise": "Overhead Press", "muscle": "shoulders", "sets": [{"weight": 40, "reps": 0}]}
      ]
    }
  ],
  "history": [
    {
      "name": "Push Day",
      "date": "2026-10-20T18:05:00",
      "durationMinutes": 55,
      "exercises": [
        {"exercise": "Bench Press", "muscle": "chest", "setting": "Flat Bench",
         "sets": [{"weight": 60, "reps": 8}, {"weight": 60, "reps": 7}]}
      ]
    }
  ]
}''';

/// Pasted into a chat together with the user's own notes, so it can write the
/// import file.
const gymImportPrompt =
    '''Convert my workouts into one JSON file for the tapIn app. Reply with only the JSON.

Rules:
- Top level: {"format": "tapin-workouts", "version": 1, "workouts": [...], "history": [...]}. "history" is optional.
- Write every workout name and exercise name in Title Case (for example "Upper", "Single Leg Extension"), never all lowercase or all caps.
- Each workout: {"name": "...", "exercises": [...]}. One entry per workout; separate workouts stay separate.
- Each exercise: {"exercise": "<Name>", "muscle": "<group>", "sets": <list>, "plates": true|false, "setting": "<text>"}.
- "muscle" is one of: chest, back, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, abs, fullBody. Pick the main muscle the exercise trains.
- "sets" is a list with one object per set: {"weight": <number>, "reps": 0}. Give every set its own weight even when they are equal. Leave "reps" at 0 unless I wrote reps.
- Weights are kilograms. If I write weights as plates (for example "8p"), set "plates": true on that exercise and use the plate number as the weight.
- Machine settings or other notes in braces go in "setting" as plain text. Omit "setting" if there is none.
- An optional "note" on a workout exercise is a standing tip shown while doing it (for example "keep elbows tucked"). Omit it if there is none.
- "history" entries (only if I give dated sessions): {"name": "...", "date": "YYYY-MM-DDTHH:MM:SS", "durationMinutes": <number>, "exercises": [{"exercise": "...", "sets": [{"weight": <number>, "reps": <number>}]}]}.

Example:
$gymImportExample''';
