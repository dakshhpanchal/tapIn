import 'package:flutter/material.dart';

/// The palette behind the calm friendly-flat redesign.
///
/// A warm-neutral canvas with a gentle surface ladder carries the app; depth
/// comes from hairline borders and soft shadows, not colour. A single vivid
/// [accent] (a fresh leaf-green by default, nodding to the nutrition brand) is
/// the only loud colour and is user-overridable via the accent picker / Material
/// You. The macro trio (carbs amber, fat coral, protein teal) stays fixed so the
/// dashboard always reads the same, whatever accent is chosen.
class AppPalette {
  final Brightness brightness;
  final Color canvas; // scaffold background
  final Color surface; // cards / sheets
  final Color surfaceMuted; // secondary fills, track backgrounds
  final Color border; // hairline outline
  final Color shadow; // soft shadow colour
  final Color accent; // the one vivid colour (overridable)
  final Color onAccent;
  final Color carbsColor;
  final Color fatColor;
  final Color proteinColor;
  final Color textStrong;
  final Color textMuted;

  const AppPalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.shadow,
    required this.accent,
    required this.onAccent,
    required this.carbsColor,
    required this.fatColor,
    required this.proteinColor,
    required this.textStrong,
    required this.textMuted,
  });

  Color get carbs => carbsColor;
  Color get fat => fatColor;
  Color get protein => proteinColor;

  /// The tapIn palettes as designed. [light] and [dark] start out as these and
  /// are replaced by the app when Material You or an accent changes them, so
  /// every widget that reads them sees the colours actually in use.
  static const baseLight = AppPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFF6F5FC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFECEBF8),
    border: Color(0xFFE1E0F2),
    shadow: Color(0x142E2B4A),
    // The coral ring of the launcher icon, with dark text on top for contrast.
    accent: Color(0xFFFC9375),
    onAccent: Color(0xFF20201C),
    // Lavender, coral and indigo, the icon's other colours.
    carbsColor: Color(0xFF7E80DC),
    fatColor: Color(0xFFE0653F),
    proteinColor: Color(0xFF3B3D8F),
    textStrong: Color(0xFF2B2A33),
    textMuted: Color(0xFF6B6880),
  );

  static const baseDark = AppPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF0E0E14),
    surface: Color(0xFF181822),
    surfaceMuted: Color(0xFF232332),
    border: Color(0xFF2E2E42),
    shadow: Color(0x33000000),
    accent: Color(0xFFFC9375),
    onAccent: Color(0xFF2A0F06),
    carbsColor: Color(0xFFA5A6EB),
    fatColor: Color(0xFFFF9A78),
    proteinColor: Color(0xFF6C70E0),
    textStrong: Color(0xFFEDEBFA),
    textMuted: Color(0xFFA3A1B8),
  );

  static AppPalette light = baseLight;
  static AppPalette dark = baseDark;

  /// Returns a copy with the accent swapped for [newAccent] (accent picker or a
  /// harmonized Material You primary). The neutral canvas, surfaces and macro
  /// colours are untouched, so only the one vivid role follows the user.
  AppPalette withAccent(Color newAccent) {
    final onNew = ThemeData.estimateBrightnessForColor(newAccent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF20201C);
    return AppPalette(
      brightness: brightness,
      canvas: canvas,
      surface: surface,
      surfaceMuted: surfaceMuted,
      border: border,
      shadow: shadow,
      accent: newAccent,
      onAccent: onNew,
      carbsColor: carbsColor,
      fatColor: fatColor,
      proteinColor: proteinColor,
      textStrong: textStrong,
      textMuted: textMuted,
    );
  }

  /// The canvas, surfaces, borders and text taken from a Material You scheme,
  /// so the whole background follows the wallpaper, not only the accent.
  AppPalette withSurfaces({
    required Color canvas,
    required Color surface,
    required Color surfaceMuted,
    required Color border,
    required Color textStrong,
    required Color textMuted,
  }) => AppPalette(
    brightness: brightness,
    canvas: canvas,
    surface: surface,
    surfaceMuted: surfaceMuted,
    border: border,
    shadow: shadow,
    accent: accent,
    onAccent: onAccent,
    carbsColor: carbsColor,
    fatColor: fatColor,
    proteinColor: proteinColor,
    textStrong: textStrong,
    textMuted: textMuted,
  );

  ColorScheme get colorScheme => ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: onAccent,
        primaryContainer: accent,
        onPrimaryContainer: onAccent,
        secondary: proteinColor,
        onSecondary: onAccent,
        secondaryContainer: surfaceMuted,
        onSecondaryContainer: textStrong,
        tertiary: carbsColor,
        onTertiary: onAccent,
        tertiaryContainer: surfaceMuted,
        onTertiaryContainer: textStrong,
        error: brightness == Brightness.light ? const Color(0xFFC4453A) : const Color(0xFFFFB4AB),
        onError: brightness == Brightness.light ? Colors.white : const Color(0xFF690005),
        surface: surface,
        onSurface: textStrong,
        surfaceContainerLowest: canvas,
        surfaceContainerLow: canvas,
        surfaceContainer: surfaceMuted,
        surfaceContainerHigh: surfaceMuted,
        surfaceContainerHighest: surfaceMuted,
        onSurfaceVariant: textMuted,
        outline: border,
        outlineVariant: border,
        surfaceTint: Colors.transparent,
        shadow: shadow,
      );
}
