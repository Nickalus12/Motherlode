import 'dart:math';

import 'package:flame/components.dart';

/// Math utility functions for Motherlode
class MathUtils {
  MathUtils._();

  static final Random _random = Random();

  /// Random double between [min] and [max]
  static double randomRange(double min, double max) {
    return min + _random.nextDouble() * (max - min);
  }

  /// Random int between [min] and [max] (inclusive)
  static int randomRangeInt(int min, int max) {
    return min + _random.nextInt(max - min + 1);
  }

  /// Distance between two points
  static double distance(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return sqrt(dx * dx + dy * dy);
  }

  /// Distance squared (faster, no sqrt)
  static double distanceSquared(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return dx * dx + dy * dy;
  }

  /// Lerp between two values
  static double lerp(double a, double b, double t) {
    return a + (b - a) * t.clamp(0.0, 1.0);
  }

  /// Inverse lerp - returns t given a value between a and b
  static double inverseLerp(double a, double b, double value) {
    if ((b - a).abs() < 0.0001) return 0.0;
    return ((value - a) / (b - a)).clamp(0.0, 1.0);
  }

  /// Remap value from one range to another
  static double remap(
    double value,
    double fromMin,
    double fromMax,
    double toMin,
    double toMax,
  ) {
    final t = inverseLerp(fromMin, fromMax, value);
    return lerp(toMin, toMax, t);
  }

  /// Normalize an angle to [0, 2*pi)
  static double normalizeAngle(double angle) {
    angle = angle % (2 * pi);
    if (angle < 0) angle += 2 * pi;
    return angle;
  }

  /// Random direction vector with given magnitude
  static Vector2 randomDirection([double magnitude = 1.0]) {
    final angle = _random.nextDouble() * 2 * pi;
    return Vector2(cos(angle) * magnitude, sin(angle) * magnitude);
  }

  /// Random direction within a cone (angle in radians, centered on baseAngle)
  static Vector2 randomConeDirection(
    double baseAngle,
    double coneHalfAngle, [
    double magnitude = 1.0,
  ]) {
    final angle = baseAngle + randomRange(-coneHalfAngle, coneHalfAngle);
    return Vector2(cos(angle) * magnitude, sin(angle) * magnitude);
  }

  /// Smoothstep interpolation
  static double smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  /// Check if a point is within a rectangle
  static bool pointInRect(
    double px,
    double py,
    double rx,
    double ry,
    double rw,
    double rh,
  ) {
    return px >= rx && px <= rx + rw && py >= ry && py <= ry + rh;
  }

  /// Sign function
  static int sign(double value) {
    if (value > 0) return 1;
    if (value < 0) return -1;
    return 0;
  }

  /// Approach a target value by a step amount
  static double approach(double current, double target, double step) {
    if (current < target) {
      return min(current + step, target);
    } else {
      return max(current - step, target);
    }
  }
}
