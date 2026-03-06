import 'dart:ui';

import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/stratigraphy.dart';

/// Color utility functions for depth-graded rendering.
///
/// Provides smooth biome transitions, grass-cap surface coloring, and subtle
/// per-cell variation so the terrain looks organic rather than flat/uniform.
class ColorUtils {
  ColorUtils._();

  // -----------------------------------------------------------------------
  // Grass surface detection
  // -----------------------------------------------------------------------

  /// Whether a given depth qualifies as "grass surface."
  /// Grass renders on the very top of solid terrain near depth 0.
  static bool isGrassSurface(double depthFeet) {
    return depthFeet <= GameConstants.grassDepthThreshold && depthFeet >= -15.0;
  }

  /// Return the grass color with subtle per-position variation so it looks
  /// natural rather than a solid block of green.
  static Color getGrassColor(double worldX, double worldY) {
    // Cheap positional hash for variation
    final hash = ((worldX * 13.7 + worldY * 27.3).abs() % 1000) / 1000.0;
    // Mix between dark and light grass
    final t = hash * 0.4; // 0-40% variation
    return Color.lerp(
      GameConstants.grassColor,
      hash > 0.5
          ? GameConstants.grassDarkColor
          : GameConstants.grassAccentColor,
      t,
    )!;
  }

  // -----------------------------------------------------------------------
  // Depth-based terrain color (fallback when no stratigraphy)
  // -----------------------------------------------------------------------

  /// Get terrain color for a given depth in feet.
  /// Smooth lerp across all biome layers.
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

  // -----------------------------------------------------------------------
  // Stratigraphy-aware coloring (primary path for Genesis terrain)
  // -----------------------------------------------------------------------

  /// Get terrain color using geological stratigraphy with grass surface,
  /// smooth boundary blending, and subtle per-cell texture variation.
  ///
  /// Falls back to depth-based color when [stratigraphy] is null.
  static Color getStratumTerrainColor(
    double worldX,
    double depthFeet,
    Stratigraphy? stratigraphy, {
    bool hasAirAbove = false,
  }) {
    // Grass surface: top of terrain near the surface
    if (hasAirAbove && isGrassSurface(depthFeet)) {
      return getGrassColor(worldX, depthFeet);
    }

    if (stratigraphy == null) {
      return _addTextureVariation(
        getTerrainColor(depthFeet),
        worldX,
        depthFeet,
      );
    }

    final stratum = stratigraphy.getStratumAtPosition(worldX, depthFeet);
    final base = stratum.primaryColor;

    // Blend near stratum boundaries for smooth transitions
    final boundary = stratigraphy.getStratumBoundary(stratum, worldX);
    final distFromBoundary = depthFeet - boundary;
    const blendZone = 60.0; // feet of smooth transition

    Color layerColor;
    if (distFromBoundary < blendZone && distFromBoundary >= 0) {
      final stratumIdx = Stratigraphy.strata.indexOf(stratum);
      if (stratumIdx > 0) {
        final above = Stratigraphy.strata[stratumIdx - 1];
        // Smooth ease-in-out curve for natural blending
        final raw = (distFromBoundary / blendZone).clamp(0.0, 1.0);
        final t = raw * raw * (3.0 - 2.0 * raw); // smoothstep
        layerColor = Color.lerp(above.primaryColor, base, t)!;
      } else {
        layerColor = base;
      }
    } else {
      layerColor = base;
    }

    return _addTextureVariation(layerColor, worldX, depthFeet);
  }

  /// Add multi-scale per-cell brightness and hue variation for organic texture.
  ///
  /// Four overlapping hash patterns at different scales create natural-looking
  /// variation without visible repetition or grid artifacts. Includes warm/cool
  /// color shifting and saturation variation for realistic geological appearance.
  static Color _addTextureVariation(
    Color color,
    double worldX,
    double depthFeet,
  ) {
    // Use fractional positions for smoother variation (not just integer grid)
    final fx = worldX * 1.0;
    final fy = depthFeet * 0.067; // scale feet to ~tile units

    // Large-scale variation (geological patches, ~8-10 tile wavelength)
    final hash1 = (((fx * 17.3 + fy * 31.7).abs()) % 200) / 200.0;
    // Medium-scale variation (rock grain, ~3-4 tile wavelength)
    final hash2 = (((fx * 53.1 + fy * 97.3).abs()) % 150) / 150.0;
    // Fine-scale speckle (individual cell variation)
    final hash3 = (((fx * 127.7 + fy * 211.3).abs()) % 100) / 100.0;
    // Extra-fine noise for micro detail
    final hash4 = (((fx * 251.1 + fy * 173.9).abs()) % 80) / 80.0;

    // Multi-scale brightness: larger amplitude at bigger scales
    final brightness = (hash1 - 0.5) * 0.16 +
        (hash2 - 0.5) * 0.10 +
        (hash3 - 0.5) * 0.06 +
        (hash4 - 0.5) * 0.03;

    // Warm/cool hue shift — reddish vs bluish within the same base tone
    final warmShift = (hash2 - 0.5) * 0.05 + (hash4 - 0.5) * 0.02;

    // Saturation variation — some patches slightly more vivid or muted
    final satVar = (hash1 - 0.5) * 0.06;

    // Apply brightness + warmth + saturation
    final avgBright = (color.r + color.g + color.b) / 3.0;
    final r =
        (color.r + brightness + warmShift + (color.r - avgBright) * satVar)
            .clamp(0.0, 1.0);
    final g = (color.g +
            brightness -
            warmShift * 0.3 +
            (color.g - avgBright) * satVar)
        .clamp(0.0, 1.0);
    final b =
        (color.b + brightness - warmShift + (color.b - avgBright) * satVar)
            .clamp(0.0, 1.0);
    return Color.from(alpha: color.a, red: r, green: g, blue: b);
  }

  // -----------------------------------------------------------------------
  // Accent / ambient / fog colors
  // -----------------------------------------------------------------------

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
      return _lerp(
          GameConstants.shallowAmbientLight, GameConstants.deepAmbientLight, t);
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

  // -----------------------------------------------------------------------
  // Color manipulation helpers
  // -----------------------------------------------------------------------

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
