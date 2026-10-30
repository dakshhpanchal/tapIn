// Pure helpers behind the Trends cards — kept Flutter-free so they can be
// unit-tested directly. The presentation layer decides what's "on track"
// (it needs theme colours) and hands the resulting date set in here.

/// The last day Trends counts: yesterday. Today is still being logged, so a
/// half-filled day would drag the averages, the streak and the charts down;
/// it joins the numbers once it is over.
DateTime trendsEndDay([DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month, n.day - 1);
}

/// Current and longest run of on-track days within [windowStart]..[today]
/// (both date-only, inclusive). A day not present in [onTrackDays] — whether
/// off-track or simply untracked — breaks the run. [current] counts the run
/// ending at [today]; if today isn't on track it's 0.
({int current, int longest}) streakStats(
  Set<DateTime> onTrackDays,
  DateTime windowStart,
  DateTime today,
) {
  final total = today.difference(windowStart).inDays;
  if (total < 0) return (current: 0, longest: 0);

  var longest = 0;
  var run = 0;
  for (var i = 0; i <= total; i++) {
    final day = DateTime(windowStart.year, windowStart.month, windowStart.day + i);
    if (onTrackDays.contains(day)) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }

  var current = 0;
  for (var i = 0; i <= total; i++) {
    final day = DateTime(today.year, today.month, today.day - i);
    if (onTrackDays.contains(day)) {
      current++;
    } else {
      break;
    }
  }

  return (current: current, longest: longest);
}

/// Linear trend through weight [points] (sorted ascending by date), returning
/// the weekly rate of change and, when a [targetKg] is set and the trend moves
/// toward it, a whole-week estimate of when it'll be reached.
///
/// Returns null when there's too little data (fewer than two points) to draw a
/// line. [weeksToTarget] is null when there's no target, the weight is flat, or
/// the trend is moving away from the target (so we don't promise a date the
/// user isn't heading for).
({double ratePerWeek, int? weeksToTarget})? weightProjection(
  List<({DateTime date, double kg})> points,
  double? targetKg,
) {
  if (points.length < 2) return null;

  final first = points.first.date;
  final xs = [
    for (final p in points) p.date.difference(first).inDays.toDouble(),
  ];
  final ys = [for (final p in points) p.kg];
  final n = points.length;
  final meanX = xs.reduce((a, b) => a + b) / n;
  final meanY = ys.reduce((a, b) => a + b) / n;

  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < n; i++) {
    numerator += (xs[i] - meanX) * (ys[i] - meanY);
    denominator += (xs[i] - meanX) * (xs[i] - meanX);
  }
  final slopePerDay = denominator == 0 ? 0.0 : numerator / denominator;
  final ratePerWeek = slopePerDay * 7;

  int? weeksToTarget;
  if (targetKg != null && slopePerDay.abs() > 1e-6) {
    final current = ys.last;
    final daysToTarget = (targetKg - current) / slopePerDay;
    // Only project when heading toward the target and within a sane horizon.
    if (daysToTarget > 0 && daysToTarget < 3650) {
      weeksToTarget = (daysToTarget / 7).ceil();
    }
  }

  return (ratePerWeek: ratePerWeek, weeksToTarget: weeksToTarget);
}

/// One tracked day reduced to the numbers the Trends averages need.
typedef DaySample = ({
  DateTime day,
  double kcal,
  double goal,
  double carbs,
  double fat,
  double protein,
});

/// Averages over the logged days of one period (a week, a month, or the
/// whole window). Untracked days are left out rather than counted as 0, so a
/// day without logging doesn't drag the average down.
typedef PeriodStats = ({
  DateTime start,
  int loggedDays,
  double avgKcal,
  double avgGoal,
  double avgCarbs,
  double avgFat,
  double avgProtein,
});

/// A day counts as logged once any energy was tracked on it.
bool isLoggedDay(DaySample s) => s.kcal > 0;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday of the week containing [d].
DateTime weekStartOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

DateTime monthStartOf(DateTime d) => DateTime(d.year, d.month);

/// Averages the logged days in [samples], or null when none were logged.
PeriodStats? periodStats(DateTime start, Iterable<DaySample> samples) {
  final logged = samples.where(isLoggedDay).toList();
  if (logged.isEmpty) return null;
  double avg(double Function(DaySample) f) =>
      logged.map(f).reduce((a, b) => a + b) / logged.length;
  return (
    start: start,
    loggedDays: logged.length,
    avgKcal: avg((s) => s.kcal),
    avgGoal: avg((s) => s.goal),
    avgCarbs: avg((s) => s.carbs),
    avgFat: avg((s) => s.fat),
    avgProtein: avg((s) => s.protein),
  );
}

/// Groups [samples] by [periodStartOf] and averages each group, oldest first.
/// Periods without a logged day are omitted.
List<PeriodStats> groupedStats(
  Iterable<DaySample> samples,
  DateTime Function(DateTime) periodStartOf,
) {
  final groups = <DateTime, List<DaySample>>{};
  for (final s in samples) {
    groups.putIfAbsent(periodStartOf(_dateOnly(s.day)), () => []).add(s);
  }
  final starts = groups.keys.toList()..sort();
  return [
    for (final start in starts)
      ?periodStats(start, groups[start]!),
  ];
}

/// Share of logged days whose energy landed within [tolerance] of the goal.
/// Null when there are no logged days with a goal.
double? adherence(Iterable<DaySample> samples, {double tolerance = 0.1}) {
  final logged = samples.where((s) => isLoggedDay(s) && s.goal > 0).toList();
  if (logged.isEmpty) return null;
  final hits = logged.where((s) => (s.kcal - s.goal).abs() <= s.goal * tolerance);
  return hits.length / logged.length;
}
