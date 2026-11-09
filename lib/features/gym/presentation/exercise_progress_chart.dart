import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';
import 'package:opennutritracker/features/gym/presentation/gym_format.dart';
import 'package:opennutritracker/features/gym/presentation/list_tools.dart';
import 'package:opennutritracker/features/gym/presentation/progress_style_prefs.dart';

/// One workout of an exercise: the weight (already in the unit on screen) and
/// the reps done at it.
class ProgressPoint {
  final DateTime date;
  final double weight;
  final int reps;

  /// The workout this point comes from, so it can be opened.
  final String? sessionId;
  const ProgressPoint({
    required this.date,
    required this.weight,
    required this.reps,
    this.sessionId,
  });
}

/// The ways the chart can be drawn. All show weight and reps together.
enum ProgressStyle {
  barsLine(
    'Bars + line',
    'Reps are bars, weight is the line.',
    'Weight, right axis',
    'Reps, left axis',
  ),
  weightBars(
    'Weight bars',
    'Weight is bars, reps are the line.',
    'Weight, left axis',
    'Reps, right axis',
  ),
  butterfly(
    'Butterfly',
    'Weight grows up from the middle line, reps grow down.',
    'Weight up',
    'Reps down',
  ),
  plateaus(
    'Plateaus',
    'A flat coral bar spans every workout you stayed on a weight.',
    'Weight, right axis',
    'Reps, left axis',
  ),
  smoothReps(
    'Smooth reps',
    'Weight is bars, reps are a smooth wave over them.',
    'Weight, left axis',
    'Reps, right axis',
  ),
  butterflyColours(
    'Butterfly colours',
    'Solid means that one improved. Red outline means you did less.',
    'Solid: weight went up',
    'Solid: reps went up',
  );

  final String label;
  final String description;
  final String weightLegend;
  final String repsLegend;
  const ProgressStyle(
    this.label,
    this.description,
    this.weightLegend,
    this.repsLegend,
  );

  static ProgressStyle fromName(String? name) => ProgressStyle.values
      .firstWhere((s) => s.name == name, orElse: () => ProgressStyle.barsLine);
}

enum _Change { first, weight, reps, same, less }

