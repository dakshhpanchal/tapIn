import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/trends/presentation/trends_calc.dart';

DaySample _day(int month, int day, double kcal, {double goal = 2000}) => (
  day: DateTime(2026, month, day),
  kcal: kcal,
  goal: goal,
  carbs: kcal / 10,
  fat: kcal / 40,
  protein: kcal / 20,
);

void main() {
  test('weekStartOf returns the Monday of the week', () {
    // 2026-10-25 is a Sunday, so its week began on Monday the 19th.
    expect(weekStartOf(DateTime(2026, 10, 25)), DateTime(2026, 10, 19));
    expect(weekStartOf(DateTime(2026, 10, 19)), DateTime(2026, 10, 19));
  });

  test('periodStats ignores unlogged days instead of counting them as 0', () {
    final stats = periodStats(DateTime(2026, 10, 19), [
      _day(10, 19, 2000),
      _day(10, 20, 0),
      _day(10, 21, 1000),
    ]);
    expect(stats!.loggedDays, 2);
    expect(stats.avgKcal, 1500);
  });

  test('periodStats is null when nothing was logged', () {
    expect(periodStats(DateTime(2026, 10, 19), [_day(10, 19, 0)]), isNull);
  });

  test('groupedStats buckets weekly and monthly, oldest first', () {
    final samples = [
      _day(10, 26, 2200), // Monday of the next week
      _day(9, 30, 1800),
      _day(10, 1, 2000),
      _day(10, 2, 2400),
    ];
    final weeks = groupedStats(samples, weekStartOf);
    expect(weeks.map((w) => w.start), [
      DateTime(2026, 9, 28),
      DateTime(2026, 10, 26),
    ]);
    expect(weeks.first.avgKcal, 2066.6666666666665);

    final months = groupedStats(samples, monthStartOf);
    expect(months.map((m) => m.start), [
      DateTime(2026, 9),
      DateTime(2026, 10),
    ]);
    expect(months.last.loggedDays, 3);
    expect(months.last.avgKcal, closeTo(2200, 1e-9));
  });

  test('adherence counts logged days within tolerance of the goal', () {
    final samples = [
      _day(10, 1, 2000),
      _day(10, 2, 2150),
      _day(10, 3, 3000),
      _day(10, 4, 0),
    ];
    expect(adherence(samples), closeTo(2 / 3, 1e-9));
    expect(adherence([_day(10, 4, 0)]), isNull);
  });
}
