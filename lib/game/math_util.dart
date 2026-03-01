import 'dart:math';
import 'dart:ui';

double clampd(double v, double a, double b) => v < a ? a : (v > b ? b : v);

class Mulberry32 {
  int _t;
  Mulberry32(int seed) : _t = seed & 0xFFFFFFFF;

  double next() {
    _t = (_t + 0x6D2B79F5) & 0xFFFFFFFF;
    int x = _imul(_t ^ (_t >>> 15), 1 | _t);
    x ^= (x + _imul(x ^ (x >>> 7), 61 | x)) & 0xFFFFFFFF;
    final int out = (x ^ (x >>> 14)) & 0xFFFFFFFF;
    return out / 4294967296.0;
  }

  static int _imul(int a, int b) {
    return (a * b) & 0xFFFFFFFF;
  }
}

int hashSeed(int n) {
  int x = (n * 2654435761) & 0xFFFFFFFF;
  x ^= (x >>> 16);
  x = (Mulberry32._imul(x, 2246822507)) & 0xFFFFFFFF;
  x ^= (x >>> 13);
  x = (Mulberry32._imul(x, 3266489909)) & 0xFFFFFFFF;
  x ^= (x >>> 16);
  return x & 0xFFFFFFFF;
}

double randIn(Mulberry32 rng, double a, double b) => a + (b - a) * rng.next();

T pick<T>(Mulberry32 rng, List<T> arr) => arr[(rng.next() * arr.length).floor()];

class CircleRectHit {
  final double nx, ny;
  final double pen;
  final double px, py;
  const CircleRectHit({
    required this.nx,
    required this.ny,
    required this.pen,
    required this.px,
    required this.py,
  });
}

CircleRectHit? circleRectOverlap(
    double cx,
    double cy,
    double cr,
    double rx,
    double ry,
    double rw,
    double rh,
    ) {
  final px = clampd(cx, rx, rx + rw);
  final py = clampd(cy, ry, ry + rh);
  final dx = cx - px;
  final dy = cy - py;
  final d2 = dx * dx + dy * dy;
  if (d2 > cr * cr) return null;
  final d = sqrt(max(1e-6, d2));
  return CircleRectHit(nx: dx / d, ny: dy / d, pen: cr - d, px: px, py: py);
}

class CircleCircleHit {
  final double nx, ny;
  final double pen;
  const CircleCircleHit({
    required this.nx,
    required this.ny,
    required this.pen,
  });
}

CircleCircleHit? circleCircleOverlap(
    double ax,
    double ay,
    double ar,
    double bx,
    double by,
    double br,
    ) {
  final dx = ax - bx;
  final dy = ay - by;
  final d2 = dx * dx + dy * dy;
  final r = ar + br;
  if (d2 > r * r) return null;
  final d = sqrt(max(1e-6, d2));
  return CircleCircleHit(nx: dx / d, ny: dy / d, pen: r - d);
}

/// Distance from point P(px,py) to segment AB(ax,ay)->(bx,by).
/// Used for laser-beam hit testing.
double distPointToSegment(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
    ) {
  final abx = bx - ax;
  final aby = by - ay;
  final apx = px - ax;
  final apy = py - ay;

  final ab2 = abx * abx + aby * aby;
  if (ab2 <= 1e-9) {
    final dx = px - ax;
    final dy = py - ay;
    return sqrt(dx * dx + dy * dy);
  }

  var t = (apx * abx + apy * aby) / ab2;
  t = clampd(t, 0.0, 1.0);

  final cx = ax + abx * t;
  final cy = ay + aby * t;

  final dx = px - cx;
  final dy = py - cy;
  return sqrt(dx * dx + dy * dy);
}

Path rrPath(Rect r, double radius) {
  final rr = Radius.circular(radius);
  return Path()..addRRect(RRect.fromRectAndRadius(r, rr));
}