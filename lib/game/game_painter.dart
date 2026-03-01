import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'game_controller.dart';
import 'level_gen.dart';
import 'math_util.dart';
import 'models.dart';

class GamePainter extends CustomPainter {
  final GameController c;
  GamePainter(this.c);

  // Pixel grid size (in screen px). Bigger = chunkier pixels.
  static const double _px = 4.0;

  double _snap(double v) => (v / _px).roundToDouble() * _px;

  Offset _snapO(Offset o) => Offset(_snap(o.dx), _snap(o.dy));

  Rect _snapR(Rect r) {
    final l = _snap(r.left);
    final t = _snap(r.top);
    final rr = _snap(r.right);
    final bb = _snap(r.bottom);
    return Rect.fromLTRB(l, t, max(l + _px, rr), max(t + _px, bb));
  }

  Paint _p(Color c,
      {bool stroke = false,
        double w = 1,
        double a = 1.0,
        StrokeCap cap = StrokeCap.butt}) {
    return Paint()
      ..isAntiAlias = false
      ..color = c.withOpacity(a)
      ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = w
      ..strokeCap = cap;
  }

  void _pxRect(Canvas canvas, Rect r, Color color, {double a = 1.0}) {
    canvas.drawRect(_snapR(r), _p(color, a: a));
  }

  void _pxStrokeRect(Canvas canvas, Rect r, Color color,
      {double w = _px, double a = 1.0}) {
    final rr = _snapR(r);
    // stroke in pixel-art: draw 4 filled strips
    _pxRect(canvas, Rect.fromLTWH(rr.left, rr.top, rr.width, w), color, a: a);
    _pxRect(canvas, Rect.fromLTWH(rr.left, rr.bottom - w, rr.width, w), color,
        a: a);
    _pxRect(canvas, Rect.fromLTWH(rr.left, rr.top, w, rr.height), color, a: a);
    _pxRect(canvas, Rect.fromLTWH(rr.right - w, rr.top, w, rr.height), color,
        a: a);
  }

  void _pxCircle(Canvas canvas, Offset c, double r, Color color,
      {double a = 1.0}) {
    // Pixel circle approximation: filled discs on grid.
    final cc = _snapO(c);
    final rr = max(_px, r);
    final x0 = _snap(cc.dx - rr);
    final x1 = _snap(cc.dx + rr);
    final y0 = _snap(cc.dy - rr);
    final y1 = _snap(cc.dy + rr);

    for (double y = y0; y <= y1; y += _px) {
      for (double x = x0; x <= x1; x += _px) {
        final dx = (x + _px * 0.5) - cc.dx;
        final dy = (y + _px * 0.5) - cc.dy;
        if (dx * dx + dy * dy <= rr * rr) {
          canvas.drawRect(Rect.fromLTWH(x, y, _px, _px), _p(color, a: a));
        }
      }
    }
  }

