import 'dart:ui';

enum ObjShape { rect, circle }

enum ObjKind {
  green,
  red,
  sticky,
  laser,
  bumper,

  // NEW
  gravityWell,
  laserSentinel,
  patrolDrone,
  phaseBlocker,
  windCorridor,
}

class Motion {
  final String axis; // "x" or "y"
  final double amp; // normalized amplitude relative to W or H
  final double freq; // Hz-ish (used inside sin with 2π)
  final double phase;

  const Motion({
    required this.axis,
    required this.amp,
    required this.freq,
    required this.phase,
  });
}

class LevelObjNorm {
  final ObjShape shape;
  final ObjKind kind;

  final double x, y;
  final double w, h;
  final double r;

  final Motion? motion;

  // Optional params:
  final double? strength; // gravityWell / windCorridor
  final double? angleSpeed; // laserSentinel (rad/sec)
  final double? beamLen; // laserSentinel (normalized 0..1)
  final double? beamWidth; // laserSentinel (normalized thickness)
  final double? phasePeriod; // phaseBlocker seconds
  final double? phaseDuty; // 0..1 visible fraction
  final double? phaseOffset; // seconds

  const LevelObjNorm({
    required this.shape,
    required this.kind,
    required this.x,
    required this.y,
    this.w = 0,
    this.h = 0,
    this.r = 0,
    this.motion,
    this.strength,
    this.angleSpeed,
    this.beamLen,
    this.beamWidth,
    this.phasePeriod,
    this.phaseDuty,
    this.phaseOffset,
  });

  // ✅ Required by your LevelGen calls
  const LevelObjNorm.rect({
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.motion,
    this.strength,
    this.phasePeriod,
    this.phaseDuty,
    this.phaseOffset,
  })  : shape = ObjShape.rect,
        r = 0,
        angleSpeed = null,
        beamLen = null,
        beamWidth = null;

  // ✅ Required by your LevelGen calls
  const LevelObjNorm.circle({
    required this.kind,
    required this.x,
    required this.y,
    required this.r,
    this.motion,
    this.strength,
    this.angleSpeed,
    this.beamLen,
    this.beamWidth,
  })  : shape = ObjShape.circle,
        w = 0,
        h = 0,
        phasePeriod = null,
        phaseDuty = null,
        phaseOffset = null;
}

class ItemNorm {
  final int id;
  final double x, y;
  final double r;
  bool gone;

  ItemNorm({
    required this.id,
    required this.x,
    required this.y,
    required this.r,
    this.gone = false,
  });
}

class PortalPairNorm {
  final Offset a;
  final Offset b;
  final double r;

  const PortalPairNorm({
    required this.a,
    required this.b,
    required this.r,
  });
}

class GoalBandNorm {
  final double y;
  final double h;

  const GoalBandNorm({
    required this.y,
    required this.h,
  });
}

class HoleNorm {
  final double x;
  final double y;

  const HoleNorm({
    required this.x,
    required this.y,
  });
}

class Level {
  final int no;
  final GoalBandNorm goalBand;
  final HoleNorm hole;
  final List<LevelObjNorm> objects;
  final List<ItemNorm> items;
  final List<PortalPairNorm> portals;

  const Level({
    required this.no,
    required this.goalBand,
    required this.hole,
    required this.objects,
    required this.items,
    required this.portals,
  });
}

class Ball {
  double r;
  double x, y;
  double vx, vy;
  int gSign; // +1 or -1
  double flipLock;
  double blinkSeed;
  double portalLock;

  Ball({
    required this.r,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.gSign,
    required this.flipLock,
    required this.blinkSeed,
    required this.portalLock,
  });
}

class Particle {
  double x, y;
  double vx, vy;
  double life;
  double ttl;
  double size;
  Color color;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.ttl,
    required this.size,
    required this.color,
  });
}

class FxState {
  final List<Particle> particles = [];
  double shakeT = 0;
  double shakeMag = 0;
}

class OverlayMessage {
  final String title;
  final String body;
  final String hint;
  final bool showNext;

  const OverlayMessage({
    required this.title,
    required this.body,
    required this.hint,
    required this.showNext,
  });
}