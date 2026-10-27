import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';

/// First screen shown on launch, on black: the tapIn icon pops in, a burst of
/// coral rays comes out of the top of the ring as if it were tapped, and a
/// soft ripple spreads. After that it routes on to the main
/// screen (returning user) or onboarding (first run).
///
/// The native launch screen (Android `launch_background` and the Android 12
/// splash) is black too and shows the same icon, so the hand-off into this
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
  static const _coral = Color(0xFFFF9A7C);
  static const _iconSize = 300.0;
  // Where the coral ring's centre sits in the icon image, as a fraction of it.
  static const _ringCentre = Offset(0.493, 0.392);

  static const _startDelay = Duration(milliseconds: 250);
  static const _duration = Duration(milliseconds: 1600);
  static const _hold = Duration(milliseconds: 250);

  late final AnimationController _controller;
  late final Animation<double> _icon;
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
    _icon = _step(0.0, 0.35, Curves.easeOutBack);

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
    // Black screen: light status bar icons so they stay visible.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pop = _icon.value;
            return SizedBox(
              width: _iconSize,
              height: _iconSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: pop.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.8 + 0.2 * pop,
                        child: Image.asset(
                          'assets/icon/tapin_splash.png',
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TapPainter(
                        progress: _controller.value,
                        centre: _ringCentre,
                        color: _coral,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ));
  }
}

/// The "tap": a fan of coral rays bursting out of the top of the ring, then a
/// thin ripple spreading from it.
///
/// Every ray starts on the same circle around the ring, so their bases form an
/// arc, and each points straight out from the centre. The rays in the middle
/// of the fan go first.
class _TapPainter extends CustomPainter {
  final double progress;
  final Offset centre;
  final Color color;

  const _TapPainter({
    required this.progress,
    required this.centre,
    required this.color,
  });

  static const _rayCount = 7;
  static const _fanStartDeg = -155.0; // screen angles: -90 is straight up
  static const _fanEndDeg = -25.0;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * centre.dx, size.height * centre.dy);
    _paintRays(canvas, size, origin);
    _paintRipple(canvas, size, origin);
  }

  void _paintRays(Canvas canvas, Size size, Offset origin) {
    final baseRadius = size.width * 0.135;
    final maxLength = size.width * 0.1;
    // Fully out by the middle of the animation, gone by its end.
    final fade = 1 - ((progress - 0.78) / 0.2).clamp(0.0, 1.0);
    for (var i = 0; i < _rayCount; i++) {
      final fromMiddle = (i - (_rayCount - 1) / 2).abs();
      final t = ((progress - 0.3 - fromMiddle * 0.025) / 0.28).clamp(0.0, 1.0);
      if (t <= 0 || fade <= 0) continue;
      final grow = Curves.easeOutCubic.transform(t);
      final angle =
          (_fanStartDeg + (_fanEndDeg - _fanStartDeg) * i / (_rayCount - 1)) *
          math.pi /
          180;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        origin + direction * baseRadius,
        origin + direction * (baseRadius + maxLength * grow),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = size.width * 0.03
          ..color = color.withValues(alpha: fade),
      );
    }
  }

  void _paintRipple(Canvas canvas, Size size, Offset origin) {
    final t = ((progress - 0.42) / 0.5).clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) return;
    canvas.drawCircle(
      origin,
      size.width * (0.12 + 0.34 * Curves.easeOutCubic.transform(t)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color.withValues(alpha: 0.4 * (1 - t)),
    );
  }

  @override
  bool shouldRepaint(_TapPainter old) => old.progress != progress;
}