  void _pxLine(Canvas canvas, Offset a, Offset b, Color color,
      {double w = _px, double aOp = 1.0}) {
    final aa = _snapO(a);
    final bb = _snapO(b);

    final dx = bb.dx - aa.dx;
    final dy = bb.dy - aa.dy;
    final steps = max(1, (max(dx.abs(), dy.abs()) / _px).round());

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = _snap(aa.dx + dx * t);
      final y = _snap(aa.dy + dy * t);
      canvas.drawRect(Rect.fromLTWH(x - w * 0.5, y - w * 0.5, w, w),
          _p(color, a: aOp));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final timeSec = c.tLevel;
    _drawSky(canvas, size, timeSec);

    // camera shake
    var ox = 0.0, oy = 0.0;
    if (c.fx.shakeT > 0) {
      final k = (c.fx.shakeT / 0.14);
      final m = c.fx.shakeMag * k;
      final rnd = Random();
      ox = (rnd.nextDouble() - 0.5) * m;
      oy = (rnd.nextDouble() - 0.5) * m;
    }

    canvas.save();
    canvas.translate(ox, oy);

    final level = c.currentLevel ?? LevelGen.makeLevel(c.levelNo);
    final objs = c.objectsFor(level, timeSec);

    // --- RECT PASS ---
    for (final o in objs) {
      if (o.shape != ObjShape.rect) continue;

      // Wind corridor is a translucent field (not a solid obstacle)
      if (o.kind == ObjKind.windCorridor) {
        _drawWindCorridor(canvas, o.rect!, timeSec);
        continue;
      }

      // Phase blocker: fade when inactive (collision handled in controller)
      if (o.kind == ObjKind.phaseBlocker) {
        final active = _phaseActiveFromRecord(o, timeSec);
        _drawPhaseBlocker(canvas, o.rect!, timeSec, active: active);
        continue;
      }

      // Normal rects
      _drawRectByKind(canvas, o.rect!, o.kind, timeSec);
    }

    // --- CIRCLE PASS ---
    for (final o in objs) {
      if (o.shape != ObjShape.circle) continue;

      if (o.kind == ObjKind.bumper) {
        _drawBumper(canvas, Offset(o.x, o.y), o.r, timeSec);
        continue;
      }

      if (o.kind == ObjKind.gravityWell) {
        _drawGravityWell(canvas, Offset(o.x, o.y), o.r, timeSec);
        continue;
      }

      if (o.kind == ObjKind.patrolDrone) {
        _drawPatrolDrone(canvas, Offset(o.x, o.y), o.r, timeSec);
        continue;
      }

      if (o.kind == ObjKind.laserSentinel) {
        final minSide = min(size.width, size.height);

        // Pull params if your objectsFor includes `src`, otherwise use defaults.
        final double beamLenNorm = _readSrcDouble(o, 'beamLen') ?? 0.45;
        final double beamWidthNorm = _readSrcDouble(o, 'beamWidth') ?? 0.018;
        final double angleSpeed = _readSrcDouble(o, 'angleSpeed') ?? 1.0;

        final len = beamLenNorm * minSide;
        final w = beamWidthNorm * minSide;
        final ang = timeSec * angleSpeed;

        _drawLaserSentinel(canvas, Offset(o.x, o.y), o.r, timeSec, len, w, ang);
        continue;
      }

      // fallback for unknown circle kinds
      _drawBumper(canvas, Offset(o.x, o.y), o.r, timeSec);
    }

    // portals
    for (final p in c.portalsFor(level)) {
      _drawPortal(canvas, Offset(p.ax, p.ay), p.r, timeSec);
      _drawPortal(canvas, Offset(p.bx, p.by), p.r, timeSec);
    }

    // items
    for (final it in c.itemsFor(level)) {
      _drawItem(canvas, Offset(it.x, it.y), it.r, it.gone, timeSec);
    }

    _drawGroundStrip(canvas, size);
    _drawGoalBand(canvas, c.goalBandRect(level));
    _drawHoleAndFlag(canvas, c.holePx(level));
    _drawBall(canvas, Offset(c.ball.x, c.ball.y), c.ball.r, timeSec, c.ball.gSign,
        c.ball.blinkSeed);

    // particles removed (bubbles)
    // _drawParticles(canvas, c.fx.particles);

    canvas.restore();
  }

  // ---------------------------
  // Helpers for new enemies
  // ---------------------------

  /// Phase logic (painter-side) so you don’t need to expose private controller methods.
  bool _phaseActiveFromRecord(dynamic o, double t) {
    // If the record contains src with phase params, use them.
    final double? period = _readSrcDouble(o, 'phasePeriod');
    final double? duty = _readSrcDouble(o, 'phaseDuty');
    final double? offset = _readSrcDouble(o, 'phaseOffset');

    final p = period ?? 2.0;
    final d = duty ?? 0.60;
    final off = offset ?? 0.0;

    final tt = (t + off) % p;
    return tt <= (p * d);
  }

  /// Tries to read o.src.<field> without hard-failing if your record doesn't include src.
  double? _readSrcDouble(dynamic o, String fieldName) {
    try {
      final src = (o as dynamic).src;
      final v = (src as dynamic).__get(fieldName);
      return (v as num?)?.toDouble();
    } catch (_) {
      // Try direct property access: src.beamLen etc.
      try {
        final src = (o as dynamic).src;
        final v = (src as dynamic).toJson()[fieldName];
        return (v as num?)?.toDouble();
      } catch (_) {
        try {
          final src = (o as dynamic).src;
          // ignore: unused_local_variable
          final _ = (src as dynamic).toString();
        } catch (_) {}
      }
    }

    // Best-effort: direct properties
    try {
      final src = (o as dynamic).src;
      final v = (src as dynamic).beamLen;
      if (fieldName == 'beamLen') return (v as num?)?.toDouble();
    } catch (_) {}
    try {
      final src = (o as dynamic).src;
      final v = (src as dynamic).beamWidth;
      if (fieldName == 'beamWidth') return (v as num?)?.toDouble();
    } catch (_) {}
    try {
      final src = (o as dynamic).src;
      final v = (src as dynamic).angleSpeed;
      if (fieldName == 'angleSpeed') return (v as num?)?.toDouble();
    } catch (_) {}
    try {
      final src = (o as dynamic).src;
      final v = (src as dynamic).phasePeriod;
      if (fieldName == 'phasePeriod') return (v as num?)?.toDouble();
    } catch (_) {}
    try {
      final src = (o as dynamic).src;
      final v = (src as dynamic).phaseDuty;
      if (fieldName == 'phaseDuty') return (v as num?)?.toDouble();
    } catch (_) {}
    try {
      final src = (o as dynamic).src;
      final v = (src as dynamic).phaseOffset;
      if (fieldName == 'phaseOffset') return (v as num?)?.toDouble();
    } catch (_) {}

    return null;
  }

