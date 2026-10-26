import 'package:flutter/material.dart';

/// The tapIn hand-and-ring mark as a flat shape in the theme's primary colour,
/// so it follows light/dark mode and Material You colours instead of sitting
/// in the app as a picture. Used in the Home bar and the version banner.
class DynamicTapInLogo extends StatelessWidget {
  const DynamicTapInLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/tapin_glyph.png',
      color: Theme.of(context).colorScheme.primary,
      colorBlendMode: BlendMode.srcIn,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
