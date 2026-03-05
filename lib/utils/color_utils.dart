import 'dart:ui';

import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/stratigraphy.dart';

/// Color utility functions for depth-graded rendering
class ColorUtils {
  ColorUtils._();

  /// Get terrain color for a given depth in feet
  static Color getTerrainColor(double depthFeet) {
    if (depthFeet <= 0) return GameConstants.surfaceTerrainColor;

    if (depthFeet <= GameConstants.topsoilEnd) {
      final t = depthFeet / GameConstants.topsoilEnd;
      return Color.lerp(
        GameConstants.surfaceTerrainColor,
        GameConstants.shallowTerrainColor,
        t,
      )!;
    }

    if (depthFeet <= GameConstants.rockEnd) {
      final t = (depthFeet - GameConstants.topsoilEnd) /
          (GameConstants.rockEnd - GameConstants.topsoilEnd);
      return Color.lerp(
        GameConstants.shallowTerrainColor,
        GameConstants.deepTerrainColor,
        t,
      )!;
    }

    if (depthFeet <= GameConstants.volcanicEnd) {
      final t = (depthFeet - GameConstants.rockEnd) /
          (GameConstants.volcanicEnd - GameConstants.rockEnd);
      return Color.lerp(
        GameConstants.deepTerrainColor,
        GameConstants.volcanicTerrainColor,
        t,
      )!;
    }

    final t = ((depthFeet - GameConstants.volcanicEnd) /
            (GameConstants.maxDepth - GameConstants.volcanicEnd))
        .clamp(0.0, 1.0);
    return Color.lerp(
      GameConstants.volcanicTerrainColor,
      GameConstants.hellTerrainColor,
      t,
    )!;
  }

  /// Get terrain color using geological stratigraphy.
  ///
  /// Returns the stratum's color with subtle noise-based variation for
  /// natural-looking geological layers. Falls back to depth-based color
  /// if [stratigraphy] is null.
  ///
  /// Near stratum boundaries, blends between adjacent layer colors for
  /// smooth visual transitions instead of hard lines.
  static Color getStratumTerrainColor(
    double worldX,
    double depthFeet,
    Stratigraphy? stratigraphy,
  ) {
    if (stratigraphy == null) return getTerrainColor(depthFeet);

    final stratum = stratigraphy.getStratumAtPosition(worldX, depthFeet);
    final base = stratum.primaryColor;

    // Check proximity to stratum boundary for blending.
    // Find the boundary depth at this worldX for the current stratum.
    final boundary = stratigraphy.getStratumBoundary(stratum, worldX);
    final distFromBoundary = depthFeet - boundary;
    const blendZone = 30.0; // feet of transition between layers

    Color layerColor;
    if (distFromBoundary < blendZone) {
      // Near top boundary — blend with the stratum above
      final stratumIdx = Stratigraphy.strata.indexOf(stratum);
      if (stratumIdx > 0) {
        final above = Stratigraphy.strata[stratumIdx - 1];
        final t = (distFromBoundary / blendZone).clamp(0.0, 1.0);
        layerColor = Color.lerp(above.primaryColor, base, t)!;
      } else {
        layerColor = base;
      }
    } else {
      layerColor = base;
    }

    // Add subtle per-cell variation using a cheap hash (no noise call
    // needed here since this runs per-polygon during rendering).
    // worldX and depthFeet combined give positional variation.
    final hash = (worldX.toInt() * 17 + depthFeet.toInt() * 31) % 200;
    final variation = (hash / 200.0 - 0.5) * 0.12; // +/- 6% brightness
    final r = (layerColor.r + variation).clamp(0.0, 1.0);
    final g = (layerColor.g + variation).clamp(0.0, 1.0);
    final b = (layerColor.b + variation).clamp(0.0, 1.0);
    return Color.from(alpha: layerColor.a, red: r, green: g, blue: b);
  }

