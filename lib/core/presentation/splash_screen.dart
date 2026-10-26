import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';

/// First screen shown on launch: the tapIn icon pops in on the icon's own navy,
/// a tap ripple spreads out from the ring twice, and the name fades in. After
/// that it routes on to the main screen (returning user) or onboarding (first
/// run).
///
/// The native launch screen (Android `launch_background` and the Android 12
/// splash) is the same navy and shows the same icon, so the hand-off into this
/// animated splash is seamless.
class SplashScreen extends StatefulWidget {
  /// Whether the user has already completed onboarding. Decides where the
  /// splash routes once the animation finishes.
  final bool userInitialized;

  const SplashScreen({super.key, required this.userInitialized});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _navy = Color(0xFF0D1946);
  static const _coral = Color(0xFFFF9A7C);
  static const _iconSize = 280.0;
  // Where the coral ring's centre sits in the icon image, as a fraction of it.
  static const _ringCentre = Offset(0.493, 0.392);

  static const _startDelay = Duration(milliseconds: 250);
  static const _duration = Duration(milliseconds: 1700);
  static const _hold = Duration(milliseconds: 250);

  late final AnimationController _controller;
  late final Animation<double> _icon;
  late final Animation<double> _name;
  Timer? _startTimer;
  bool _navigated = false;

  /// A step of the timeline, [begin]..[end] as fractions of the animation.
  Animation<double> _step(double begin, double end, Curve curve) =>
      CurvedAnimation(
        parent: _controller,
        curve: Interval(begin, end, curve: curve),
      );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _icon = _step(0.0, 0.4, Curves.easeOutBack);
    _name = _step(0.55, 0.85, Curves.easeOut);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // A short beat on the finished logo before moving on.
        _startTimer = Timer(_hold, _goNext);
      }
    });

    // Honour the OS "reduce motion" setting: skip the animation and move on.
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduceMotion) {
      _controller.value = 1;
      _startTimer = Timer(const Duration(milliseconds: 600), _goNext);
    } else {
      _startTimer = Timer(_startDelay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(
      widget.userInitialized
          ? NavigationOptions.mainRoute
          : NavigationOptions.onboardingRoute,
    );
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _navy,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pop = _icon.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _iconSize,
                  height: _iconSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _RipplePainter(
                            progress: _controller.value,
                            centre: _ringCentre,
                            color: _coral,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Opacity(
                          opacity: pop.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.8 + 0.2 * pop,
                            child: Image.asset(
                              'assets/icon/tapin_launcher_1024.png',
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -48 + 8 * (1 - _name.value)),
                  child: Opacity(
                    opacity: _name.value,
                    child: Text(
                      'tapIn',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Two coral rings spreading out from the ring in the icon, as if tapped: the
/// first as the icon lands, the second a beat later.
class _RipplePainter extends CustomPainter {
  final double progress;
  final Offset centre;
  final Color color;

  const _RipplePainter({
    required this.progress,
    required this.centre,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * centre.dx, size.height * centre.dy);
    for (final (start, end) in const [(0.3, 0.75), (0.45, 0.9)]) {
      final t = ((progress - start) / (end - start)).clamp(0.0, 1.0);
      if (t <= 0 || t >= 1) continue;
      final eased = Curves.easeOutCubic.transform(t);
      final radius = size.width * (0.12 + 0.36 * eased);
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: 0.55 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.progress != progress;
}
