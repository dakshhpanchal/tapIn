import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/features/gym/data/exercise_seed.dart';
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

  /// All exercises, seeding the built-in library on first use. Built-ins that
  /// the user hasn't seen yet (a newer library) are added without touching
  /// existing ones.
  Future<List<Exercise>> getExercises() async {
    final seeds = buildSeedExercises();
    final missing = {
      for (final e in seeds)
        if (!_exerciseBox.containsKey(e.id)) e.id: _encode(e.toJson()),
    };
    if (missing.isNotEmpty) await _exerciseBox.putAll(missing);
    final all = [
      for (final raw in _exerciseBox.values) Exercise.fromJson(_decode(raw)),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  Future<void> saveExercise(Exercise e) =>
      _exerciseBox.put(e.id, _encode(e.toJson()));

  /// Only custom exercises can be deleted; logged history keeps its name.
  Future<void> deleteExercise(String id) async {
    final raw = _exerciseBox.get(id);
    if (raw == null || !Exercise.fromJson(_decode(raw)).isCustom) return;
    await _exerciseBox.delete(id);
  }

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

  // Routines --------------------------------------------------------------

  List<Routine> getRoutines() =>
      [for (final raw in _routineBox.values) Routine.decode(raw)]..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

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
  static Map<String, dynamic> _decode(String raw) => jsonDecode(raw) as Map<String, dynamic>;
}
