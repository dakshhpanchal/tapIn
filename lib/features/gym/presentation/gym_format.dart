import 'package:flutter/material.dart';
import 'package:opennutritracker/features/gym/domain/gym_calc.dart';

/// Weight is stored in kg; these convert to and from the unit on screen.
String weightUnitLabel(bool useLb) => useLb ? 'lb' : 'kg';

double toDisplayWeight(double kg, bool useLb) => useLb ? kgToLb(kg) : kg;

/// The unit label for an exercise: "plates" for machine plates, else kg/lb.
String unitFor({required bool plates, required bool useLb}) =>
    plates ? 'plates' : weightUnitLabel(useLb);

/// [stored] as shown for an exercise: plate counts as they are, weights in
/// the user's unit.
String weightShown(
  double stored, {
  required bool plates,
  required bool useLb,
}) => plates ? formatWeight(stored) : weightText(stored, useLb);

/// What the user typed back to the stored number (plates stay as typed).
double weightStored(
  double typed, {
  required bool plates,
  required bool useLb,
}) => plates ? typed : fromDisplayWeight(typed, useLb);

double fromDisplayWeight(double value, bool useLb) =>
    useLb ? lbToKg(value) : value;

String weightText(double kg, bool useLb) =>
    formatWeight(toDisplayWeight(kg, useLb));

/// "1h 05m", "42m", "0m".
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
}

/// "1:05:09" or "5:09", for running clocks.
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.padLeft(2, '0')}:$s' : '$m:$s';
}

/// Volume with a thousands separator: "12,450".
String volumeText(double kg, bool useLb) {
  final v = toDisplayWeight(kg, useLb).round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    if (i > 0 && (v.length - i) % 3 == 0) buf.write(',');
    buf.write(v[i]);
  }
  return '$buf ${weightUnitLabel(useLb)}';
}

/// "18:05".
String timeText(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String dateText(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// Text colour for secondary labels, following the theme.
Color mutedColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
