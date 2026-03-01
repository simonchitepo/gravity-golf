import 'dart:math';
import 'dart:ui';

import 'models.dart';
import 'math_util.dart';

class LevelGen {
  static const int maxLevels = 100;

  static Level makeLevel(int levelNo) {
    final rng = Mulberry32(hashSeed(levelNo));
    final difficulty = clampd((levelNo - 1) / 99.0, 0, 1);

    final holeX = clampd(0.72 + (rng.next() - 0.5) * 0.32, 0.22, 0.90);
    final holeY = clampd(0.90 + (rng.next() - 0.5) * 0.05, 0.84, 0.94);
    final goalBand = const GoalBandNorm(y: 0.89, h: 0.10);

    final objects = <LevelObjNorm>[];
    final items = <ItemNorm>[];
    final portals = <PortalPairNorm>[];

    // ---------------------------
    // Helpers
    // ---------------------------
    Motion? motionMaybe() {
      if (rng.next() < (0.22 + difficulty * 0.24)) {
        return Motion(
          axis: (rng.next() < 0.5) ? "x" : "y",
          amp: clampd(0.04 + rng.next() * 0.12 * difficulty, 0.04, 0.16),
          freq: clampd(0.70 + rng.next() * 0.95 + difficulty * 0.35, 0.70, 2.10),
          phase: rng.next() * 3.0,
        );
      }
      return null;
    }

    void pushRect(
        ObjKind kind,
        double x,
        double y,
        double w,
        double h,
        Motion? motion, {
          // NEW optional params:
          double? strength,
          double? phasePeriod,
          double? phaseDuty,
          double? phaseOffset,
        }) {
      objects.add(LevelObjNorm.rect(
        kind: kind,
        x: x,
        y: y,
        w: w,
        h: h,
        motion: motion,
        strength: strength,
        phasePeriod: phasePeriod,
        phaseDuty: phaseDuty,
        phaseOffset: phaseOffset,
      ));
    }

    void pushCircle(
        ObjKind kind,
        double x,
        double y,
        double r,
        Motion? motion, {
          // NEW optional params:
          double? strength,
          double? angleSpeed,
          double? beamLen,
          double? beamWidth,
        }) {
      objects.add(LevelObjNorm.circle(
        kind: kind,
        x: x,
        y: y,
        r: r,
        motion: motion,
        strength: strength,
        angleSpeed: angleSpeed,
        beamLen: beamLen,
        beamWidth: beamWidth,
      ));
    }

    void addRandomRect(ObjKind kind) {
      final w = clampd(0.10 + rng.next() * 0.11, 0.10, 0.20);
      final h = clampd(0.06 + rng.next() * 0.06, 0.06, 0.12);
      var x = clampd(0.08 + rng.next() * 0.84, 0.02, 0.88);
      var y = clampd(0.14 + rng.next() * 0.66, 0.12, 0.82);
      y = clampd(y - difficulty * 0.06, 0.12, 0.84);
      if (levelNo > 1) x = clampd(x, 0.18, 0.82 - w);
      pushRect(kind, x, y, w, h, motionMaybe());
    }

    void addStickyPlatform() {
      final w = clampd(0.12 + rng.next() * 0.10, 0.12, 0.22);
      final h = clampd(0.06 + rng.next() * 0.06, 0.06, 0.12);
      var x = randIn(rng, 0.10, 0.90 - w);
      var y = randIn(rng, 0.18, 0.82 - h);
      if (levelNo > 1) x = clampd(x, 0.18, 0.82 - w);
      pushRect(ObjKind.sticky, x, y, w, h, (rng.next() < 0.25) ? motionMaybe() : null);
    }

    void addBumper() {
      final r = clampd(0.030 + rng.next() * 0.030, 0.030, 0.060);
      var x = randIn(rng, 0.10, 0.90);
      var y = randIn(rng, 0.18, 0.78);
      if (levelNo > 1) x = clampd(x, 0.22, 0.78);
      pushCircle(ObjKind.bumper, x, y, r, (rng.next() < 0.45) ? motionMaybe() : null);
    }

    void addPortalPair() {
      final a = Offset(randIn(rng, 0.22, 0.78), randIn(rng, 0.20, 0.72));
      final b = Offset(randIn(rng, 0.22, 0.78), randIn(rng, 0.20, 0.72));
      portals.add(PortalPairNorm(a: a, b: b, r: 0.040));
    }

    // ---------------------------
    // NEW Enemies / Mechanics
    // ---------------------------

    void addGravityWell() {
      final r = clampd(0.035 + rng.next() * 0.035, 0.035, 0.070);
      final x = randIn(rng, 0.22, 0.78);
      final y = randIn(rng, 0.20, 0.72);
      final strength = 2200.0 + 2600.0 * difficulty;

      pushCircle(
        ObjKind.gravityWell,
        x,
        y,
        r,
        (rng.next() < 0.40) ? motionMaybe() : null,
        strength: strength,
      );
    }

    void addLaserSentinel() {
      final r = clampd(0.028 + rng.next() * 0.020, 0.028, 0.050);
      final x = randIn(rng, 0.22, 0.78);
      final y = randIn(rng, 0.20, 0.72);

      final angleSpeed =
          (0.6 + rng.next() * 1.2) * (difficulty > 0.5 ? 1.2 : 1.0); // rad/sec
      final beamLen = clampd(0.22 + rng.next() * 0.40, 0.22, 0.60); // normalized vs min(W,H)
      const beamWidth = 0.018; // normalized thickness

      pushCircle(
        ObjKind.laserSentinel,
        x,
        y,
        r,
        (rng.next() < 0.25) ? motionMaybe() : null,
        angleSpeed: angleSpeed,
        beamLen: beamLen,
        beamWidth: beamWidth,
      );
    }

    void addPatrolDrone() {
      final r = clampd(0.030 + rng.next() * 0.030, 0.030, 0.060);
      final x = randIn(rng, 0.22, 0.78);
      final y = randIn(rng, 0.20, 0.72);

      // sinusoidal patrol motion
      final m = Motion(
        axis: (rng.next() < 0.5) ? "x" : "y",
        amp: clampd(0.06 + rng.next() * 0.12, 0.06, 0.18),
        freq: clampd(0.60 + rng.next() * 1.10, 0.60, 2.00) + difficulty * 0.35,
        phase: rng.next() * 3.0,
      );

      pushCircle(ObjKind.patrolDrone, x, y, r, m);
    }

    void addPhaseBlocker() {
      final w = clampd(0.12 + rng.next() * 0.12, 0.12, 0.22);
      final h = clampd(0.06 + rng.next() * 0.08, 0.06, 0.14);
      var x = randIn(rng, 0.22, 0.78 - w);
      var y = randIn(rng, 0.18, 0.78 - h);

      if (levelNo > 1) x = clampd(x, 0.18, 0.82 - w);

      final period = clampd(1.2 + rng.next() * 1.6, 1.2, 2.8);
      final duty = clampd(0.45 + rng.next() * 0.25, 0.45, 0.70);
      final offset = rng.next() * period;

      pushRect(
        ObjKind.phaseBlocker,
        x,
        y,
        w,
        h,
        (rng.next() < 0.25) ? motionMaybe() : null,
        phasePeriod: period,
        phaseDuty: duty,
        phaseOffset: offset,
      );
    }

    void addWindCorridor() {
      final w = clampd(0.18 + rng.next() * 0.22, 0.18, 0.40);
      final h = clampd(0.07 + rng.next() * 0.16, 0.07, 0.25);
      var x = randIn(rng, 0.18, 0.82 - w);
      var y = randIn(rng, 0.18, 0.80 - h);

      if (levelNo > 1) x = clampd(x, 0.18, 0.82 - w);

      final strength = 900.0 + 1100.0 * difficulty; // px/s^2

      pushRect(
        ObjKind.windCorridor,
        x,
        y,
        w,
        h,
        (rng.next() < 0.30) ? motionMaybe() : null,
        strength: strength,
      );
    }

    // ---------------------------
    // Base walls (same as before)
    // ---------------------------
    if (levelNo > 1) {
      pushRect(ObjKind.green, 0.00, 0.16, 0.16, 0.66, null);
      pushRect(ObjKind.green, 0.84, 0.16, 0.16, 0.66, null);
    }

    // ---------------------------
    // Existing object counts (same as before)
    // ---------------------------
    final safeCount = (3 + difficulty * 6 + rng.next() * 2).floor();
    final redCount = (2 + difficulty * 9 + rng.next() * 3).floor();
    final laserCount =
    ((difficulty > 0.18 ? 1 : 0) + difficulty * 2 + (rng.next() < 0.35 ? 1 : 0)).floor();
    final bumperCount = (1 + difficulty * 3 + (rng.next() < 0.55 ? 1 : 0)).floor();
    final stickyCount = ((difficulty > 0.25 ? 1 : 0) + (rng.next() < 0.55 ? 1 : 0)).floor();
    final portalPairsBase = (difficulty > 0.35 && rng.next() < 0.55) ? 1 : 0;

    for (var i = 0; i < safeCount; i++) addRandomRect(ObjKind.green);
    for (var i = 0; i < redCount; i++) addRandomRect(ObjKind.red);

    // lasers (spike bars)
    for (var i = 0; i < laserCount; i++) {
      final thin = clampd(0.018 + rng.next() * 0.016, 0.018, 0.034);
      final long = clampd(0.18 + rng.next() * 0.28, 0.18, 0.46);
      final horizontal = rng.next() < 0.55;
      final w = horizontal ? long : thin;
      final h = horizontal ? thin : long;
      var x = randIn(rng, 0.10, 0.90 - w);
      var y = randIn(rng, 0.16, 0.82 - h);
      if (levelNo > 1) x = clampd(x, 0.18, 0.82 - w);
      final m = Motion(
        axis: (rng.next() < 0.6) ? "x" : "y",
        amp: clampd(0.06 + rng.next() * 0.10, 0.06, 0.16),
        freq: clampd(0.90 + rng.next() * 1.20, 0.90, 2.40),
        phase: rng.next() * 3.0,
      );
      pushRect(ObjKind.laser, x, y, w, h, m);
    }

    // sticky platforms
    for (var i = 0; i < stickyCount; i++) {
      addStickyPlatform();
    }

    // bumpers
    for (var i = 0; i < bumperCount; i++) {
      addBumper();
    }

    // base portals
    for (var p = 0; p < portalPairsBase; p++) {
      addPortalPair();
    }

    // ---------------------------
    // NEW Combo logic
    // ---------------------------
    final bool combosEnabled = difficulty > 0.30;

    // Gravity Well + Laser Sentinel
    if (combosEnabled && rng.next() < 0.55) {
      addGravityWell();
      addLaserSentinel();
    }

    // Patrol Drone + Sticky platform (ensure at least 1 sticky)
    if (combosEnabled && rng.next() < 0.65) {
      addPatrolDrone();
      addStickyPlatform();
    }

    // Phase Blocker + Portal (ensure at least 1 portal pair)
    if (combosEnabled && rng.next() < 0.60) {
      addPhaseBlocker();
      if (portals.isEmpty) addPortalPair();
    }

    // Wind Corridor + Bumper (ensure at least 1 bumper)
    if (combosEnabled && rng.next() < 0.70) {
      addWindCorridor();
      final hasBumper = objects.any((o) => o.kind == ObjKind.bumper);
      if (!hasBumper) addBumper();
    }

    // ---------------------------
    // Items (coins) same as before
    // ---------------------------
    final itemCount = (2 + difficulty * 5 + rng.next() * 3).floor();

    bool itemTooClose(double ix, double iy) {
      for (final o in objects) {
        if (o.shape == ObjShape.rect) {
          final rx = o.x, ry = o.y, rw = o.w, rh = o.h;
          final cx = clampd(ix, rx, rx + rw);
          final cy = clampd(iy, ry, ry + rh);
          final d2 = (ix - cx) * (ix - cx) + (iy - cy) * (iy - cy);
          if (d2 < 0.010 * 0.010) return true;
        } else {
          final dx = ix - o.x;
          final dy = iy - o.y;
          if (dx * dx + dy * dy < (o.r + 0.040) * (o.r + 0.040)) return true;
        }
      }
      for (final it in items) {
        final dx = ix - it.x;
        final dy = iy - it.y;
        if (dx * dx + dy * dy < 0.055 * 0.055) return true;
      }
      return false;
    }

    var nextId = 1;

    void addCoin() {
      for (var tries = 0; tries < 40; tries++) {
        var x = randIn(rng, 0.10, 0.90);
        var y = randIn(rng, 0.16, 0.82);
        if (levelNo > 1) x = clampd(x, 0.22, 0.78);
        if ((x - holeX).abs() < 0.10 && y > 0.78) continue;
        if (itemTooClose(x, y)) continue;
        items.add(ItemNorm(id: nextId++, x: x, y: y, r: 0.020));
        return;
      }
    }

    for (var i = 0; i < itemCount; i++) addCoin();

    return Level(
      no: levelNo,
      goalBand: goalBand,
      hole: HoleNorm(x: holeX, y: holeY),
      objects: objects,
      items: items,
      portals: portals,
    );
  }
}