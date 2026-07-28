import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Dotted working orb — particles on tilted orbits (thinking-orbs MIT port).

/// Tuned size presets (separate designs, not a scale factor).
enum ThinkingOrbSize {
  /// Inline / button scale.
  inline(20),

  /// Avatar / panel scale.
  panel(64);

  const ThinkingOrbSize(this.px);
  final double px;
}

/// Convenience wrapper for [ThinkingOrb].
class MutandeOrb extends StatelessWidget {
  /// Full-panel loading (threads, bootstrap, etc.).
  const MutandeOrb.standard({
    super.key,
    this.size = ThinkingOrbSize.panel,
    this.semanticLabel,
    this.dark,
  });

  /// Inline loading (buttons, rows).
  const MutandeOrb.loading({
    super.key,
    this.size = ThinkingOrbSize.inline,
    this.semanticLabel,
    this.dark,
  });

  final ThinkingOrbSize size;
  final String? semanticLabel;
  final bool? dark;

  @override
  Widget build(BuildContext context) {
    return ThinkingOrb(
      size: size,
      semanticLabel: semanticLabel,
      dark: dark,
    );
  }
}

class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({
    super.key,
    this.size = ThinkingOrbSize.panel,
    this.speed = 1.0,
    this.paused = false,
    this.dark,
    this.semanticLabel,
  });

  final ThinkingOrbSize size;
  final double speed;
  final bool paused;

  /// When null, ink follows [ThemeData.brightness] (dark theme → light dots).
  final bool? dark;
  final String? semanticLabel;

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _tSec = 0.6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      setState(() {
        _tSec = elapsed.inMicroseconds / 1e6;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ThinkingOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused || oldWidget.size != widget.size) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce || widget.paused) {
      _ticker.stop();
      if (reduce) {
        setState(() => _tSec = 0.6);
      }
      return;
    }
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark =
        widget.dark ?? Theme.of(context).brightness == Brightness.dark;
    final preset = _resolvePreset(widget.size);
    final label = widget.semanticLabel ?? 'Working…';
    final px = widget.size.px;

    return Semantics(
      label: label,
      image: true,
      child: SizedBox(
        width: px,
        height: px,
        child: CustomPaint(
          painter: _ThinkingOrbPainter(
            tSec: _tSec * preset.speed * widget.speed,
            dark: dark,
            opts: preset.opts,
          ),
        ),
      ),
    );
  }
}

class _Resolved {
  const _Resolved({required this.speed, required this.opts});

  final double speed;
  final _ModeOpts opts;
}

class _ModeOpts {
  const _ModeOpts({
    this.orbitN = 12,
    this.ghostN = 40,
    this.ghostR = 0.9,
    this.partR = 1.2,
    this.partRDepth = 1.6,
  });

  final int orbitN;
  final int ghostN;
  final double ghostR;
  final double partR;
  final double partRDepth;
}

_Resolved _resolvePreset(ThinkingOrbSize size) {
  if (size == ThinkingOrbSize.panel) {
    return const _Resolved(speed: 1.885, opts: _ModeOpts());
  }
  return const _Resolved(
    speed: 3.9,
    opts: _ModeOpts(
      orbitN: 3,
      ghostN: 10,
      ghostR: 2.16,
      partR: 2.88,
      partRDepth: 3.84,
    ),
  );
}

class _Dot {
  _Dot({
    required this.x,
    required this.y,
    required this.z,
    required this.r,
    required this.white,
    this.a = 1,
  });

  final double x;
  final double y;
  final double z;
  final double r;
  final double white;
  final double a;
}

class _ThinkingOrbPainter extends CustomPainter {
  _ThinkingOrbPainter({
    required this.tSec,
    required this.dark,
    required this.opts,
  });

  final double tSec;
  final bool dark;
  final _ModeOpts opts;

  @override
  void paint(Canvas canvas, Size size) {
    _paintDots(canvas, _drawOrbits(size.shortestSide, tSec, opts), dark);
  }

  @override
  bool shouldRepaint(covariant _ThinkingOrbPainter oldDelegate) {
    return oldDelegate.tSec != tSec ||
        oldDelegate.dark != dark ||
        oldDelegate.opts != opts;
  }
}

