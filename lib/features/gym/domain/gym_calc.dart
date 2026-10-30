import 'package:opennutritracker/features/gym/domain/gym_models.dart';

/// Epley estimate of the one-rep max. A single rep is the weight itself, and
/// anything past 12 reps is too far from a max to extrapolate, so it counts as
/// 12.
double estimateOneRepMax(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return 0;
  if (reps == 1) return weightKg;
  return weightKg * (1 + (reps > 12 ? 12 : reps) / 30);
}

/// A set that was really done: ticked, with at least one rep. A set ticked
/// with no reps is treated as skipped, not as a set of zero.
bool isLoggedSet(SetEntry s) => s.done && s.reps > 0;

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

/// The heaviest finished working set of [e], with the most reps among sets at
/// that weight: the number to compare from one workout to the next.
({double weightKg, int reps}) topSet(WorkoutExercise e) {
  var weight = 0.0;
  var reps = 0;
  for (final s in workingSets(e)) {
    if (s.weightKg > weight || (s.weightKg == weight && s.reps > reps)) {
      weight = s.weightKg;
      reps = s.reps;
    }
  }
  return (weightKg: weight, reps: reps);
}

/// One point on an exercise's progress chart: how that exercise went in one
/// finished session.
typedef ExercisePoint = ({
  DateTime date,
  double bestWeightKg,
  double oneRepMaxKg,
  double volumeKg,
  int topReps,
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
        topReps: topSet(e).reps,
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

/// The Monday of the week [d] falls in, as a date.
DateTime weekStartOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

typedef WeekCount = ({DateTime weekStart, int count});

/// Workouts finished in each of the last [weeks] weeks, oldest first, the last
/// entry being the week of [now].
List<WeekCount> workoutsPerWeek(
  Iterable<WorkoutSession> sessions,
  DateTime now, {
  int weeks = 12,
}) {
  final thisWeek = weekStartOf(now);
  final counts = <DateTime, int>{};
  for (final s in sessions) {
    if (!s.isFinished) continue;
    final w = weekStartOf(s.startedAt);
    counts[w] = (counts[w] ?? 0) + 1;
  }
  return [
    for (var i = weeks - 1; i >= 0; i--)
      (
        weekStart: DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * i),
        count:
            counts[DateTime(
              thisWeek.year,
              thisWeek.month,
              thisWeek.day - 7 * i,
            )] ??
            0,
      ),
  ];
}

/// Weeks in a row with at least one workout. The current week is not held
/// against the streak while it is still empty: counting starts from last week.
int workoutWeekStreak(List<WeekCount> weeks) {
  var i = weeks.length - 1;
  if (i >= 0 && weeks[i].count == 0) i--;
  var streak = 0;
  for (; i >= 0 && weeks[i].count > 0; i--) {
    streak++;
  }
  return streak;
}

typedef TopSet = ({double weightKg, int reps});

/// How one exercise has moved from its first logged session to its latest, as
/// the heaviest set actually done each time (weight and reps). For plate
/// machines the weight is the plate setting.
typedef ExerciseGain = ({
  String id,
  String name,
  bool plates,
  int sessions,
  TopSet first,
  TopSet latest,
});

/// Exercises done in at least two finished sessions, biggest gain first.
List<ExerciseGain> exerciseGains(Iterable<WorkoutSession> sessions) {
  final ordered = sessions.where((s) => s.isFinished).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final sets = <String, List<TopSet>>{};
  final names = <String, String>{};
  final plateFlags = <String, bool>{};
  for (final s in ordered) {
    for (final e in s.exercises) {
      if (workingSets(e).isEmpty) continue;
      final top = topSet(e);
      if (top.weightKg <= 0 && top.reps <= 0) continue;
      sets.putIfAbsent(e.exerciseId, () => []).add(top);
      names[e.exerciseId] = e.name;
      plateFlags[e.exerciseId] = e.plates;
    }
  }
  final gains = <ExerciseGain>[
    for (final entry in sets.entries)
      if (entry.value.length >= 2)
        (
          id: entry.key,
          name: names[entry.key]!,
          plates: plateFlags[entry.key]!,
          sessions: entry.value.length,
          first: entry.value.first,
          latest: entry.value.last,
        ),
  ];
  // Heavier first; at the same weight, more reps.
  double change(ExerciseGain g) => g.first.weightKg > 0
      ? (g.latest.weightKg - g.first.weightKg) / g.first.weightKg
      : 0;
  gains.sort((a, b) {
    final c = change(b).compareTo(change(a));
    return c != 0
        ? c
        : (b.latest.reps - b.first.reps).compareTo(a.latest.reps - a.first.reps);
  });
  return gains;
}

typedef RecordEntry = ({
  DateTime date,
  String exerciseName,
  Set<RecordKind> kinds,
});

/// The most recent new heaviest weights, newest first. A first-ever
/// performance is not a record.
List<RecordEntry> recentRecords(
  Iterable<WorkoutSession> sessions, {
  int limit = 8,
}) {
  final ordered = sessions.where((s) => s.isFinished).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final found = <RecordEntry>[];
  for (var i = 0; i < ordered.length; i++) {
    final records = detectRecords(ordered[i], ordered.take(i));
    for (final e in ordered[i].exercises) {
      final kinds = {...?records[e.exerciseId]}
        ..retainAll({RecordKind.weight});
      if (kinds.isNotEmpty) {
        found.add((
          date: ordered[i].startedAt,
          exerciseName: e.name,
          kinds: kinds,
        ));
      }
    }
  }
  return found.reversed.take(limit).toList();
}
