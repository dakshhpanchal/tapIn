import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/features/gym/domain/gym_models.dart';

/// Reads and writes gym data. Everything is stored as JSON strings in
/// encrypted boxes opened by `HiveDBProvider`, so the gym feature doesn't need
/// generated Hive adapters and its records can evolve without a migration.
class GymRepository {
  static const _activeKey = 'active';

  final Box<String> _exerciseBox;
  final Box<String> _sessionBox;
  final Box<String> _routineBox;
  final Box<String> _metaBox;

  GymRepository(
    this._exerciseBox,
    this._sessionBox,
    this._routineBox,
    this._metaBox,
  );

  // Exercises -----------------------------------------------------------

  /// The user's exercises, A to Z. There is no built-in list: the user adds
  /// their own. An earlier build seeded a library with `seed_` ids; those are
  /// removed here so it doesn't linger (logged workouts keep their own copy of
  /// the exercise name, so history is unaffected).
  Future<List<Exercise>> getExercises() async {
    final seeded = _exerciseBox.keys
        .where((k) => k is String && k.startsWith('seed_'))
        .toList();
    if (seeded.isNotEmpty) await _exerciseBox.deleteAll(seeded);
    return [
      for (final raw in _exerciseBox.values) Exercise.fromJson(_decode(raw)),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> saveExercise(Exercise e) =>
      _exerciseBox.put(e.id, _encode(e.toJson()));

  /// Logged workouts keep their own copy of the name, so history survives.
  Future<void> deleteExercise(String id) => _exerciseBox.delete(id);

  // Sessions ------------------------------------------------------------

  /// Finished sessions, newest first.
  List<WorkoutSession> getSessions() =>
      [for (final raw in _sessionBox.values) WorkoutSession.decode(raw)]
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  Future<void> saveSession(WorkoutSession s) =>
      _sessionBox.put(s.id, s.encode());

  Future<void> deleteSession(String id) => _sessionBox.delete(id);

  // The workout in progress ------------------------------------------------

  WorkoutSession? getActiveSession() {
    final raw = _metaBox.get(_activeKey);
    return raw == null ? null : WorkoutSession.decode(raw);
  }

  Future<void> saveActiveSession(WorkoutSession s) =>
      _metaBox.put(_activeKey, s.encode());

  Future<void> clearActiveSession() => _metaBox.delete(_activeKey);

  // Rest days ---------------------------------------------------------------

  static const _restDaysKey = 'rest_days';

  /// The days logged as rest days, as `yyyy-MM-dd`.
  Set<String> getRestDays() {
    final raw = _metaBox.get(_restDaysKey);
    if (raw == null) return {};
    return {for (final d in jsonDecode(raw) as List) d as String};
  }

  Future<void> saveRestDays(Set<String> days) =>
      _metaBox.put(_restDaysKey, jsonEncode(days.toList()..sort()));

  // Routines --------------------------------------------------------------

  List<Routine> getRoutines() =>
      [for (final raw in _routineBox.values) Routine.decode(raw)]..sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0
            ? byOrder
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

  Future<void> saveRoutine(Routine r) => _routineBox.put(r.id, r.encode());

  Future<void> deleteRoutine(String id) => _routineBox.delete(id);

  /// Wipes all gym data, for "delete all data".
  Future<void> clearAll() async {
    await _exerciseBox.clear();
    await _sessionBox.clear();
    await _routineBox.clear();
    await _metaBox.clear();
  }

  static String _encode(Map<String, dynamic> json) => jsonEncode(json);
  static Map<String, dynamic> _decode(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;
}