/// What changed from the workout before [i]: more weight, more reps at the
/// same weight, nothing, or less.
_Change _changeAt(List<ProgressPoint> p, int i) {
  if (i == 0) return _Change.first;
  final a = p[i - 1], b = p[i];
  const e = 1e-6;
  if (b.weight > a.weight + e) return _Change.weight;
  if (b.weight < a.weight - e) return _Change.less;
  if (b.reps > a.reps) return _Change.reps;
  if (b.reps < a.reps) return _Change.less;
  return _Change.same;
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Weight and reps for one exercise over time: a readout of the chosen
/// workout, a chart in one of several looks, and a way to switch the look.
/// Tap or drag on the chart to pick a workout.
class ExerciseProgressChart extends StatefulWidget {
  final List<ProgressPoint> points; // oldest first
  final String unit;

  /// The look to open with; by default the one used last time.
  final ProgressStyle? initialStyle;

  /// Opens the workout behind the chosen point; no button without it.
  final void Function(String sessionId)? onView;
  const ExerciseProgressChart({
    super.key,
    required this.points,
    required this.unit,
    this.initialStyle,
    this.onView,
  });

  @override
  State<ExerciseProgressChart> createState() => _ExerciseProgressChartState();
}

class _ExerciseProgressChartState extends State<ExerciseProgressChart> {
  late ProgressStyle _style =
      widget.initialStyle ?? ProgressStyle.fromName(ProgressStylePrefs.read());
  int _window = 12; // 12, 30, or 0 for all
  int? _picked; // index in the visible points; null = the latest

  List<ProgressPoint> get _visible {
    final all = widget.points;
    if (_window == 0 || all.length <= _window) return all;
    return all.sublist(all.length - _window);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _visible;
    final sel = math.min(_picked ?? pts.length - 1, pts.length - 1);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final weightColor = theme.colorScheme.primary;
    final repsColor = palette.proteinColor;
    final text = theme.textTheme;
    final p = pts[sel];
    final change = _changeAt(pts, sel);
    final (tagText, tagColor) = switch (change) {
      _Change.first => ('First workout', palette.textMuted),
      _Change.weight => (
        '+${_num(p.weight - pts[sel - 1].weight)} ${widget.unit}',
        weightColor,
      ),
      _Change.reps => ('+${p.reps - pts[sel - 1].reps} reps', repsColor),
      _Change.same => ('Same', palette.textMuted),
      _Change.less => (
        p.weight < pts[sel - 1].weight
            ? '−${_num(pts[sel - 1].weight - p.weight)} ${widget.unit}'
            : '−${pts[sel - 1].reps - p.reps} reps',
        theme.colorScheme.error,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateText(p.date) +
                        (sel == pts.length - 1 ? ' · latest' : ''),
                    style: text.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _num(p.weight),
                          style: text.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: palette.textStrong,
                          ),
                        ),
                        TextSpan(
                          text: ' ${widget.unit} × ${p.reps} reps',
                          style: text.bodyMedium?.copyWith(
                            color: palette.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing12,
                vertical: Dimens.spacing4,
              ),
              decoration: BoxDecoration(
                color: tagColor,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                tagText,
                style: text.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: Dimens.spacing4),
            OptionMenu<ProgressStyle>(
              icon: Icons.bar_chart_rounded,
              tooltip: 'Chart style',
              identifier: 'gym-progress-chart-style',
              values: ProgressStyle.values,
              labelOf: (v) => v.label,
              descriptionOf: (v) => v.description,
              selected: _style,
              onSelected: (s) {
                setState(() => _style = s);
                ProgressStylePrefs.save(s.name);
              },
            ),
            if (widget.points.length > 12)
              OptionMenu<int>(
                icon: Icons.date_range_rounded,
                tooltip: 'Time range',
                values: const [12, 30, 0],
                labelOf: (v) => switch (v) {
                  12 => 'Last 12 workouts',
                  30 => 'Last 30 workouts',
                  _ => 'All workouts',
                },
                selected: _window,
                onSelected: (v) => setState(() {
                  _window = v;
                  _picked = null;
                }),
              ),
          ],
        ),
        if (widget.onView != null && p.sessionId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => widget.onView!(p.sessionId!),
              child: const Text('View workout'),
            ),
          ),
        const SizedBox(height: Dimens.spacing12),
        Semantics(
          label:
              'Weight and reps for each workout. Selected: ${dateText(p.date)}, '
              '${_num(p.weight)} ${widget.unit} for ${p.reps} reps.',
          child: LayoutBuilder(
            builder: (context, box) {
              void pick(double dx) {
                final cw =
                    (box.maxWidth - _ChartPainter.left - _ChartPainter.right) /
                    pts.length;
                final i = ((dx - _ChartPainter.left) / cw).floor().clamp(
                  0,
                  pts.length - 1,
                );
                if (i != _picked) setState(() => _picked = i);
              }

              return GestureDetector(
                key: const ValueKey('progress-chart'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => pick(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
                child: CustomPaint(
                  size: Size(box.maxWidth, 200),
                  painter: _ChartPainter(
                    style: _style,
                    points: pts,
                    selected: sel,
                    weightColor: weightColor,
                    repsColor: repsColor,
                    muted: palette.textMuted,
                    ink: palette.textStrong,
                    grid: palette.border,
                    error: theme.colorScheme.error,
                    surface: palette.surface,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        Wrap(
          spacing: Dimens.spacing16,
          runSpacing: Dimens.spacing4,
          children: [
            _legend(context, weightColor, _style.weightLegend),
            _legend(context, repsColor, _style.repsLegend),
          ],
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: mutedColor(context),
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ChartPainter extends CustomPainter {
  static const left = 36.0, right = 36.0, top = 16.0, bottom = 26.0;

  final ProgressStyle style;
  final List<ProgressPoint> points;
  final int selected;
  final Color weightColor, repsColor, muted, ink, grid, error, surface;

  _ChartPainter({
    required this.style,
    required this.points,
    required this.selected,
    required this.weightColor,
    required this.repsColor,
    required this.muted,
    required this.ink,
    required this.grid,
    required this.error,
    required this.surface,
  });

  Color get _wSoft => weightColor.withValues(alpha: 0.2);
  Color get _rSoft => repsColor.withValues(alpha: 0.2);

  late Canvas _c;
  late double _w, _h, _ph, _base, _cw, _wlo, _whi, _rMax;
  late double _wMin, _wMax;
  late bool _showValues;

  double _x(int i) => left + (i + .5) * _cw;
  double _wy(double v) => top + (_whi - v) / (_whi - _wlo) * _ph;
  double _ry(double r) => top + (1 - r / _rMax) * _ph;

  void _text(
    String s,
    double x,
    double cy,
    Color color, {
    double size = 10,
    TextAlign align = TextAlign.center,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right || TextAlign.end => x - tp.width,
      TextAlign.left || TextAlign.start => x,
      _ => x - tp.width / 2,
    };
    tp.paint(_c, Offset(dx, cy - tp.height / 2));
  }

  Paint _fill(Color c) => Paint()..color = c;
  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;
    _c = canvas;
    _w = size.width;
    _h = size.height;
    _ph = _h - top - bottom;
    _base = top + _ph;
    _cw = (_w - left - right) / n;
    _showValues = _cw >= 24;

    _wMin = points.map((p) => p.weight).reduce(math.min);
    _wMax = points.map((p) => p.weight).reduce(math.max);
    final span = _wMax - _wMin;
    final pad = span == 0 ? math.max(1.0, _wMax * .1) : span * .3;
    _wlo = math.max(0, _wMin - pad);
    _whi = _wMax + pad;
    final repsMax = points.map((p) => p.reps).reduce(math.max);
    _rMax = math.max(6, ((repsMax * 1.15) / 2).ceil() * 2).toDouble();

    // The chosen workout, shaded behind everything.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_x(selected) - _cw / 2, 0, _cw, _h - bottom + 6),
        const Radius.circular(6),
      ),
      _fill(grid.withValues(alpha: .5)),
    );

    switch (style) {
      case ProgressStyle.barsLine:
        _repsGridLeft();
        _weightAxisRight();
        _repsBars();
        _weightLine();
      case ProgressStyle.weightBars:
        _weightGridLeft();
        _repsAxisRight();
        _weightBars(.76);
        _repsLine();
      case ProgressStyle.butterfly:
        _butterfly(colourful: false);
      case ProgressStyle.plateaus:
        _repsGridLeft();
        _weightAxisRight();
        _repsBars();
        _plateaus();
      case ProgressStyle.smoothReps:
        _weightGridLeft();
        _repsAxisRight();
        _weightBars(.8);
        _repsWave();
      case ProgressStyle.butterflyColours:
        _butterfly(colourful: true);
    }
    _dates();
  }

  // Axes -----------------------------------------------------------------

  List<double> get _repsTicks => [0, (_rMax / 2).roundToDouble(), _rMax];
  List<double> get _weightTicks =>
      _wMax == _wMin ? [_wMin] : [_wMin, (_wMin + _wMax) / 2, _wMax];

  void _gridLine(double y) {
    final paint = _stroke(grid, 1);
    for (var x = left; x < _w - right; x += 7) {
      _c.drawLine(Offset(x, y), Offset(math.min(x + 3, _w - right), y), paint);
    }
  }

  void _repsGridLeft() {
    for (final v in _repsTicks) {
      _gridLine(_ry(v));
      _text(_num(v), left - 6, _ry(v), repsColor, align: TextAlign.right);
    }
  }

  void _weightGridLeft() {
    for (final v in _weightTicks) {
      _gridLine(_wy(v));
      _text(_num(v), left - 6, _wy(v), weightColor, align: TextAlign.right);
    }
  }

  void _weightAxisRight() {
    for (final v in _weightTicks) {
      _text(
        _num(v),
        _w - right + 6,
        _wy(v),
        weightColor,
        align: TextAlign.left,
      );
    }
  }

  void _repsAxisRight() {
    for (final v in _repsTicks) {
      _text(_num(v), _w - right + 6, _ry(v), repsColor, align: TextAlign.left);
    }
  }

  void _dates() {
    final every = math.max(1, (46 / _cw).ceil());
    for (var i = 0; i < points.length; i++) {
      if ((points.length - 1 - i) % every != 0) continue;
      final d = points[i].date;
      _text(
        '${d.day}/${d.month}',
        _x(i),
        _h - 8,
        i == selected ? ink : muted,
        size: 9,
      );
    }
  }

  // Marks ----------------------------------------------------------------

  RRect _bar(double cx, double w, double y1, double y2, [double r = 3]) =>
      RRect.fromLTRBR(cx - w / 2, y1, cx + w / 2, y2, Radius.circular(r));

  void _repsBars() {
    for (var i = 0; i < points.length; i++) {
      final r = _bar(_x(i), _cw * .6, _ry(points[i].reps.toDouble()), _base);
      _c.drawRRect(r, _fill(_rSoft));
      _c.drawRRect(r, _stroke(repsColor, i == selected ? 2 : 1));
      if (_showValues) {
        _text('${points[i].reps}', _x(i), _base - 8, repsColor);
      }
    }
  }

  void _weightBars(double widthFactor) {
    for (var i = 0; i < points.length; i++) {
      final r = _bar(_x(i), _cw * widthFactor, _wy(points[i].weight), _base, 4);
      _c.drawRRect(r, _fill(_wSoft));
      _c.drawRRect(r, _stroke(weightColor, i == selected ? 2 : 1));
    }
  }

  void _lineWith(double Function(ProgressPoint) y, Color color) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(_x(i), y(points[i]));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    _c.drawPath(path, _stroke(color, 3));
    for (var i = 0; i < points.length; i++) {
      final o = Offset(_x(i), y(points[i]));
      _c.drawCircle(o, i == selected ? 6 : 4, _fill(color));
      _c.drawCircle(o, i == selected ? 6 : 4, _stroke(surface, 2));
    }
  }

  void _weightLine() => _lineWith((p) => _wy(p.weight), weightColor);
  void _repsLine() => _lineWith((p) => _ry(p.reps.toDouble()), repsColor);

  void _plateaus() {
    // Runs of workouts at the same weight.
    final runs = <(double, int, int)>[];
    for (var i = 0; i < points.length; i++) {
      if (runs.isNotEmpty && (runs.last.$1 - points[i].weight).abs() < 1e-6) {
        runs[runs.length - 1] = (runs.last.$1, runs.last.$2, i);
      } else {
        runs.add((points[i].weight, i, i));
      }
    }
    for (var k = 0; k < runs.length; k++) {
      final (w, s, e) = runs[k];
      final x1 = _x(s) - _cw * .45, x2 = _x(e) + _cw * .45, y = _wy(w);
      _c.drawLine(Offset(x1, y), Offset(x2, y), _stroke(weightColor, 5));
      if (x2 - x1 > 40) {
        _text(_num(w), (x1 + x2) / 2, y - 10, weightColor);
      }
      if (k + 1 < runs.length) {
        final ny = _wy(runs[k + 1].$1);
        final nx = _x(runs[k + 1].$2) - _cw * .45;
        final dash = _stroke(weightColor, 2);
        const steps = 6;
        for (var d = 0; d < steps; d += 2) {
          _c.drawLine(
            Offset(x2 + (nx - x2) * d / steps, y + (ny - y) * d / steps),
            Offset(
              x2 + (nx - x2) * (d + 1) / steps,
              y + (ny - y) * (d + 1) / steps,
            ),
            dash,
          );
        }
      }
    }
  }

  void _repsWave() {
    final pts = [
      for (var i = 0; i < points.length; i++)
        Offset(_x(i), _ry(points[i].reps.toDouble())),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i], p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      line.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    final area = Path.from(line)
      ..lineTo(pts.last.dx, _base)
      ..lineTo(pts.first.dx, _base)
      ..close();
    _c.drawPath(area, _fill(repsColor.withValues(alpha: .16)));
    _c.drawPath(line, _stroke(repsColor, 3));
    for (var i = 0; i < pts.length; i++) {
      final r = i == selected ? 6.0 : 3.5;
      _c.drawCircle(pts[i], r, _fill(repsColor));
      _c.drawCircle(pts[i], r, _stroke(surface, 2));
    }
  }

  void _butterfly({required bool colourful}) {
    final mid = top + _ph / 2;
    final half = _ph / 2 - 14;
    double up(double v) => (v - _wlo) / (_whi - _wlo) * half;
    double down(int r) => r / _rMax * half;
    _c.drawLine(
      Offset(left, mid),
      Offset(_w - right, mid),
      _stroke(muted.withValues(alpha: .5), 1),
    );
    _text('kg', left - 6, top + 4, weightColor, align: TextAlign.right);
    _text('reps', left - 6, _base - 2, repsColor, align: TextAlign.right);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final change = _changeAt(points, i);
      final wSolid =
          !colourful || change == _Change.weight || change == _Change.first;
      final rSolid =
          !colourful || change == _Change.reps || change == _Change.first;
      final bad = colourful && change == _Change.less;
      final wr = _bar(_x(i), _cw * .6, mid - up(p.weight), mid);
      _c.drawRRect(wr, _fill(wSolid ? weightColor : _wSoft));
      _c.drawRRect(wr, _stroke(bad ? error : weightColor, bad ? 2 : 1));
      final rr = _bar(_x(i), _cw * .6, mid, mid + down(p.reps));
      _c.drawRRect(rr, _fill(rSolid ? repsColor : _rSoft));
      _c.drawRRect(rr, _stroke(bad ? error : repsColor, bad ? 2 : 1));
      if (_showValues) {
        _text(_num(p.weight), _x(i), mid - up(p.weight) - 8, ink, size: 9);
        _text('${p.reps}', _x(i), mid + down(p.reps) + 9, ink, size: 9);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}

/// Builds chart points for [history]: weights in the unit shown (plates stay
/// as plate counts).
List<ProgressPoint> progressPoints(
  List<ExercisePoint> history, {
  required bool plates,
  required bool useLb,
}) => [
  for (final p in history)
    ProgressPoint(
      date: p.date,
      weight: plates ? p.bestWeightKg : toDisplayWeight(p.bestWeightKg, useLb),
      reps: p.topReps,
      sessionId: p.sessionId,
    ),
];