  // ---------- Background ----------
  // CHANGE: clouds are restored to the original (smooth) look.
  void _drawSky(Canvas canvas, Size size, double t) {
    final rect = Offset.zero & size;
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF19B6FF), Color(0xFF53D8FF), Color(0xFFC9F6FF)],
        stops: [0.00, 0.45, 1.00],
      ).createShader(rect);
    canvas.drawRect(rect, sky);

    // subtle stripes
    final stripePaint = Paint()..color = Colors.white.withOpacity(0.10);
    for (var i = 0; i < 7; i++) {
      final y = (size.height * 0.06) + i * (size.height * 0.07);
      canvas.drawRect(Rect.fromLTWH(0.0, y, size.width, 10.0), stripePaint);
    }

    // clouds (ORIGINAL)
    _cloud(canvas,
        Offset(size.width * 0.26 + sin(t * 0.10) * 26, size.height * 0.20),
        0.85,
        face: true);
    _cloud(canvas,
        Offset(size.width * 0.70 + sin(t * 0.08 + 1.2) * 30, size.height * 0.16),
        0.95,
        face: true);
    _cloud(canvas,
        Offset(size.width * 0.50 + sin(t * 0.06 + 2.2) * 22, size.height * 0.28),
        0.70,
        face: false);

    // hills (leave as-is from your current file)
    _hill(canvas, size, size.height * 0.54, 18, t * 0.10 + 0.6,
        const Color(0xFF3FD26F), 0.0);
    _hill(canvas, size, size.height * 0.62, 22, t * 0.09 + 2.2,
        const Color(0xFF25B85B), 0.0);
  }

  // CHANGE: cloud renderer restored to original (smooth ovals + outline).
  void _cloud(Canvas canvas, Offset c, double s, {required bool face}) {
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = const Color(0xFF0E1A24).withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = Path()
      ..addOval(Rect.fromCenter(
          center: c.translate(-48 * s, 6 * s), width: 88 * s, height: 60 * s))
      ..addOval(Rect.fromCenter(
          center: c.translate(-10 * s, -8 * s), width: 112 * s, height: 76 * s))
      ..addOval(Rect.fromCenter(
          center: c.translate(44 * s, 6 * s), width: 100 * s, height: 68 * s))
      ..addOval(Rect.fromCenter(
          center: c.translate(86 * s, 12 * s), width: 72 * s, height: 52 * s));
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    if (!face) return;

    final eyeFill = Paint()..color = const Color(0xFF0E1A24).withOpacity(0.55);
    final mouth = Paint()
      ..color = const Color(0xFF0E1A24).withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final fx = c.dx + 8 * s;
    final fy = c.dy + 8 * s;
    canvas.drawCircle(Offset(fx - 18 * s, fy - 2 * s), 4 * s, eyeFill);
    canvas.drawCircle(Offset(fx + 6 * s, fy - 2 * s), 4 * s, eyeFill);

    canvas.drawArc(
      Rect.fromCircle(center: Offset(fx - 6 * s, fy + 10 * s), radius: 10 * s),
      0.15 * pi,
      0.70 * pi,
      false,
      mouth,
    );
  }

  void _hill(Canvas canvas, Size size, double yBase, double amp, double phase,
      Color fill, double strokeA) {
    // Filled stepped silhouette.
    final stepX = _px * 6;
    final groundY = size.height;

    final pts = <Offset>[];
    for (double x = 0.0; x <= size.width + stepX; x += stepX) {
      final tt = (x / size.width) * pi * 2;
      final y = yBase + sin(tt * 1.15 + phase) * amp;
      pts.add(Offset(_snap(x), _snap(y)));
    }

    // Raster fill by columns.
    for (int i = 0; i < pts.length - 1; i++) {
      final x0 = pts[i].dx;
      final x1 = pts[i + 1].dx;
      final yTop = min(pts[i].dy, pts[i + 1].dy);
      _pxRect(canvas, Rect.fromLTRB(x0, yTop, x1, groundY), fill);
    }

    // No stroke in pixel style (keep strokeA for compatibility, unused).
    // ignore: unused_local_variable
    final _ = strokeA;
  }

  // ---------- Foreground ----------
  void _drawGroundStrip(Canvas canvas, Size size) {
    final double stripH = max(86.0, size.height * 0.12);
    final double y0 = size.height - stripH;

    // Dirt (tile-like dither).
    final dirt = const Color(0xFFC9874D);
    final dirtDark = const Color(0xFFB8743E);
    final dirtDeep = const Color(0xFFA96435);

    final dirtRect = Rect.fromLTWH(0.0, y0 + 28.0, size.width, stripH - 28.0);
    _pxRect(canvas, dirtRect, dirt);

    for (double y = dirtRect.top; y < dirtRect.bottom; y += _px) {
      for (double x = 0; x < size.width; x += _px) {
        final k = (((x / _px).floor() + (y / _px).floor()) & 7);
        if (k == 0) {
          _pxRect(canvas, Rect.fromLTWH(x, y, _px, _px), dirtDark);
        } else if (k == 3) {
          _pxRect(canvas, Rect.fromLTWH(x, y, _px, _px), dirtDeep);
        }
      }
    }

    // Grass top (flat).
    final grass = const Color(0xFF2FD46F);
    final grassDark = const Color(0xFF1FAE56);
    final grassRect = Rect.fromLTWH(0.0, y0, size.width, 34.0);
    _pxRect(canvas, grassRect, grass);

    // Grass blades (chunky).
    for (double x = 0.0; x < size.width; x += _px * 2) {
      final double h = (x % (_px * 10) == 0.0) ? _px * 4 : _px * 2;
      _pxRect(
          canvas,
          Rect.fromLTWH(x, y0 + 28.0 - h, _px * 2, h),
          grassDark);
    }

    // Edge line.
    _pxRect(canvas, Rect.fromLTWH(0, y0 + 34.0, size.width, _px),
        const Color(0xFF0E1A24),
        a: 0.25);
  }

  void _drawGoalBand(Canvas canvas, Rect g) {
    final r = _snapR(g);
    _pxRect(canvas, r, const Color(0xFF2FD46F));
    _pxStrokeRect(canvas, r, const Color(0xFF0E1A24), a: 0.25, w: _px);
    // Add simple checker to read like a “goal zone”.
    for (double y = r.top; y < r.bottom; y += _px * 2) {
      for (double x = r.left; x < r.right; x += _px * 2) {
        final on = (((x / _px).floor() + (y / _px).floor()) & 1) == 0;
        if (on) {
          _pxRect(canvas, Rect.fromLTWH(x, y, _px * 2, _px * 2), Colors.white,
              a: 0.06);
        }
      }
    }
  }

  void _drawHoleAndFlag(Canvas canvas, ({double x, double y, double r}) h) {
    final cx = _snap(h.x);
    final cy = _snap(h.y);
    final rr = max(_px * 2, h.r);

    // Hole shadow (pixel oval-ish).
    for (int i = 0; i < 3; i++) {
      _pxCircle(canvas, Offset(cx, cy), rr * (1.4 - i * 0.22),
          const Color(0xFF000000),
          a: 0.12 + i * 0.08);
    }

    // Flag pole.
    final poleTop = Offset(cx, cy - _snap(56));
    final poleBot = Offset(cx, cy - _snap(10));
    _pxLine(canvas, poleTop, poleBot, const Color(0xFF0E1A24),
        w: _px, aOp: 0.35);

    // Flag (pixel triangle).
    final flag = const Color(0xFFFF4D5C);
    for (int yy = 0; yy < 6; yy++) {
      final w = (6 - yy);
      for (int xx = 0; xx < w; xx++) {
        _pxRect(
            canvas,
            Rect.fromLTWH(cx + _px * (1 + xx), poleTop.dy + _px * (2 + yy), _px,
                _px),
            flag);
      }
    }
    // Flag outline.
    _pxRect(canvas,
        Rect.fromLTWH(cx + _px, poleTop.dy + _px * 2, _px, _px),
        const Color(0xFF0E1A24),
        a: 0.35);
  }

  void _drawRectByKind(Canvas canvas, Rect r, ObjKind kind, double t) {
    switch (kind) {
      case ObjKind.green:
        _drawQuestionBlock(canvas, r, t);
        break;
      case ObjKind.red:
        _drawBrick(canvas, r);
        break;
      case ObjKind.sticky:
        _drawPipe(canvas, r, const Color(0xFF6E7A8C), const Color(0xFFB9C0CF));
        break;
      case ObjKind.laser:
        _drawSpikes(canvas, r, t);
        break;

    // These are drawn in special passes:
      case ObjKind.bumper:
      case ObjKind.gravityWell:
      case ObjKind.laserSentinel:
      case ObjKind.patrolDrone:
      case ObjKind.phaseBlocker:
      case ObjKind.windCorridor:
      // do nothing here
        break;
    }
  }

  void _drawQuestionBlock(Canvas canvas, Rect r, double t) {
    final rr = _snapR(r);

    // Mario-ish palette.
    final base = const Color(0xFFF3B237);
    final hi = const Color(0xFFFFE08A);
    final lo = const Color(0xFFD59618);
    final outline = const Color(0xFF0E1A24);

    _drawBlockBase(canvas, rr, base: base, hi: hi, lo: lo);

    // Pixel "?" made from tiles (no font rendering).
    final pulse = (sin(t * 2.6) * 0.5 + 0.5);
    final bob = _snap((_px * 1.0) * (0.4 + 0.6 * pulse));

    final s = max(_px, min(rr.width, rr.height) / 10);
    final cx = rr.center.dx;
    final cy = rr.center.dy + _px - bob;

    const q = [
      "00111100",
      "01100110",
      "00000110",
      "00001100",
      "00011000",
      "00011000",
      "00000000",
      "00011000",
    ];

    final left = _snap(cx - (q[0].length * s) / 2);
    final top = _snap(cy - (q.length * s) / 2);

    for (int y = 0; y < q.length; y++) {
      for (int x = 0; x < q[y].length; x++) {
        if (q[y][x] == '0') continue;
        final pxr = Rect.fromLTWH(left + x * s, top + y * s, s, s);
        _pxRect(canvas, pxr, Colors.white, a: 0.92);
      }
    }

    // tiny sparkle corner pixel
    _pxRect(canvas,
        Rect.fromLTWH(rr.left + _px * 2, rr.top + _px * 2, _px, _px), outline,
        a: 0.10);
  }

  void _drawBrick(Canvas canvas, Rect r) {
    final rr = _snapR(r);

    final base = const Color(0xFFD76A3A);
    final hi = const Color(0xFFF3925F);
    final lo = const Color(0xFFB94F2C);
    final outline = const Color(0xFF0E1A24);

    _drawBlockBase(canvas, rr, base: base, hi: hi, lo: lo);

    // Brick seams (pixel lines).
    final seam = outline.withOpacity(0.20);
    final seam2 = outline.withOpacity(0.12);

    // Horizontal seam mid.
    _pxRect(
        canvas,
        Rect.fromLTWH(rr.left + _px, rr.top + rr.height * 0.50, rr.width - _px * 2,
            _px),
        seam);

    // Vertical seams alternating.
    final cols = max(2, (rr.width / (_px * 6)).floor());
    final step = rr.width / cols;
    for (int i = 1; i < cols; i++) {
      final x = _snap(rr.left + i * step);
      final offset = (i.isEven) ? rr.height * 0.25 : rr.height * 0.65;
      _pxRect(canvas,
          Rect.fromLTWH(x, rr.top + _snap(offset), _px, rr.height * 0.18), seam2);
    }
  }

  void _drawBlockBase(Canvas canvas, Rect r,
      {required Color base, required Color hi, required Color lo}) {
    final rr = _snapR(r);
    final outline = const Color(0xFF0E1A24);

    // Drop shadow (pixel offset).
    _pxRect(canvas, rr.shift(Offset(_px, _px * 1.5)), outline, a: 0.16);

    // Fill.
    _pxRect(canvas, rr, base);

    // Top highlight strip.
    _pxRect(
        canvas,
        Rect.fromLTWH(rr.left, rr.top, rr.width, max(_px * 2, rr.height * 0.22)),
        hi,
        a: 0.75);

    // Bottom shade strip.
    _pxRect(
        canvas,
        Rect.fromLTWH(rr.left, rr.bottom - max(_px * 2, rr.height * 0.20), rr.width,
            max(_px * 2, rr.height * 0.20)),
        lo,
        a: 0.30);

    // Outline.
    _pxStrokeRect(canvas, rr, outline, a: 0.55, w: _px);
  }

  void _drawPipe(Canvas canvas, Rect r, Color body, Color rim) {
    final rr = _snapR(r);
    final outline = const Color(0xFF0E1A24);

    // Shadow.
    _pxRect(canvas, rr.shift(Offset(_px, _px * 1.5)), outline, a: 0.16);

    // Body.
    _pxRect(canvas, rr, body);

    // Rim (top lip).
    final rimH = max(_px * 4, rr.height * 0.22);
    final rimRect = Rect.fromLTWH(rr.left - _px * 2, rr.top, rr.width + _px * 4,
        _snap(rimH));
    _pxRect(canvas, rimRect, rim);

    // Inner highlight column.
    _pxRect(
        canvas,
        Rect.fromLTWH(rr.left + _px * 2, rr.top + _px * 2, _px * 2,
            max(_px, rr.height - _px * 4)),
        Colors.white,
        a: 0.10);

    // Outline.
    _pxStrokeRect(canvas, rr, outline, a: 0.35, w: _px);
    _pxStrokeRect(canvas, rimRect, outline, a: 0.35, w: _px);
  }

  void _drawSpikes(Canvas canvas, Rect r, double t) {
    final rr = _snapR(r);
    final outline = const Color(0xFF0E1A24);

    _pxRect(canvas, rr, const Color(0xFFFF4D5C));
    _pxStrokeRect(canvas, rr, outline, a: 0.55, w: _px);

    // Triangular pixel spikes.
    final n = max(6, (rr.width / (_px * 4)).floor());
    final step = rr.width / n;
    for (int i = 0; i < n; i++) {
      final x0 = rr.left + i * step;
      final x1 = x0 + step;
      final xm = (x0 + x1) * 0.5;
      final y0 = rr.bottom - _px;
      final yT = rr.top + _px * 2;

      // Fill with a small pixel triangle.
      final height = max(3, ((y0 - yT) / _px).round());
      for (int yy = 0; yy < height; yy++) {
        final rowW = (yy + 1);
        final y = _snap(y0 - yy * _px);
        for (int xx = -rowW; xx <= rowW; xx++) {
          final x = _snap(xm + xx * _px);
          if (x < x0 || x > x1) continue;
          _pxRect(canvas, Rect.fromLTWH(x, y, _px, _px), Colors.white, a: 0.80);
        }
      }
    }

    // Glow band (pixel).
    final glow = 0.18 + 0.18 * (sin(t * 8.0) * 0.5 + 0.5);
    _pxRect(
        canvas,
        Rect.fromLTWH(rr.left + _px * 2, rr.top + _px * 2,
            max(_px, rr.width - _px * 4), max(_px, rr.height - _px * 4)),
        Colors.white,
        a: glow);
  }

  // ---------------------------
  // New enemy renderers
  // ---------------------------

  void _drawGravityWell(Canvas canvas, Offset c, double r, double t) {
    final cc = _snapO(c);
    final rr = max(_px * 4, r);

    // Dark core + purple ring using pixel circles.
    _pxCircle(canvas, cc, rr, const Color(0xFF2A1B47), a: 0.55);
    _pxCircle(canvas, cc, rr * 0.70, const Color(0xFF6B42C8), a: 0.35);
    _pxCircle(canvas, cc, rr * 0.38, Colors.black, a: 0.12);

    // Swirl line (pixel line).
    final ang = t * 2.0;
    final a = Offset(cc.dx + cos(ang) * rr * 0.55, cc.dy + sin(ang) * rr * 0.55);
    final b = Offset(
        cc.dx + cos(ang + 2.1) * rr * 0.35, cc.dy + sin(ang + 2.1) * rr * 0.35);
    _pxLine(canvas, a, b, Colors.white, w: _px, aOp: 0.18);
  }

  void _drawLaserSentinel(
      Canvas canvas, Offset c, double r, double t, double len, double w, double ang) {
    final cc = _snapO(c);
    final rr = max(_px * 4, r);

    // Beam (pixel line).
    final end = Offset(cc.dx + cos(ang) * len, cc.dy + sin(ang) * len);
    _pxLine(canvas, cc, end, const Color(0xFFFF4D5C),
        w: max(_px, _snap(w)), aOp: 0.70);

    // Body (pixel disc).
    _pxCircle(canvas, cc, rr, const Color(0xFF3A2D2D), a: 0.85);
    _pxCircle(canvas, cc, rr, Colors.white, a: 0.10);
    // Outline by sprinkling edge pixels (cheap): draw a darker ring.
    _pxCircle(canvas, cc, rr + _px, const Color(0xFF0E1A24), a: 0.12);

    // Eye in direction of beam.
    final eyeC =
    Offset(cc.dx + cos(ang) * rr * 0.35, cc.dy + sin(ang) * rr * 0.35);
    _pxCircle(canvas, eyeC, max(_px, rr * 0.20), const Color(0xFFFF4D5C), a: 0.90);
  }

  void _drawPatrolDrone(Canvas canvas, Offset c, double r, double t) {
    final cc = _snapO(c);
    final rr = max(_px * 4, r);

    _pxCircle(canvas, cc, rr, const Color(0xFF1B1E2A), a: 0.85);

    // Teeth/spikes (pixel rays).
    const spikes = 10;
    for (int i = 0; i < spikes; i++) {
      final a = (i / spikes) * pi * 2 + t * 1.6;
      final p1 = Offset(cc.dx + cos(a) * rr * 0.55, cc.dy + sin(a) * rr * 0.55);
      final p2 = Offset(cc.dx + cos(a) * rr * 0.98, cc.dy + sin(a) * rr * 0.98);
      _pxLine(canvas, p1, p2, Colors.white, w: _px, aOp: 0.22);
    }

    _pxCircle(canvas, cc, rr * 0.28, const Color(0xFFFF4D5C), a: 0.75);
  }

  void _drawWindCorridor(Canvas canvas, Rect r, double t) {
    final rr = _snapR(r);
    final outline = const Color(0xFF0E1A24);

    // Pixel fill.
    _pxRect(canvas, rr, const Color(0xFF9EE7FF), a: 0.14);
    _pxStrokeRect(canvas, rr, outline, a: 0.16, w: _px);

    // Moving arrows as chunky chevrons.
    final midY = _snap(rr.center.dy);
    for (double x = rr.left + _px * 4; x < rr.right - _px * 6; x += _px * 10) {
      final phase = ((t * 60.0 + x) % (_px * 10));
      final xx = _snap(x + phase);

      // main dash
      _pxRect(canvas, Rect.fromLTWH(xx, midY, _px * 3, _px), Colors.white, a: 0.28);
      // chevron
      _pxRect(canvas, Rect.fromLTWH(xx + _px * 3, midY - _px, _px, _px), Colors.white,
          a: 0.28);
      _pxRect(canvas, Rect.fromLTWH(xx + _px * 3, midY + _px, _px, _px), Colors.white,
          a: 0.28);
    }
  }

  void _drawPhaseBlocker(Canvas canvas, Rect r, double t, {required bool active}) {
    // Same block style, just fade.
    final alpha = active ? 1.0 : 0.18;
    canvas.saveLayer(_snapR(r),
        Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
    _drawQuestionBlock(canvas, r, t);
    canvas.restore();
  }

  // ---------------------------
  // Existing circles
  // ---------------------------

  void _drawBumper(Canvas canvas, Offset c, double r, double t) {
    final cc = _snapO(c);
    final rr = max(_px * 4, r);

    // Shadow.
    _pxCircle(canvas, cc + Offset(_px, _px * 1.5), rr * 1.05,
        const Color(0xFF0E1A24),
        a: 0.14);

    // Body.
    _pxCircle(canvas, cc, rr, const Color(0xFFFFE57A), a: 1.0);
    _pxCircle(canvas, cc, rr + _px, const Color(0xFF0E1A24), a: 0.18);

    // Specular highlight.
    _pxCircle(canvas, cc + Offset(-rr * 0.32, -rr * 0.34), rr * 0.30,
        Colors.white,
        a: 0.42);

    // Pulsing ring.
    final ringAlpha = 0.18 + 0.18 * (sin(t * 5.2) * 0.5 + 0.5);
    _pxCircle(canvas, cc, rr * 0.62, Colors.white, a: ringAlpha);
  }

  void _drawPortal(Canvas canvas, Offset c, double r, double t) {
    final cc = _snapO(c);
    final rr = max(_px * 4, r);

    // Shadow.
    _pxCircle(canvas, cc + Offset(_px, _px * 1.5), rr * 1.08,
        const Color(0xFF0E1A24),
        a: 0.14);

    final pulse = 0.10 * (sin(t * 4.4) * 0.5 + 0.5);
    final pr = rr * (1.0 + pulse);

    _pxCircle(canvas, cc, pr, const Color(0xFFA694FF), a: 1.0);
    _pxCircle(canvas, cc, pr + _px, const Color(0xFF0E1A24), a: 0.16);
    _pxCircle(canvas, cc, pr * 0.62, Colors.white, a: 0.22);

    // Inner swirl pixel.
    final a = t * 3.0;
    final p = Offset(cc.dx + cos(a) * pr * 0.25, cc.dy + sin(a) * pr * 0.25);
    _pxRect(canvas, Rect.fromLTWH(p.dx, p.dy, _px, _px), Colors.white, a: 0.28);
  }

  void _drawItem(Canvas canvas, Offset c, double r, bool gone, double t) {
    if (gone) return;

    final cc = _snapO(c);
    final rr = max(_px * 3, r);

    // Shadow.
    _pxCircle(canvas, cc + Offset(_px, _px * 1.5), rr * 1.06,
        const Color(0xFF0E1A24),
        a: 0.14);

    final tw = 0.35 + 0.65 * (sin(t * 4.8 + cc.dx * 0.01) * 0.5 + 0.5);
    final w = rr * 2 * (0.70 + 0.30 * tw);

    // Pixel “coin” as ellipse-ish: draw discs across x-range.
    final halfW = w * 0.5;
    for (double x = -halfW; x <= halfW; x += _px) {
      final k = (x / halfW).abs().clamp(0.0, 1.0);
      final rad = rr * sqrt(1 - k * k);
      _pxCircle(canvas, Offset(cc.dx + x, cc.dy), rad, const Color(0xFFFFE57A),
          a: 1.0);
    }
    // Outline hint.
    _pxCircle(canvas, cc, rr + _px, const Color(0xFF0E1A24), a: 0.14);
  }

  // CHANGE: ball renderer restored to the original (smooth) look.
  void _drawBall(Canvas canvas, Offset c, double r, double t, int gSign,
      double blinkSeed) {
    canvas.drawOval(
      Rect.fromCenter(center: c + const Offset(4, 7), width: r * 2.2, height: r * 1.4),
      Paint()..color = const Color(0xFF0E1A24).withOpacity(0.18),
    );

    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFF8FBFF));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFF0E1A24).withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.34),
      r * 0.30,
      Paint()..color = Colors.white.withOpacity(0.55),
    );

    final blink = sin(t * 2.6 + blinkSeed) > 0.985;
    final ex = r * 0.32;
    final ey = -r * 0.10;

    final eyePaint = Paint()..color = const Color(0xFF0E1A24).withOpacity(0.68);
    final stroke = Paint()
      ..color = const Color(0xFF0E1A24).withOpacity(0.60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (final s in [-1.0, 1.0]) {
      final epos = c + Offset(ex * s, ey);
      if (blink) {
        canvas.drawLine(epos + const Offset(-6, 0), epos + const Offset(6, 0), stroke);
      } else {
        canvas.drawCircle(epos, 4.1, eyePaint);
      }
    }

    canvas.drawArc(
      Rect.fromCircle(center: c + Offset(0, r * 0.22), radius: 8.2),
      0.15 * pi,
      0.70 * pi,
      false,
      stroke,
    );

    final dir = gSign.toDouble();
    final ax = c.dx;
    final ay = c.dy - r * 1.65;

    final arrow = Paint()
      ..color = const Color(0xFF0E1A24).withOpacity(0.70)
      ..strokeWidth = 3;

    canvas.drawLine(Offset(ax - 7, ay + 10 * dir), Offset(ax, ay + 20 * dir), arrow);
    canvas.drawLine(Offset(ax, ay + 20 * dir), Offset(ax + 7, ay + 10 * dir), arrow);
  }

  void _drawParticles(Canvas canvas, List<Particle> particles) {
    for (final p in particles) {
      final a = (1 - (p.life / p.ttl)).clamp(0.0, 1.0);
      _pxCircle(canvas, Offset(p.x, p.y), max(_px, p.size * 0.5), p.color, a: a);
    }
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}