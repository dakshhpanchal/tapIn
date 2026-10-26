import 'package:opennutritracker/features/gym/domain/gym_models.dart';

/// Epley estimate of the one-rep max. A single rep is the weight itself, and
/// anything past 12 reps is too far from a max to extrapolate, so it counts as
/// 12.
double estimateOneRepMax(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return 0;
  if (reps == 1) return weightKg;
  return weightKg * (1 + (reps > 12 ? 12 : reps) / 30);
}

/// Sets that count towards volume and records: finished working sets.
Iterable<SetEntry> workingSets(WorkoutExercise e) =>
    e.sets.where((s) => s.done && !s.warmup && s.reps > 0);

/// Total weight moved (weight × reps) by the finished working sets.
///
/// Zero for plate-based exercises: a plate count times reps is not a weight,
/// and adding it to kilograms would make the total meaningless.
double exerciseVolume(WorkoutExercise e) => e.plates
    ? 0
    : workingSets(e).fold(0.0, (sum, s) => sum + s.weightKg * s.reps);

double sessionVolume(WorkoutSession s) =>
    s.exercises.fold(0.0, (sum, e) => sum + exerciseVolume(e));

int sessionSetCount(WorkoutSession s) =>
    s.exercises.fold(0, (sum, e) => sum + workingSets(e).length);

/// The heaviest finished working set weight for [e], or 0.
double bestWeight(WorkoutExercise e) =>
    workingSets(e).fold(0.0, (m, s) => s.weightKg > m ? s.weightKg : m);

double bestOneRepMax(WorkoutExercise e) => workingSets(e).fold(
  0.0,
  (m, s) => estimateOneRepMax(s.weightKg, s.reps) > m
      ? estimateOneRepMax(s.weightKg, s.reps)
      : m,
);

/// One point on an exercise's progress chart: how that exercise went in one
/// finished session.
typedef ExercisePoint = ({
  DateTime date,
  double bestWeightKg,
  double oneRepMaxKg,
  double volumeKg,
});

/// [exerciseId]'s history across finished [sessions], oldest first. Sessions
/// where it wasn't done (no finished working set) are skipped.
List<ExercisePoint> exerciseHistory(
  Iterable<WorkoutSession> sessions,
  String exerciseId,
) {
  final points = <ExercisePoint>[];
  for (final s in sessions) {
    if (!s.isFinished) continue;
    for (final e in s.exercises.where((e) => e.exerciseId == exerciseId)) {
      if (workingSets(e).isEmpty) continue;
      points.add((
        date: s.startedAt,
        bestWeightKg: bestWeight(e),
        oneRepMaxKg: bestOneRepMax(e),
        volumeKg: exerciseVolume(e),
      ));
    }
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

/// What [exerciseId] looked like the last time it was done in [sessions]
/// (excluding [excludeSessionId]), for prefilling a new workout and the "last
/// time" hint. Null when it has never been done.
WorkoutExercise? lastPerformance(
  Iterable<WorkoutSession> sessions,
  String exerciseId, {
  String? excludeSessionId,
}) {
  WorkoutSession? latest;
  WorkoutExercise? found;
  for (final s in sessions) {
    if (!s.isFinished || s.id == excludeSessionId) continue;
    for (final e in s.exercises.where((e) => e.exerciseId == exerciseId)) {
      if (workingSets(e).isEmpty) continue;
      if (latest == null || s.startedAt.isAfter(latest.startedAt)) {
        latest = s;
        found = e;
      }
    }
  }
  return found;
}

enum RecordKind { weight, oneRepMax, volume }

/// Records [session] set against everything in [before] (the finished
/// sessions that existed first): per exercise, which of heaviest weight,
/// estimated 1RM and session volume are new bests. A first-ever performance
/// is not a record, since there is nothing to beat.
Map<String, Set<RecordKind>> detectRecords(
  WorkoutSession session,
  Iterable<WorkoutSession> before,
) {
  final records = <String, Set<RecordKind>>{};
  for (final e in session.exercises) {
    final history = exerciseHistory(before, e.exerciseId);
    if (history.isEmpty || workingSets(e).isEmpty) continue;
    double maxOf(double Function(ExercisePoint) f) =>
        history.map(f).reduce((a, b) => a > b ? a : b);
    final found = <RecordKind>{
      if (bestWeight(e) > maxOf((p) => p.bestWeightKg)) RecordKind.weight,
      if (bestOneRepMax(e) > maxOf((p) => p.oneRepMaxKg)) RecordKind.oneRepMax,
      if (exerciseVolume(e) > maxOf((p) => p.volumeKg)) RecordKind.volume,
    };
    if (found.isNotEmpty) records[e.exerciseId] = found;
  }
  return records;
}

/// Finished working sets per muscle group over [sessions], for the weekly
/// balance view.
Map<MuscleGroup, int> setsPerMuscle(Iterable<WorkoutSession> sessions) {
  final counts = <MuscleGroup, int>{};
  for (final s in sessions) {
    for (final e in s.exercises) {
      final n = workingSets(e).length;
      if (n > 0) counts[e.muscle] = (counts[e.muscle] ?? 0) + n;
    }
  }
  return counts;
}

const double _kgPerLb = 0.45359237;

double kgToLb(double kg) => kg / _kgPerLb;
double lbToKg(double lb) => lb * _kgPerLb;

/// "60", "62.5" — whole numbers without a decimal point.
String formatWeight(double value) {
  final rounded = (value * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(
          rounded * 10 == (rounded * 10).roundToDouble() ? 1 : 2,
        );
}
