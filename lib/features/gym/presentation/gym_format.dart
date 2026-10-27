import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
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
  final v = NumberFormat.decimalPattern().format(
    toDisplayWeight(kg, useLb).round(),
  );
  return '$v ${weightUnitLabel(useLb)}';
}

/// The time of day in the user's own clock style (24 or 12 hour).
String timeText(DateTime d) => DateFormat.jm().format(d);

/// "Mon, 5 Oct", with the year added for dates outside the current year.
String dateText(DateTime d) {
  final sameYear = d.year == DateTime.now().year;
  return (sameYear ? DateFormat.MMMEd() : DateFormat.yMMMEd()).format(d);
}

/// Text colour for secondary labels, following the theme.
Color mutedColor(BuildContext context) =>
    (Theme.of(context).brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light)
        .textMuted;
