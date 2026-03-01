import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'level_gen.dart';
import 'math_util.dart';
import 'models.dart';
import 'storage.dart';

class WorldParams {
  double pad = 18;

  final double g = 1650;
  final double maxSpeed = 1500;
  final double airDamp = 0.9982;
  final double wallRestitution = 0.52;
  final double safeRestitution = 0.68;
  final double bumperRestitution = 0.92;
  final double stickyRestitution = 0.25;
  final double tangentialFriction = 0.985;
  final double flipCooldown = 0.09;
  final double flipKick = 420;
  final int substeps = 4;
  final double minHV = 220;
  final double hvBoost = 880;
  final double hvBlend = 0.050;
  final double holeRadiusScale = 1.75;
  final double holeWinMul = 0.98;
}

class GameController extends ChangeNotifier {
  final WorldParams world = WorldParams();
  final FxState fx = FxState();

  Size viewport = Size.zero;
  double dpr = 1;

  late Ball ball;
  Level? currentLevel;

  bool running = false;
  bool paused = false;

  int levelIndex = 0;
  int flips = 0;
  int coins = 0;

  double tLevel = 0;
  Duration _lastTick = Duration.zero;

  Ticker? _ticker;

  bool showStartOverlay = true;
  OverlayMessage? messageOverlay;

  Map<String, int> bestByLevel = {};

  int get levelNo => levelIndex + 1;

  String get bestText {
    final b = bestByLevel['$levelNo'];
    return b == null ? '—' : '$b';
  }

