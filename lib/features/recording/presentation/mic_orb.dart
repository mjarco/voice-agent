import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:voice_agent/features/recording/presentation/mic_activity.dart';

/// The living mic (off-roadmap S5, research drafts/13 §4): around the mic's
/// orb ([child]) the state shows by how it moves, in S1's mic colours.
///
/// - idle breathes slowly;
/// - listening sends rings outward;
/// - hearing and recording: the outline trembles, as a voice would move it;
/// - processing: a ring turns around the orb;
/// - standby stands still.
///
/// With Android's "Remove animations" the orb stands still and says its
/// state by colour and icon only. Widget tests freeze it
/// ([debugAnimate], test/flutter_test_config.dart): a loop never lets
/// `pumpAndSettle` settle.
class MicOrb extends StatefulWidget {
  const MicOrb({
    super.key,
    required this.activity,
    required this.color,
    required this.child,
  });

  final MicActivity activity;
  final Color color;
  final Widget child;

  /// False in widget tests, where an endless animation never settles.
  static bool debugAnimate = true;

  /// How long one loop of each state takes.
  static Duration periodOf(MicActivity a) => switch (a) {
        MicActivity.idle => const Duration(milliseconds: 3600),
        MicActivity.listening => const Duration(milliseconds: 1800),
        MicActivity.hearing || MicActivity.recording => const Duration(milliseconds: 1400),
        MicActivity.processing => const Duration(milliseconds: 1100),
        MicActivity.standby => Duration.zero,
      };

  /// True when the state moves at all (and motion is allowed).
  static bool moves(MicActivity a, {required bool reduceMotion}) =>
      debugAnimate && !reduceMotion && a != MicActivity.standby;

  @override
  State<MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this);

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MicOrb old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) _sync();
  }

  void _sync() {
    if (MicOrb.moves(widget.activity, reduceMotion: _reduceMotion)) {
      final period = MicOrb.periodOf(widget.activity);
      if (_clock.duration != period || !_clock.isAnimating) {
        _clock
          ..duration = period
          ..repeat();
      }
    } else {
      _clock
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moving = MicOrb.moves(widget.activity, reduceMotion: _reduceMotion);
    return AnimatedBuilder(
      key: Key('mic-orb-${widget.activity.name}'),
      animation: _clock,
      builder: (context, child) {
        final t = moving ? _clock.value : 0.0;
        // Idle breathes: the orb itself swells by 4% and back.
        final scale = widget.activity == MicActivity.idle && moving
            ? 0.98 + 0.04 * (0.5 + 0.5 * math.sin(t * 2 * math.pi))
            : 1.0;
        return CustomPaint(
          painter: _OrbPainter(
            activity: widget.activity,
            color: widget.color,
            t: t,
            moving: moving,
          ),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: widget.child,
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.activity,
    required this.color,
    required this.t,
    required this.moving,
  });

  final MicActivity activity;
  final Color color;

  /// The loop's phase, 0 to 1.
  final double t;
  final bool moving;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    if (!moving) return;
    switch (activity) {
      case MicActivity.listening:
        // Two rings leave the orb and fade.
        for (final shift in const [0.0, 0.5]) {
          final p = (t + shift) % 1;
          canvas.drawCircle(
            c,
            r * (1.0 + 0.5 * p),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = color.withValues(alpha: (1 - p) * 0.55),
          );
        }
      case MicActivity.hearing || MicActivity.recording:
        // The outline trembles outward, as a voice would move it: the
        // radius moved by three sines around the orb.
        final path = Path();
        const steps = 60;
        final ph = t * 2 * math.pi;
        for (var i = 0; i <= steps; i++) {
          final a = i / steps * 2 * math.pi;
          final d = 0.07 +
              0.05 * math.sin(3 * a + ph) +
              0.035 * math.sin(5 * a - 2 * ph) +
              0.025 * math.sin(7 * a + 3 * ph);
          final p = c + Offset(math.cos(a), math.sin(a)) * (r * (1 + d));
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.5));
      case MicActivity.processing:
        // A quarter ring turning around the orb.
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.2),
          t * 2 * math.pi - math.pi / 2,
          math.pi / 2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = color,
        );
      case MicActivity.idle || MicActivity.standby:
        break;
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t || old.activity != activity || old.color != color || old.moving != moving;
}
