import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:voice_agent/core/theme/app_colors.dart';

/// The drift of Aurora's background (off-roadmap S2,
/// 2026-11-15-va-graphite-glass): one clock for every page, so a page pushed
/// over another shows the same sky. It ticks only while [enabled] (the
/// owner's "Tło w ruchu"), while Android's "Remove animations" is off and
/// while the app is in front; otherwise the sky stands still where it was.
///
/// The phase advances a full turn in [period]. The painters repaint at most
/// [fps] times a second: the drift is slow, and each repaint of the sky
/// re-blurs every glass surface over it.
class AuroraDrift extends StatefulWidget {
  const AuroraDrift({
    super.key,
    required this.enabled,
    required this.child,
    this.period = const Duration(seconds: 48),
    this.fps = 12,
  });

  final bool enabled;
  final Widget child;
  final Duration period;
  final int fps;

  /// Off in widget tests (test/flutter_test_config.dart): a sky that never
  /// stops scheduling frames would never let `pumpAndSettle` settle. The
  /// drift's own tests turn it back on.
  static bool debugEnabled = true;

  /// The phase in [0, 1), or a still sky when there is no [AuroraDrift].
  static ValueListenable<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DriftScope>()?.phase ??
      const _Still();

  @override
  State<AuroraDrift> createState() => _AuroraDriftState();
}

class _Still implements ValueListenable<double> {
  const _Still();
  @override
  double get value => 0;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _AuroraDriftState extends State<AuroraDrift>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  final _phase = ValueNotifier<double>(0);
  Duration _base = Duration.zero; // time already drifted before this run
  Duration _lastPaint = Duration.zero;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = WidgetsBinding.instance.lifecycleState;
    _foreground = s == null || s == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AuroraDrift old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  bool get _shouldRun =>
      AuroraDrift.debugEnabled &&
      widget.enabled &&
      _foreground &&
      !MediaQuery.disableAnimationsOf(context);

  void _sync() {
    if (_shouldRun && !_ticker.isActive) {
      _lastPaint = Duration.zero;
      _ticker.start();
    } else if (!_shouldRun && _ticker.isActive) {
      _base = _elapsed;
      _ticker.stop();
    }
  }

  Duration _elapsed = Duration.zero;

  void _tick(Duration sinceStart) {
    _elapsed = _base + sinceStart;
    final step = Duration(microseconds: 1000000 ~/ widget.fps);
    if (sinceStart - _lastPaint < step && _lastPaint != Duration.zero) return;
    _lastPaint = sinceStart == Duration.zero ? const Duration(microseconds: 1) : sinceStart;
    final p = widget.period.inMicroseconds;
    _phase.value = (_elapsed.inMicroseconds % p) / p;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DriftScope(phase: _phase, child: widget.child);
}

class _DriftScope extends InheritedWidget {
  const _DriftScope({required this.phase, required super.child});

  final ValueNotifier<double> phase;

  @override
  bool updateShouldNotify(_DriftScope old) => old.phase != phase;
}

/// Whether the drift ticks now (for tests and the device check).
@visibleForTesting
bool auroraDriftRunning(BuildContext context) {
  final state = context.findAncestorStateOfType<_AuroraDriftState>();
  return state?._ticker.isActive ?? false;
}

/// The page's sky: Graphite's background colour and four soft blobs that
/// drift on [AuroraDrift]'s clock. Painted as radial gradients, not blurred
/// circles: the look of the mockups' `filter: blur(46px)` without a blur.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return CustomPaint(
      key: const Key('aurora-background'),
      painter: _SkyPainter(colors, AuroraDrift.of(context), Theme.of(context).brightness),
      child: child,
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.colors, this.phase, this.brightness) : super(repaint: phase);

  final AppColors colors;
  final ValueListenable<double> phase;
  final Brightness brightness;

  // The mockups' blobs on a 390 × 844 screen: x, y, size, orbit, phase
  // (research drafts/assets/mockups_dynamic.py, BLOBS).
  static const _blobs = [
    (40.0, 80.0, 300.0, 40.0, 0.0),
    (260.0, 180.0, 280.0, 50.0, 0.3),
    (120.0, 520.0, 320.0, 45.0, 0.6),
    (300.0, 700.0, 260.0, 35.0, 0.85),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.background);
    final sx = size.width / 390, sy = size.height / 844;
    final t = phase.value;
    for (var i = 0; i < _blobs.length && i < colors.blobs.length; i++) {
      final (x, y, s, r, ph) = _blobs[i];
      final a = 2 * math.pi * (t + ph);
      final c = Offset((x + r * math.cos(a)) * sx, (y + r * math.sin(a)) * sy);
      final radius = (s / 2 + 46) * sx;
      final color = colors.blobs[i].withValues(alpha: 0.9);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: color.a * 0.55), color.withValues(alpha: 0)],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.colors != colors || old.phase != phase || old.brightness != brightness;
}

/// Puts [AuroraBackground] behind every page route: the page is drawn over
/// the sky and the pair moves as one in the platform's transition.
class AuroraPageTransitionsBuilder extends PageTransitionsBuilder {
  const AuroraPageTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      inner.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        AuroraBackground(child: child),
      );
}