  Future<void> init() async {
    bestByLevel = await BestStorage.load();
    ball = Ball(
      r: 18,
      x: 0,
      y: 0,
      vx: 140,
      vy: 0,
      gSign: 1,
      flipLock: 0,
      blinkSeed: Random().nextDouble() * 10,
      portalLock: 0,
    );

    _ticker = Ticker(_onTick)..start();
    resetLevel(); // preview level
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void setViewport(Size size, double devicePixelRatio) {
    viewport = size;
    dpr = devicePixelRatio;
    if (viewport.shortestSide <= 0) return;
    world.pad = clampd(viewport.shortestSide * 0.03, 12, 22);
  }

  void startGame() {
    showStartOverlay = false;
    messageOverlay = null;
    running = true;
    paused = false;
    levelIndex = 0;
    resetLevel();
    notifyListeners();
  }

  void restartLevel() {
    messageOverlay = null;
    paused = false;
    resetLevel();
    notifyListeners();
  }

  void nextLevel() {
    messageOverlay = null;
    paused = false;
    levelIndex = clampd(levelIndex + 1.0, 0, LevelGen.maxLevels - 1).toInt();
    resetLevel();
    notifyListeners();
  }

  void togglePause() {
    if (!running) return;
    paused = !paused;
    notifyListeners();
  }

  void onFlip() {
    if (!running || paused) return;
    if (showStartOverlay) return;
    if (messageOverlay != null) return;
    if (ball.flipLock > 0) return;

    ball.gSign *= -1;
    flips++;
    ball.vy = clampd(
      ball.vy + world.flipKick * ball.gSign,
      -world.maxSpeed,
      world.maxSpeed,
    );
    ball.flipLock = world.flipCooldown;

    _pop(ball.x, ball.y, 10, const Color(0xF2FFFFFF), 420);
    notifyListeners();
  }

  void buildLevel() {
    currentLevel = LevelGen.makeLevel(levelNo);
  }

  void resetLevel() {
    flips = 0;
    coins = 0;
    tLevel = 0;

    buildLevel();

    if (viewport.shortestSide > 0) {
      ball.r = clampd(viewport.shortestSide * 0.020, 14, 22);
    }

    final seed = (hashSeed(currentLevel!.no) ^ 0xA5A5A5A5) & 0xFFFFFFFF;
    final rng = Mulberry32(seed);

    ball.x = viewport.width * (0.50 + (rng.next() - 0.5) * 0.20);
    ball.y = world.pad + ball.r + 10;

    final dir = (rng.next() < 0.5) ? -1 : 1;
    final base = world.minHV + rng.next() * 160;
    ball.vx = dir * base;
    ball.vy = 0;
    ball.gSign = 1;
    ball.flipLock = 0;
    ball.portalLock = 0;

    fx.particles.clear();
    fx.shakeT = 0;
    fx.shakeMag = 0;
  }

  void _onTick(Duration elapsed) {
    final dtRaw = _lastTick == Duration.zero
        ? 1 / 60.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;

    _lastTick = elapsed;
    final dt = clampd(dtRaw, 0, 1 / 30);

    if (running && !paused) {
      _step(dt);
    } else {
      tLevel += dt; // keep time moving for animations
      _updateParticles(dt);
    }

    notifyListeners();
  }

  // ------------------------------------------------------------
  // Public helpers for the painter
  // ------------------------------------------------------------
  Rect goalBandRect(Level level) => _goalBandRect(level);
  ({double x, double y, double r}) holePx(Level level) => _holePx(level);

  /// Painter-safe helper for phase visuals (so painter doesn't touch private).
  bool phaseActiveForPainter(LevelObjNorm o, double t) => _phaseActive(o, t);

  // ---------- Normalized -> Px helpers ----------
  Rect _goalBandRect(Level level) {
    final pad = world.pad;
    final y = level.goalBand.y * viewport.height;
    final h = level.goalBand.h * viewport.height;
    final x = pad + 10;
    final w = viewport.width - (pad + 10) * 2;
    return Rect.fromLTWH(x, y, w, h);
  }

  ({double x, double y, double r}) _holePx(Level level) {
    final band = _goalBandRect(level);
    final hx = band.left + band.width * level.hole.x;
    final hy = band.top + band.height * level.hole.y;
    final base = clampd(min(band.width, band.height) * 0.10, 14, 22);
    final hr = base * world.holeRadiusScale;
    return (x: hx, y: hy, r: hr);
  }

  bool _reachedHole(Level level) {
    final h = _holePx(level);
    final d = (Offset(ball.x, ball.y) - Offset(h.x, h.y)).distance;
    final req = max(10, h.r * world.holeWinMul);
    return d <= req;
  }

  // ---------- Motion application ----------
  Rect _normRectToPx(LevelObjNorm o) {
    final pad = world.pad;
    var x = o.x * viewport.width;
    var y = o.y * viewport.height;
    var w = o.w * viewport.width;
    var h = o.h * viewport.height;

    final minW = clampd(min(viewport.width, viewport.height) * 0.052, 28, 54);
    final minH = minW * 0.70;

    w = max(w, minW);
    h = max(h, minH);

    x = clampd(x, pad, viewport.width - pad - w);
    y = clampd(y, pad, viewport.height - pad - h);

    return Rect.fromLTWH(x, y, w, h);
  }

  ({double x, double y, double r}) _normCircleToPx(LevelObjNorm o) {
    final pad = world.pad;
    final r = max(
      clampd(o.r * min(viewport.width, viewport.height), 16, 44),
      ball.r * 0.70,
    );
    var x = o.x * viewport.width;
    var y = o.y * viewport.height;
    x = clampd(x, pad + r, viewport.width - pad - r);
    y = clampd(y, pad + r, viewport.height - pad - r);
    return (x: x, y: y, r: r);
  }

  Rect _applyMotionRectPx(Rect rect, Motion? motion, double timeSec) {
    if (motion == null) return rect;
    final s = sin((timeSec * motion.freq + motion.phase) * pi * 2);
    var x = rect.left;
    var y = rect.top;
    if (motion.axis == "x") x += s * (motion.amp * viewport.width);
    if (motion.axis == "y") y += s * (motion.amp * viewport.height);
    final pad = world.pad;
    x = clampd(x, pad, viewport.width - pad - rect.width);
    y = clampd(y, pad, viewport.height - pad - rect.height);
    return Rect.fromLTWH(x, y, rect.width, rect.height);
  }

  ({double x, double y, double r}) _applyMotionCirclePx(
      ({double x, double y, double r}) c,
      Motion? motion,
      double timeSec,
      ) {
    if (motion == null) return c;
    final s = sin((timeSec * motion.freq + motion.phase) * pi * 2);
    var x = c.x;
    var y = c.y;
    if (motion.axis == "x") x += s * (motion.amp * viewport.width);
    if (motion.axis == "y") y += s * (motion.amp * viewport.height);
    final pad = world.pad;
    x = clampd(x, pad + c.r, viewport.width - pad - c.r);
    y = clampd(y, pad + c.r, viewport.height - pad - c.r);
    return (x: x, y: y, r: c.r);
  }

  /// IMPORTANT: includes `src` so gameplay code can read enemy parameters.
  List<({
  LevelObjNorm src,
  ObjShape shape,
  ObjKind kind,
  Rect? rect,
  double x,
  double y,
  double r
  })> objectsFor(Level level, double timeSec) {
    final out = <({
    LevelObjNorm src,
    ObjShape shape,
    ObjKind kind,
    Rect? rect,
    double x,
    double y,
    double r
    })>[];

    for (final o in level.objects) {
      if (o.shape == ObjShape.rect) {
        final r0 = _normRectToPx(o);
        final r1 = _applyMotionRectPx(r0, o.motion, timeSec);
        out.add((src: o, shape: ObjShape.rect, kind: o.kind, rect: r1, x: 0, y: 0, r: 0));
      } else {
        final c0 = _normCircleToPx(o);
        final c1 = _applyMotionCirclePx(c0, o.motion, timeSec);
        out.add((src: o, shape: ObjShape.circle, kind: o.kind, rect: null, x: c1.x, y: c1.y, r: c1.r));
      }
    }
    return out;
  }

  List<({ItemNorm src, double x, double y, double r, bool gone})> itemsFor(Level level) {
    final pad = world.pad;
    final out = <({ItemNorm src, double x, double y, double r, bool gone})>[];
    for (final src in level.items) {
      final r = src.r * min(viewport.width, viewport.height);
      var x = src.x * viewport.width;
      var y = src.y * viewport.height;
      x = clampd(x, pad + r, viewport.width - pad - r);
      y = clampd(y, pad + r, viewport.height - pad - r);
      out.add((src: src, x: x, y: y, r: r, gone: src.gone));
    }
    return out;
  }

  List<({double ax, double ay, double bx, double by, double r})> portalsFor(Level level) {
    final pad = world.pad;
    final out = <({double ax, double ay, double bx, double by, double r})>[];
    for (final p in level.portals) {
      final r = p.r * min(viewport.width, viewport.height);
      var ax = p.a.dx * viewport.width;
      var ay = p.a.dy * viewport.height;
      var bx = p.b.dx * viewport.width;
      var by = p.b.dy * viewport.height;

      ax = clampd(ax, pad + r, viewport.width - pad - r);
      ay = clampd(ay, pad + r, viewport.width - pad - r);
      bx = clampd(bx, pad + r, viewport.width - pad - r);
      by = clampd(by, pad + r, viewport.width - pad - r);

      out.add((ax: ax, ay: ay, bx: bx, by: by, r: r));
    }
    return out;
  }

  // ---------- Enemy helpers ----------
  bool _pointInRect(double px, double py, Rect r) =>
      px >= r.left && px <= r.right && py >= r.top && py <= r.bottom;

  bool _phaseActive(LevelObjNorm o, double t) {
    final period = o.phasePeriod ?? 2.0;
    final duty = o.phaseDuty ?? 0.6;
    final offset = o.phaseOffset ?? 0.0;

    final tt = (t + offset) % period;
    return tt <= (period * duty);
  }

  // ---------- Physics ----------
  void _enforceHorizontalMotion(double dt) {
    final dir = ball.vx >= 0 ? 1.0 : -1.0;
    final target = dir * max(world.minHV, min(world.hvBoost, ball.vx.abs() + 24));
    ball.vx += (target - ball.vx) * (1 - pow(1 - world.hvBlend, dt * 60));
    if (ball.vx.abs() < world.minHV) ball.vx = dir * world.minHV;
  }

  void _integrate(double dt) {
    _enforceHorizontalMotion(dt);

    ball.vy += (world.g * ball.gSign) * dt;

    final damp = pow(world.airDamp, dt * 60).toDouble();
    ball.vx *= damp;
    ball.vy *= damp;

    ball.vx = clampd(ball.vx, -world.maxSpeed, world.maxSpeed);
    ball.vy = clampd(ball.vy, -world.maxSpeed, world.maxSpeed);

    ball.x += ball.vx * dt;
    ball.y += ball.vy * dt;
  }

  void _collideWorld() {
    final pad = world.pad;
    final minX = pad + ball.r;
    final maxX = viewport.width - pad - ball.r;
    final minY = pad + ball.r;
    final maxY = viewport.height - pad - ball.r;

    if (ball.x < minX) {
      ball.x = minX;
      ball.vx = ball.vx.abs() * max(0.62, world.wallRestitution);
      if (ball.vx.abs() < world.minHV) ball.vx = world.minHV;
      _pop(ball.x, ball.y, 10, const Color(0xF2FFFFFF), 520);
      _shake(3);
    } else if (ball.x > maxX) {
      ball.x = maxX;
      ball.vx = -ball.vx.abs() * max(0.62, world.wallRestitution);
      if (ball.vx.abs() < world.minHV) ball.vx = -world.minHV;
      _pop(ball.x, ball.y, 10, const Color(0xF2FFFFFF), 520);
      _shake(3);
    }

    if (ball.y < minY) {
      ball.y = minY;
      ball.vy = ball.vy.abs() * world.wallRestitution;
      _pop(ball.x, ball.y, 10, const Color(0xF2FFFFFF), 520);
    } else if (ball.y > maxY) {
      ball.y = maxY;
      ball.vy = -ball.vy.abs() * world.wallRestitution;
      _pop(ball.x, ball.y, 10, const Color(0xF2FFFFFF), 520);
    }
  }

  bool _resolveCircleAabb(Rect rect, double restitution, Color sparkColor) {
    final hit = circleRectOverlap(
      ball.x,
      ball.y,
      ball.r,
      rect.left,
      rect.top,
      rect.width,
      rect.height,
    );
    if (hit == null) return false;

    ball.x += hit.nx * hit.pen;
    ball.y += hit.ny * hit.pen;

    final vn = ball.vx * hit.nx + ball.vy * hit.ny;
    if (vn < 0) {
      final j = -(1 + restitution) * vn;
      ball.vx += j * hit.nx;
      ball.vy += j * hit.ny;

      final tx = -hit.ny;
      final ty = hit.nx;
      final vt = ball.vx * tx + ball.vy * ty;
      final fr = world.tangentialFriction;

      ball.vx -= vt * (1 - fr) * tx;
      ball.vy -= vt * (1 - fr) * ty;
    }

    _pop(hit.px, hit.py, 14, sparkColor, 820);
    _shake(2.5);
    return true;
  }

  bool _resolveCircleCircle(double cx, double cy, double cr, double restitution, Color sparkColor) {
    final hit = circleCircleOverlap(ball.x, ball.y, ball.r, cx, cy, cr);
    if (hit == null) return false;

    ball.x += hit.nx * hit.pen;
    ball.y += hit.ny * hit.pen;

    final vn = ball.vx * hit.nx + ball.vy * hit.ny;
    if (vn < 0) {
      final j = -(1 + restitution) * vn;
      ball.vx += j * hit.nx;
      ball.vy += j * hit.ny;
    }

    _pop(
      ball.x - hit.nx * ball.r * 0.2,
      ball.y - hit.ny * ball.r * 0.2,
      16,
      sparkColor,
      980,
    );
    _shake(3.0);
    return true;
  }

  void _step(double dt) {
    final level = currentLevel;
    if (level == null || viewport.isEmpty) return;

    ball.flipLock = max(0, ball.flipLock - dt);
    ball.portalLock = max(0, ball.portalLock - dt);

    final n = world.substeps;
    final h = dt / n;

    for (var i = 0; i < n; i++) {
      tLevel += h;

      _integrate(h);
      _collideWorld();

      final objs = objectsFor(level, tLevel);
      final its = itemsFor(level);
      final ports = portalsFor(level);

      // ------------------------------------------------------------
      // Apply FIELDS: Gravity Well + Wind Corridor
      // ------------------------------------------------------------
      for (final o in objs) {
        if (o.kind == ObjKind.gravityWell && o.shape == ObjShape.circle) {
          final k = o.src.strength ?? 3200.0;

          final dx = o.x - ball.x;
          final dy = o.y - ball.y;
          final d2 = dx * dx + dy * dy;
          final d = sqrt(max(1e-6, d2));

          // smooth falloff: strong near center, gentle far away
          final scale = o.r * 7.0;
          final falloff = 1.0 / (1.0 + (d / max(1e-6, scale)) * (d / max(1e-6, scale)));

          ball.vx += (dx / d) * k * falloff * h;
          ball.vy += (dy / d) * k * falloff * h;
        }

        if (o.kind == ObjKind.windCorridor && o.shape == ObjShape.rect) {
          final rect = o.rect!;
          if (_pointInRect(ball.x, ball.y, rect)) {
            final k = o.src.strength ?? 1200.0;
            // simple: wind pushes right; you can make direction randomized later
            ball.vx += k * h;
          }
        }
      }

      // ------------------------------------------------------------
      // Coins
      // ------------------------------------------------------------
      for (final it in its) {
        if (it.gone) continue;
        final hit = circleCircleOverlap(ball.x, ball.y, ball.r, it.x, it.y, it.r);
        if (hit != null) {
          it.src.gone = true;
          coins++;
          _pop(it.x, it.y, 12, const Color(0xF2FFE678), 680);
          _shake(1.5);
        }
      }

      // ------------------------------------------------------------
      // Portals
      // ------------------------------------------------------------
      if (ball.portalLock <= 0 && ports.isNotEmpty) {
        for (final p in ports) {
          final ha = circleCircleOverlap(ball.x, ball.y, ball.r, p.ax, p.ay, p.r);
          final hb = circleCircleOverlap(ball.x, ball.y, ball.r, p.bx, p.by, p.r);
          if (ha != null || hb != null) {
            _pop(ball.x, ball.y, 18, const Color(0xF2A08CFF), 820);
            _shake(3.0);
            if (ha != null) {
              ball.x = p.bx;
              ball.y = p.by;
            } else {
              ball.x = p.ax;
              ball.y = p.ay;
            }
            ball.vy *= 0.92;
            ball.portalLock = 0.35;
            break;
          }
        }
      }

      // ------------------------------------------------------------
      // Objects (collisions + hazards)
      // ------------------------------------------------------------
      for (final o in objs) {
        if (o.shape == ObjShape.rect) {
          final rect = o.rect!;

          // Phase blocker: only collides when active
          if (o.kind == ObjKind.phaseBlocker) {
            if (!_phaseActive(o.src, tLevel)) {
              continue; // intangible
            }
            // treat as a safe bounce (like green)
            _resolveCircleAabb(rect, world.safeRestitution, const Color(0xF2FFD278));
            continue;
          }

          // Wind corridor is a field; no collision response
          if (o.kind == ObjKind.windCorridor) {
            continue;
          }

          final hit = circleRectOverlap(ball.x, ball.y, ball.r, rect.left, rect.top, rect.width, rect.height);
          if (hit == null) continue;

          switch (o.kind) {
            case ObjKind.green:
              _resolveCircleAabb(rect, world.safeRestitution, const Color(0xF2FFD278));
              break;
            case ObjKind.sticky:
              _resolveCircleAabb(rect, world.stickyRestitution, const Color(0xF2BEC8DC));
              ball.vx *= 0.86;
              ball.vy *= 0.86;
              break;
            case ObjKind.red:
            case ObjKind.laser:
              _pop(hit.px, hit.py, 26, const Color(0xF2FF5A6E), 980);
              _shake(9);
              _crash(o.kind == ObjKind.laser ? 'Laser hit.' : 'You touched a hazard.');
              return;

          // NEW kinds that aren't rect-colliders:
            case ObjKind.gravityWell:
            case ObjKind.laserSentinel:
            case ObjKind.patrolDrone:
            case ObjKind.phaseBlocker:
            case ObjKind.windCorridor:
            case ObjKind.bumper:
              break;
          }
        } else {
          // circle objects
          if (o.kind == ObjKind.bumper) {
            final hit = circleCircleOverlap(ball.x, ball.y, ball.r, o.x, o.y, o.r);
            if (hit == null) continue;

            _resolveCircleCircle(o.x, o.y, o.r, world.bumperRestitution, const Color(0xF2FFEB8C));
            final dir = ball.vx >= 0 ? 1.0 : -1.0;
            ball.vx = dir * min(world.maxSpeed, ball.vx.abs() + 90);
            continue;
          }

          // Patrol drone: hazard on touch
          if (o.kind == ObjKind.patrolDrone) {
            final hit = circleCircleOverlap(ball.x, ball.y, ball.r, o.x, o.y, o.r);
            if (hit != null) {
              _pop(ball.x, ball.y, 26, const Color(0xF2FF5A6E), 980);
              _shake(9);
              _crash('Patrol drone hit.');
              return;
            }
            continue;
          }

          // Gravity well: handled as a field (no direct collision)
          if (o.kind == ObjKind.gravityWell) {
            continue;
          }

          // Laser sentinel: beam hit test
          if (o.kind == ObjKind.laserSentinel) {
            final minSide = min(viewport.width, viewport.height);
            final len = (o.src.beamLen ?? 0.45) * minSide;
            final w = (o.src.beamWidth ?? 0.018) * minSide;
            final ang = tLevel * (o.src.angleSpeed ?? 1.0);

            final ax = o.x;
            final ay = o.y;
            final bx = ax + cos(ang) * len;
            final by = ay + sin(ang) * len;

            final d = distPointToSegment(ball.x, ball.y, ax, ay, bx, by);
            if (d <= (ball.r + w * 0.5)) {
              _pop(ball.x, ball.y, 26, const Color(0xF2FF5A6E), 980);
              _shake(9);
              _crash('Laser sentinel hit.');
              return;
            }

            // Optional: also treat the turret body as a hazard on touch
            final bodyHit = circleCircleOverlap(ball.x, ball.y, ball.r, o.x, o.y, o.r);
            if (bodyHit != null) {
              _pop(ball.x, ball.y, 26, const Color(0xF2FF5A6E), 980);
              _shake(9);
              _crash('Laser sentinel hit.');
              return;
            }
            continue;
          }

          // Anything else circle that isn't bumper -> hazard
          final hit = circleCircleOverlap(ball.x, ball.y, ball.r, o.x, o.y, o.r);
          if (hit != null) {
            _pop(ball.x, ball.y, 26, const Color(0xF2FF5A6E), 980);
            _shake(9);
            _crash('Hazard hit.');
            return;
          }
        }
      }

      if (_reachedHole(level)) {
        _win();
        return;
      }

      _updateParticles(h);
    }
  }

  // ---------- FX + end states ----------
  void _pop(double x, double y, int count, Color color, double speed) {
    final rnd = Random();
    for (var i = 0; i < count; i++) {
      final a = rnd.nextDouble() * pi * 2;
      final s = (0.35 + rnd.nextDouble() * 0.75) * speed;
      fx.particles.add(Particle(
        x: x,
        y: y,
        vx: cos(a) * s,
        vy: sin(a) * s,
        life: 0,
        ttl: 0.32 + rnd.nextDouble() * 0.40,
        size: 2 + rnd.nextDouble() * 4,
        color: color,
      ));
    }
  }

  void _shake(double mag) {
    fx.shakeMag = max(fx.shakeMag, mag);
    fx.shakeT = max(fx.shakeT, 0.14);
  }

  void _updateParticles(double dt) {
    for (var i = fx.particles.length - 1; i >= 0; i--) {
      final p = fx.particles[i];
      p.life += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= pow(0.98, dt * 60).toDouble();
      p.vy *= pow(0.98, dt * 60).toDouble();
      if (p.life >= p.ttl) fx.particles.removeAt(i);
    }

    if (fx.shakeT > 0) {
      fx.shakeT = max(0, fx.shakeT - dt);
      if (fx.shakeT <= 0) fx.shakeMag = 0;
    }
  }

  void _crash(String reason) {
    _pop(ball.x, ball.y, 34, const Color(0xF2FF5A6E), 980);
    _shake(10);
    messageOverlay = OverlayMessage(
      title: 'Boom.',
      body: reason.isEmpty ? 'You hit a hazard.' : reason,
      hint: 'Tip: time flips and use bounces to route through the middle.',
      showNext: false,
    );
    paused = true;
  }

  Future<void> _win() async {
    _pop(ball.x, ball.y, 28, const Color(0xF278FFB4), 820);
    _shake(6);

    final lvlKey = '$levelNo';
    final prev = bestByLevel[lvlKey];
    if (prev == null || flips < prev) {
      bestByLevel[lvlKey] = flips;
      await BestStorage.save(bestByLevel);
    }

    final isLast = levelIndex >= LevelGen.maxLevels - 1;
    messageOverlay = OverlayMessage(
      title: isLast ? 'All levels cleared.' : 'Win.',
      body: 'Reached the hole in $flips flip${flips == 1 ? '' : 's'} with $coins ★ collected.',
      hint: (bestByLevel[lvlKey] == flips) ? 'New best.' : 'Replay to reduce flips.',
      showNext: !isLast,
    );
    paused = true;
  }
}