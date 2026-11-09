import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/gym/presentation/exercise_progress_chart.dart';

List<ProgressPoint> _points(int n) => [
  for (var i = 0; i < n; i++)
    ProgressPoint(
      date: DateTime(2026, 8, 1).add(Duration(days: 7 * i)),
      // Steps up every 4th workout, reps climb in between, one repeat and one dip.
      weight: 20 + 2.5 * (i ~/ 4),
      reps: i == 5 ? 7 : 8 + (i % 4),
    ),
];

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Opens the small bar-chart menu and chooses [style].
Future<void> _pick(WidgetTester tester, ProgressStyle style) async {
  await tester.tap(find.byTooltip('Chart style'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(style.label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every look draws for a normal history', (tester) async {
    await tester.pumpWidget(
      _wrap(ExerciseProgressChart(points: _points(10), unit: 'kg')),
    );
    for (final s in ProgressStyle.values) {
      await _pick(tester, s);
      expect(tester.takeException(), isNull, reason: s.label);
    }
  });

  testWidgets('one workout, and a long history, still draw in every look', (
    tester,
  ) async {
    for (final n in [1, 2, 60]) {
      await tester.pumpWidget(
        _wrap(ExerciseProgressChart(points: _points(n), unit: 'kg')),
      );
      for (final s in ProgressStyle.values) {
        await _pick(tester, s);
        expect(tester.takeException(), isNull, reason: '${s.label} with $n');
      }
    }
  });

  testWidgets('shows the latest workout first and what changed', (
    tester,
  ) async {
    final pts = [
      ProgressPoint(date: DateTime(2026, 10, 1), weight: 25, reps: 10),
      ProgressPoint(date: DateTime(2026, 10, 8), weight: 25, reps: 12),
    ];
    await tester.pumpWidget(
      _wrap(ExerciseProgressChart(points: pts, unit: 'kg')),
    );
    expect(find.textContaining('25 kg × 12 reps'), findsOneWidget);
    expect(find.text('+2 reps'), findsOneWidget);
    expect(find.textContaining('latest'), findsOneWidget);
  });

  testWidgets('tapping the chart picks an earlier workout', (tester) async {
    final pts = [
      ProgressPoint(date: DateTime(2026, 10, 1), weight: 20, reps: 10),
      ProgressPoint(date: DateTime(2026, 10, 8), weight: 22.5, reps: 8),
      ProgressPoint(date: DateTime(2026, 10, 15), weight: 22.5, reps: 8),
    ];
    await tester.pumpWidget(
      _wrap(ExerciseProgressChart(points: pts, unit: 'kg')),
    );
    expect(find.text('Same'), findsOneWidget);
    final box = tester.getRect(find.byKey(const ValueKey('progress-chart')));
    // The first column sits just right of the left axis.
    await tester.tapAt(Offset(box.left + 36 + 5, box.center.dy));
    await tester.pump();
    expect(find.textContaining('20 kg × 10 reps'), findsOneWidget);
    expect(find.text('First workout'), findsOneWidget);
    expect(find.textContaining('latest'), findsNothing);
  });

  testWidgets('weight up and a dip are named in the unit shown', (
    tester,
  ) async {
    final pts = [
      ProgressPoint(date: DateTime(2026, 10, 1), weight: 5, reps: 10),
      ProgressPoint(date: DateTime(2026, 10, 8), weight: 6, reps: 8),
      ProgressPoint(date: DateTime(2026, 10, 15), weight: 6, reps: 6),
    ];
    await tester.pumpWidget(
      _wrap(ExerciseProgressChart(points: pts, unit: 'plates')),
    );
    expect(find.text('−2 reps'), findsOneWidget);
    final box = tester.getRect(find.byKey(const ValueKey('progress-chart')));
    await tester.tapAt(Offset(box.center.dx, box.center.dy));
    await tester.pump();
    expect(find.text('+1 plates'), findsOneWidget);
  });
}
