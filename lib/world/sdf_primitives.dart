import 'dart:math';

/// Signed Distance Field primitives and boolean operations.
///
/// Convention: negative = inside solid, positive = outside (air), zero = surface.
class SdfPrimitives {
  SdfPrimitives._();

  // -- Primitives --

  /// Circle/sphere SDF: distance from point (px,py) to circle at (cx,cy) with radius r.
  static double circle(double px, double py, double cx, double cy, double r) {
    final dx = px - cx;
    final dy = py - cy;
    return sqrt(dx * dx + dy * dy) - r;
  }

  /// Axis-aligned box SDF: distance from point (px,py) to box centered at (cx,cy)
  /// with half-widths (hw,hh).
  static double box(
    double px, double py,
    double cx, double cy,
    double hw, double hh,
  ) {
    final dx = (px - cx).abs() - hw;
    final dy = (py - cy).abs() - hh;
    final outside = sqrt(max(dx, 0) * max(dx, 0) + max(dy, 0) * max(dy, 0));
    final inside = min(max(dx, dy), 0.0);
    return outside + inside;
  }

  /// Capsule SDF: distance from point (px,py) to a line segment from (ax,ay)
  /// to (bx,by) with radius r. Useful for tunnels and veins.
  static double capsule(
    double px, double py,
    double ax, double ay,
    double bx, double by,
    double r,
  ) {
    final pax = px - ax, pay = py - ay;
    final bax = bx - ax, bay = by - ay;
    final dot = bax * bax + bay * bay;
    final h = dot > 0 ? ((pax * bax + pay * bay) / dot).clamp(0.0, 1.0) : 0.0;
    final dx = pax - bax * h, dy = pay - bay * h;
    return sqrt(dx * dx + dy * dy) - r;
  }

  /// Line segment SDF (zero-radius capsule): distance from point (px,py)
  /// to the nearest point on line segment from (ax,ay) to (bx,by).
  static double line(
    double px, double py,
    double ax, double ay,
    double bx, double by,
  ) {
    final pax = px - ax, pay = py - ay;
    final bax = bx - ax, bay = by - ay;
    final dot = bax * bax + bay * bay;
    final h = dot > 0 ? ((pax * bax + pay * bay) / dot).clamp(0.0, 1.0) : 0.0;
    final dx = pax - bax * h, dy = pay - bay * h;
    return sqrt(dx * dx + dy * dy);
  }

  // -- Boolean operations --

  /// Union: combine two shapes (nearest surface wins).
  static double union(double d1, double d2) => min(d1, d2);

  /// Subtraction: carve shape2 out of shape1.
  /// Result is inside shape1 AND outside shape2.
  static double subtract(double d1, double d2) => max(d1, -d2);

  /// Intersection: keep only the overlap of two shapes.
  static double intersect(double d1, double d2) => max(d1, d2);

  /// Smooth union: blend two shapes with smoothing factor k.
  /// Larger k = smoother blend.
  static double smoothUnion(double d1, double d2, double k) {
    if (k <= 0) return min(d1, d2);
    final h = (0.5 + 0.5 * (d2 - d1) / k).clamp(0.0, 1.0);
    return d2 * (1.0 - h) + d1 * h - k * h * (1.0 - h);
  }

  /// Smooth subtraction: smoothly carve shape2 from shape1.
  /// Larger k = smoother carve edges.
  static double smoothSubtract(double d1, double d2, double k) {
    if (k <= 0) return max(d1, -d2);
    final h = (0.5 - 0.5 * (d2 + d1) / k).clamp(0.0, 1.0);
    return d2 * (1.0 - h) + (-d1) * h + k * h * (1.0 - h);
  }

  /// Smooth intersection: smoothly intersect two shapes.
  static double smoothIntersect(double d1, double d2, double k) {
    if (k <= 0) return max(d1, d2);
    final h = (0.5 - 0.5 * (d2 - d1) / k).clamp(0.0, 1.0);
    return d2 * (1.0 - h) + d1 * h + k * h * (1.0 - h);
  }

  // -- Utility --

  /// Convert old density (0.0=empty, 1.0=solid) to SDF value.
  /// Uses threshold 0.5: density > 0.5 becomes negative (solid).
  static double densityToSdf(double density, {double threshold = 0.5}) {
    return threshold - density;
  }

  /// Convert SDF back to approximate density (0.0=empty, 1.0=solid).
  /// Clamps to [0.0, 1.0] range for backward compatibility.
  static double sdfToDensity(double sdf) {
    return (0.5 - sdf).clamp(0.0, 1.0);
  }

  // -- Drill operation --

  /// Apply a smooth spherical drill subtraction to a region of an SDF grid.
  ///
  /// Carves a circle of [radius] centered at ([drillX], [drillY]) from the
  /// grid. Uses smooth subtraction with factor [smoothK] for natural-looking
  /// rounded drill holes instead of blocky single-cell removal.
  ///
  /// [grid] is a 2D array of SDF values.
  /// [gridOriginX], [gridOriginY] are the world coordinates of grid[0][0].
  /// [onCellModified] is called for each cell whose SDF changed, so the
  /// caller can mark chunks dirty, update CellType, etc.
  ///
  /// Returns the number of cells modified.
  static int drillSdf({
    required List<List<double>> grid,
    required double drillX,
    required double drillY,
    required double radius,
    required int gridOriginX,
    required int gridOriginY,
    double smoothK = 0.3,
    void Function(int gridX, int gridY, double oldSdf, double newSdf)?
        onCellModified,
  }) {
    final height = grid.length;
    if (height == 0) return 0;
    final width = grid[0].length;

    // Only iterate cells within the drill's influence area
    final margin = (radius + smoothK + 1).ceil();
    final localCenterX = drillX - gridOriginX;
    final localCenterY = drillY - gridOriginY;

    final minY = (localCenterY - margin).floor().clamp(0, height - 1);
    final maxY = (localCenterY + margin).ceil().clamp(0, height - 1);
    final minX = (localCenterX - margin).floor().clamp(0, width - 1);
    final maxX = (localCenterX + margin).ceil().clamp(0, width - 1);

    int modified = 0;

    for (int gy = minY; gy <= maxY; gy++) {
      for (int gx = minX; gx <= maxX; gx++) {
        final worldCellX = gridOriginX + gx;
        final worldCellY = gridOriginY + gy;

        // SDF of the drill sphere at this cell
        final drillDist = circle(
          worldCellX.toDouble(),
          worldCellY.toDouble(),
          drillX,
          drillY,
          radius,
        );

        // Smooth subtraction: carve drill hole from terrain
        final oldSdf = grid[gy][gx];
        final newSdf = smoothSubtract(oldSdf, drillDist, smoothK);

        if (newSdf != oldSdf) {
          grid[gy][gx] = newSdf;
          modified++;
          onCellModified?.call(gx, gy, oldSdf, newSdf);
        }
      }
    }

    return modified;
  }
}