double _hashD(num a, num b) {
  final h = math.sin(a * 12.9898 + b * 78.233) * 43758.5453;
  return h - h.floorToDouble();
}

double _radiusScale(double size, double pow) {
  return math.pow(size / 300, pow).toDouble();
}

typedef _Projector = List<double> Function(double x, double y, double z);

_Projector _makeProj(
  double yaw,
  double tilt,
  double cx,
  double cy,
  double scale,
) {
  final st = math.sin(tilt);
  final ct = math.cos(tilt);
  final sy = math.sin(yaw);
  final cyw = math.cos(yaw);
  return (x, y, z) {
    final x1 = x * cyw + z * sy;
    final z1 = -x * sy + z * cyw;
    final y1 = y * ct - z1 * st;
    final z2 = y * st + z1 * ct;
    return [cx + x1 * scale, cy - y1 * scale, z2];
  };
}

List<_Dot> _drawOrbits(double size, double t, _ModeOpts o) {
  final cx = size / 2;
  final cy = size / 2;
  final R = (size / 2) * 0.82;
  final pt = _makeProj(t * 0.12, 0.3, cx, cy, 1);
  final rs = _radiusScale(size, 0.6);

  final dots = <_Dot>[];
  final orbitN = o.orbitN;
  final ghostN = o.ghostN;
  const particles = 3;

  for (var orb = 0; orb < orbitN; orb++) {
    final h1 = _hashD(orb, 1.7);
    final h2 = _hashD(orb, 5.2);
    final h3 = _hashD(orb, 8.9);
    final ro = R * (0.45 + 0.52 * h1);
    final th = h1 * 2 * math.pi;
    final phi = math.acos(2 * h2 - 1);
    final nx = math.sin(phi) * math.cos(th);
    final ny = math.cos(phi);
    final nz = math.sin(phi) * math.sin(th);
    var ux = -ny;
    var uy = nx;
    const uz = 0.0;
    final ul = math.max(1e-6, math.sqrt(ux * ux + uy * uy));
    ux /= ul;
    uy /= ul;
    final vx = ny * uz - nz * uy;
    final vy = nz * ux - nx * uz;
    final vz = nx * uy - ny * ux;
    final speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1);

    for (var k = 0; k < ghostN; k++) {
      final a = (k / ghostN) * 2 * math.pi;
      final p = pt(
        (ux * math.cos(a) + vx * math.sin(a)) * ro,
        (uy * math.cos(a) + vy * math.sin(a)) * ro,
        (uz * math.cos(a) + vz * math.sin(a)) * ro,
      );
      final depth = (p[2] / ro + 1) / 2;
      dots.add(
        _Dot(
          x: p[0],
          y: p[1],
          z: p[2],
          r: o.ghostR * rs,
          white: 0.72,
          a: 0.5 * (0.4 + 0.6 * depth),
        ),
      );
    }

    for (var m = 0; m < particles; m++) {
      final a = t * speed + (m / particles) * 2 * math.pi + h2 * 6;
      final p = pt(
        (ux * math.cos(a) + vx * math.sin(a)) * ro,
        (uy * math.cos(a) + vy * math.sin(a)) * ro,
        (uz * math.cos(a) + vz * math.sin(a)) * ro,
      );
      final depth = (p[2] / ro + 1) / 2;
      dots.add(
        _Dot(
          x: p[0],
          y: p[1],
          z: p[2],
          r: (o.partR + o.partRDepth * depth) * rs,
          white: 0.3 - 0.22 * depth,
        ),
      );
    }
  }
  return dots;
}

void _paintDots(Canvas canvas, List<_Dot> dots, bool dark) {
  dots.sort((a, b) => a.z.compareTo(b.z));
  final paint = Paint()..style = PaintingStyle.fill;
  for (final d in dots) {
    if (d.a < 0.02) continue;
    final w = d.white.clamp(0.0, 1.0);
    final g = ((dark ? 1 - w : w) * 255).round();
    paint.color = Color.fromARGB((d.a * 255).round().clamp(0, 255), g, g, g);
    canvas.drawCircle(Offset(d.x, d.y), math.max(0.3, d.r), paint);
  }
}