  /// Get accent color for a given depth in feet
  static Color getAccentColor(double depthFeet) {
    if (depthFeet <= 0) return GameConstants.surfaceAccentColor;

    if (depthFeet <= GameConstants.topsoilEnd) {
      final t = depthFeet / GameConstants.topsoilEnd;
      return Color.lerp(
        GameConstants.surfaceAccentColor,
        GameConstants.shallowAccentColor,
        t,
      )!;
    }

    if (depthFeet <= GameConstants.rockEnd) {
      final t = (depthFeet - GameConstants.topsoilEnd) /
          (GameConstants.rockEnd - GameConstants.topsoilEnd);
      return Color.lerp(
        GameConstants.shallowAccentColor,
        GameConstants.deepAccentColor,
        t,
      )!;
    }

    if (depthFeet <= GameConstants.volcanicEnd) {
      final t = (depthFeet - GameConstants.rockEnd) /
          (GameConstants.volcanicEnd - GameConstants.rockEnd);
      return Color.lerp(
        GameConstants.deepAccentColor,
        GameConstants.volcanicAccentColor,
        t,
      )!;
    }

    final t = ((depthFeet - GameConstants.volcanicEnd) /
            (GameConstants.maxDepth - GameConstants.volcanicEnd))
        .clamp(0.0, 1.0);
    return Color.lerp(
      GameConstants.volcanicAccentColor,
      GameConstants.hellAccentColor,
      t,
    )!;
  }

  /// Get ambient light level (0.0 to 1.0) for a given depth
  static double getAmbientLight(double depthFeet) {
    if (depthFeet <= 0) return GameConstants.surfaceAmbientLight;

    if (depthFeet <= GameConstants.topsoilEnd) {
      final t = depthFeet / GameConstants.topsoilEnd;
      return _lerp(GameConstants.surfaceAmbientLight,
          GameConstants.shallowAmbientLight, t);
    }

    if (depthFeet <= GameConstants.rockEnd) {
      final t = (depthFeet - GameConstants.topsoilEnd) /
          (GameConstants.rockEnd - GameConstants.topsoilEnd);
      return _lerp(GameConstants.shallowAmbientLight,
          GameConstants.deepAmbientLight, t);
    }

    if (depthFeet <= GameConstants.volcanicEnd) {
      final t = (depthFeet - GameConstants.rockEnd) /
          (GameConstants.volcanicEnd - GameConstants.rockEnd);
      return _lerp(GameConstants.deepAmbientLight,
          GameConstants.volcanicAmbientLight, t);
    }

    final t = ((depthFeet - GameConstants.volcanicEnd) /
            (GameConstants.maxDepth - GameConstants.volcanicEnd))
        .clamp(0.0, 1.0);
    return _lerp(
        GameConstants.volcanicAmbientLight, GameConstants.hellAmbientLight, t);
  }

  /// Get depth fog color for overlay
  static Color getDepthFogColor(double depthFeet) {
    final terrainColor = getTerrainColor(depthFeet);
    final normalizedDepth =
        (depthFeet / GameConstants.maxDepth).clamp(0.0, 1.0);
    return terrainColor.withValues(alpha: normalizedDepth * 0.3);
  }

  /// Brighten a color by a factor (for ore sparkle, highlights)
  static Color brighten(Color color, double factor) {
    final r = (color.r + (1.0 - color.r) * factor).clamp(0.0, 1.0);
    final g = (color.g + (1.0 - color.g) * factor).clamp(0.0, 1.0);
    final b = (color.b + (1.0 - color.b) * factor).clamp(0.0, 1.0);
    return Color.from(alpha: color.a, red: r, green: g, blue: b);
  }

  /// Darken a color by a factor (for terrain stroke)
  static Color darken(Color color, double factor) {
    final r = (color.r * (1.0 - factor)).clamp(0.0, 1.0);
    final g = (color.g * (1.0 - factor)).clamp(0.0, 1.0);
    final b = (color.b * (1.0 - factor)).clamp(0.0, 1.0);
    return Color.from(alpha: color.a, red: r, green: g, blue: b);
  }

  /// Get the lava glow color with pulsing effect
  static Color getLavaGlowColor(double pulsePhase) {
    final intensity = 0.8 + 0.2 * pulsePhase; // 0.8 to 1.0
    return Color.from(
      alpha: intensity * 0.6,
      red: 1.0,
      green: 0.3 * intensity,
      blue: 0.0,
    );
  }

  /// Get gas shimmer color
  static Color getGasShimmerColor(double shimmerPhase) {
    return Color.from(
      alpha: 0.15 + 0.1 * shimmerPhase,
      red: 0.0,
      green: 1.0,
      blue: 0.3,
    );
  }

  static double _lerp(double a, double b, double t) {
    return a + (b - a) * t.clamp(0.0, 1.0);
  }
}
