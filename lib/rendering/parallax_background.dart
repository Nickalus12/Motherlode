import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/color_utils.dart';
import 'package:motherlode/utils/constants.dart';

/// Multi-layer parallax background with procedural sky and rich cave atmosphere.
///
/// Underground: biome-reactive gradient, cave wall silhouettes, stalactites,
/// crystal sparkles, lava glow, fog wisps, floating embers, drip effects.
/// Sky: gradient, stars, sun, mountains, clouds.
class ParallaxBackground extends Component
    with HasGameReference<MotherlodeGame> {
  @override
  int get priority => -10;

  // Underground rock formations for each layer
  final List<List<_RockFormation>> _layers = [];
  bool _initialized = false;

  // Underground effect caches
  final List<_CrystalSparkle> _crystals = [];
  final List<_LavaGlow> _lavaGlows = [];
  final List<_FogWisp> _fogWisps = [];
  final List<_Stalactite> _stalactites = [];
  final List<_FloatingEmber> _embers = [];
  final List<_WaterDrip> _drips = [];
  bool _undergroundFxInitialized = false;

  // Sky system caches
  bool _skyInitialized = false;
  final List<_Star> _stars = [];
  final List<List<_Cloud>> _cloudLayers = [];
  final List<List<Offset>> _mountainLayers = [];
  double _time = 0.0;

  static const double _sunWorldY = -25.0;

  void _initialize() {
    if (_initialized) return;
    _initialized = true;

    final random = Random(42);

    // Generate 4 parallax layers with more density
    for (int layer = 0; layer < 4; layer++) {
      final formations = <_RockFormation>[];
      final count = 40 + layer * 20;

      for (int i = 0; i < count; i++) {
        formations.add(_RockFormation(
          x: random.nextDouble() * 2400 - 1200,
          y: random.nextDouble() * 600,
          width: 10 + random.nextDouble() * 60,
          height: 15 + random.nextDouble() * 80,
          seed: random.nextInt(10000),
        ));
      }
      _layers.add(formations);
    }
  }

  void _initializeUndergroundFx() {
    if (_undergroundFxInitialized) return;
    _undergroundFxInitialized = true;

    // Crystal sparkle points — more numerous and varied
    final crystalRandom = Random(137);
    for (int i = 0; i < 150; i++) {
      final y = 67.0 + crystalRandom.nextDouble() * 433;
      final depthFeet = y * GameConstants.feetPerTile;
      Color color;
      double size;
      if (depthFeet < GameConstants.rockEnd) {
        color = [
          const Color(0xFF4488FF),
          const Color(0xFF44FF88),
          const Color(0xFF88CCFF),
          const Color(0xFF66FFCC),
        ][crystalRandom.nextInt(4)];
        size = 0.12 + crystalRandom.nextDouble() * 0.2;
      } else if (depthFeet < GameConstants.volcanicEnd) {
        color = [
          const Color(0xFFFF4444),
          const Color(0xFFFF8844),
          const Color(0xFFFFAA22),
          const Color(0xFFFF6622),
        ][crystalRandom.nextInt(4)];
        size = 0.15 + crystalRandom.nextDouble() * 0.3;
      } else {
        color = [
          const Color(0xFFAA44FF),
          const Color(0xFFFF2222),
          const Color(0xFFDD00FF),
          const Color(0xFFFF0066),
        ][crystalRandom.nextInt(4)];
        size = 0.18 + crystalRandom.nextDouble() * 0.35;
      }
      _crystals.add(_CrystalSparkle(
        x: crystalRandom.nextDouble() * 1800 - 900,
        y: y,
        phase: crystalRandom.nextDouble() * pi * 2,
        color: color,
        size: size,
      ));
    }

    // Lava glow spots — bigger, more dramatic
    final lavaRandom = Random(256);
    for (int i = 0; i < 40; i++) {
      _lavaGlows.add(_LavaGlow(
        x: lavaRandom.nextDouble() * 1800 - 900,
        y: 200.0 + lavaRandom.nextDouble() * 200,
        radius: 4.0 + lavaRandom.nextDouble() * 10.0,
        phase: lavaRandom.nextDouble() * pi * 2,
        speed: 0.2 + lavaRandom.nextDouble() * 0.6,
      ));
    }

    // Fog wisps — more of them, more visible
    final fogRandom = Random(512);
    for (int i = 0; i < 60; i++) {
      _fogWisps.add(_FogWisp(
        x: fogRandom.nextDouble() * 1800 - 900,
        y: 10.0 + fogRandom.nextDouble() * 490,
        width: 6.0 + fogRandom.nextDouble() * 20.0,
        height: 1.5 + fogRandom.nextDouble() * 4.0,
        phase: fogRandom.nextDouble() * pi * 2,
        speed: 0.15 + fogRandom.nextDouble() * 0.4,
        driftAmplitude: 3.0 + fogRandom.nextDouble() * 5.0,
      ));
    }

    // Stalactite silhouettes hanging from cave ceilings
    final stalRandom = Random(777);
    for (int i = 0; i < 80; i++) {
      _stalactites.add(_Stalactite(
        x: stalRandom.nextDouble() * 1800 - 900,
        y: stalRandom.nextDouble() * 500,
        width: 0.3 + stalRandom.nextDouble() * 0.8,
        height: 1.0 + stalRandom.nextDouble() * 3.0,
        seed: stalRandom.nextInt(10000),
      ));
    }

    // Floating embers in volcanic/hell zones
    final emberRandom = Random(999);
    for (int i = 0; i < 60; i++) {
      _embers.add(_FloatingEmber(
        x: emberRandom.nextDouble() * 1800 - 900,
        y: 200.0 + emberRandom.nextDouble() * 300,
        phase: emberRandom.nextDouble() * pi * 2,
        speed: 0.3 + emberRandom.nextDouble() * 0.8,
        driftX: (emberRandom.nextDouble() - 0.5) * 2.0,
        size: 0.06 + emberRandom.nextDouble() * 0.1,
      ));
    }

    // Water drip points in shallow/rock zones
    final dripRandom = Random(333);
    for (int i = 0; i < 40; i++) {
      _drips.add(_WaterDrip(
        x: dripRandom.nextDouble() * 1800 - 900,
        y: 5.0 + dripRandom.nextDouble() * 150,
        phase: dripRandom.nextDouble() * pi * 2,
        speed: 0.8 + dripRandom.nextDouble() * 1.5,
        length: 0.3 + dripRandom.nextDouble() * 0.8,
      ));
    }
  }

  void _initializeSky() {
    if (_skyInitialized) return;
    _skyInitialized = true;

    final random = Random(1337);

    // Stars — more of them with color variety
    for (int i = 0; i < 180; i++) {
      final colorTemp = random.nextDouble();
      Color starColor;
      if (colorTemp < 0.6) {
        starColor = const Color(0xFFFFF8E7); // warm white
      } else if (colorTemp < 0.8) {
        starColor = const Color(0xFFAABBFF); // blue-white
      } else if (colorTemp < 0.9) {
        starColor = const Color(0xFFFFDDAA); // yellow
      } else {
        starColor = const Color(0xFFFFBB88); // orange
      }

      _stars.add(_Star(
        x: random.nextDouble() * 200 - 100,
        y: -30.0 - random.nextDouble() * 30.0,
        radius: 0.04 + random.nextDouble() * 0.1,
        brightness: 0.5 + random.nextDouble() * 0.5,
        twinkleSpeed: 1.0 + random.nextDouble() * 3.0,
        color: starColor,
      ));
    }

    // Cloud layers
    final cloudConfigs = [
      (count: 10, yMin: -22.0, yMax: -14.0, speed: 0.12, scale: 1.3),
      (count: 12, yMin: -17.0, yMax: -9.0, speed: 0.25, scale: 1.0),
      (count: 8, yMin: -11.0, yMax: -4.0, speed: 0.45, scale: 0.8),
    ];
    for (final cfg in cloudConfigs) {
      final clouds = <_Cloud>[];
      for (int i = 0; i < cfg.count; i++) {
        clouds.add(_Cloud(
          baseX: random.nextDouble() * 140 - 70,
          y: cfg.yMin + random.nextDouble() * (cfg.yMax - cfg.yMin),
          width: (3.0 + random.nextDouble() * 6.0) * cfg.scale,
          height: (0.8 + random.nextDouble() * 1.5) * cfg.scale,
          speed: cfg.speed * (0.8 + random.nextDouble() * 0.4),
          blobSeed: random.nextInt(10000),
        ));
      }
      _cloudLayers.add(clouds);
    }

    // Mountain silhouette layers (4 layers for more depth)
    final mountainConfigs = [
      (yBase: -0.5, heightMin: 4.0, heightMax: 7.0, points: 25, parallax: 0.1),
      (yBase: -0.3, heightMin: 3.0, heightMax: 5.5, points: 30, parallax: 0.2),
      (yBase: -0.1, heightMin: 2.0, heightMax: 4.0, points: 35, parallax: 0.35),
      (yBase: 0.0, heightMin: 1.0, heightMax: 2.5, points: 40, parallax: 0.5),
    ];
    for (final cfg in mountainConfigs) {
      final points = <Offset>[];
      const totalWidth = 240.0;
      final step = totalWidth / cfg.points;
      for (int i = 0; i <= cfg.points; i++) {
        final x = -totalWidth / 2 + i * step;
        final h1 = sin(i * 0.7 + 1.3) * cfg.heightMax * 0.5;
        final h2 = sin(i * 0.3 + 2.7) * cfg.heightMax * 0.3;
        final h3 = sin(i * 1.1 + 0.5) * cfg.heightMax * 0.2;
        final height = (h1 + h2 + h3).abs().clamp(cfg.heightMin, cfg.heightMax);
        points.add(Offset(x, cfg.yBase - height));
      }
      _mountainLayers.add(points);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    _initialize();
    _initializeSky();
    _initializeUndergroundFx();

    final cameraPos = game.camera.viewfinder.position;
    final visibleRect = game.camera.visibleWorldRect;
    final depthFeet = game.currentDepthFeet;

    const groundTop = 0.0;

    // --- UNDERGROUND SYSTEM (y > 0) ---
    if (visibleRect.bottom > groundTop) {
      final ugTop = groundTop.clamp(visibleRect.top, visibleRect.bottom);
      final ugRect = Rect.fromLTRB(
        visibleRect.left,
        ugTop,
        visibleRect.right,
        visibleRect.bottom,
      );

      final centerDepthFeet =
          ((ugTop + visibleRect.bottom) / 2.0) * GameConstants.feetPerTile;

      _renderBiomeFill(canvas, ugRect, centerDepthFeet);
      _renderCaveWalls(canvas, visibleRect, cameraPos);
      _renderStalactites(canvas, visibleRect, cameraPos);
      _renderLavaGlow(canvas, visibleRect, cameraPos);
      _renderFloatingEmbers(canvas, visibleRect, cameraPos);
      _renderCrystals(canvas, visibleRect, cameraPos);
      _renderWaterDrips(canvas, visibleRect, cameraPos);
      _renderFogWisps(canvas, visibleRect, cameraPos);
    }

    // --- SKY SYSTEM (above ground only) ---
    if (visibleRect.top < groundTop) {
      final skyBottom =
          groundTop.clamp(visibleRect.top, visibleRect.bottom);
      final skyRect = Rect.fromLTRB(
        visibleRect.left,
        visibleRect.top,
        visibleRect.right,
        skyBottom,
      );

      final skyOpacity = (1.0 - depthFeet / 200).clamp(0.0, 1.0);
      if (skyOpacity > 0) {
        canvas.save();
        canvas.clipRect(skyRect);

        _renderSkyGradient(canvas, skyRect, skyOpacity);
        _renderStars(canvas, visibleRect, cameraPos, skyOpacity);
        _renderSun(canvas, visibleRect, cameraPos, skyOpacity);
        _renderMountains(canvas, visibleRect, cameraPos, skyOpacity);
        _renderClouds(canvas, visibleRect, cameraPos, skyOpacity);

        canvas.restore();
      }
    }
  }

  // ===================================================================
  // UNDERGROUND SUB-RENDERERS
  // ===================================================================

  void _renderBiomeFill(Canvas canvas, Rect ugRect, double centerDepthFeet) {
    final topDepthFeet = (ugRect.top * GameConstants.feetPerTile)
        .clamp(0.0, GameConstants.maxDepth);
    final botDepthFeet = (ugRect.bottom * GameConstants.feetPerTile)
        .clamp(0.0, GameConstants.maxDepth);

    Color topColor = _getBiomeBackgroundColor(topDepthFeet);
    Color botColor = _getBiomeBackgroundColor(botDepthFeet);

    // Hell pulsing effect
    if (centerDepthFeet > GameConstants.hellStart) {
      final hellT = ((centerDepthFeet - GameConstants.hellStart) / 2000.0)
          .clamp(0.0, 1.0);
      final pulse = 0.5 + 0.5 * sin(_time * 0.8);
      final pulseAmount = hellT * pulse * 0.2;
      topColor = Color.lerp(topColor, const Color(0xFF550000), pulseAmount)!;
      botColor = Color.lerp(botColor, const Color(0xFF440000), pulseAmount)!;
    }

    // Volcanic zone subtle pulse
    if (centerDepthFeet > GameConstants.rockEnd &&
        centerDepthFeet <= GameConstants.hellStart) {
      final volcanicT =
          ((centerDepthFeet - GameConstants.rockEnd) /
                  (GameConstants.hellStart - GameConstants.rockEnd))
              .clamp(0.0, 1.0);
      final pulse = 0.5 + 0.5 * sin(_time * 0.5 + 1.5);
      final pulseAmount = volcanicT * pulse * 0.08;
      topColor =
          Color.lerp(topColor, const Color(0xFF3A1000), pulseAmount)!;
      botColor =
          Color.lerp(botColor, const Color(0xFF2A0800), pulseAmount)!;
    }

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [topColor, botColor],
    );
    canvas.drawRect(
      ugRect,
      Paint()..shader = gradient.createShader(ugRect),
    );
  }

  Color _getBiomeBackgroundColor(double depthFeet) {
    if (depthFeet <= GameConstants.sandLayerEnd) {
      final t = (depthFeet / GameConstants.sandLayerEnd).clamp(0.0, 1.0);
      return Color.lerp(
        const Color(0xFF5C4A2E),
        const Color(0xFF4A3820),
        t,
      )!;
    }
    if (depthFeet <= GameConstants.topsoilEnd) {
      final t = ((depthFeet - GameConstants.sandLayerEnd) /
              (GameConstants.topsoilEnd - GameConstants.sandLayerEnd))
          .clamp(0.0, 1.0);
      return Color.lerp(
        const Color(0xFF4A3820),
        const Color(0xFF2E1E10),
        t,
      )!;
    }
    if (depthFeet <= GameConstants.rockEnd) {
      final t = ((depthFeet - GameConstants.topsoilEnd) /
              (GameConstants.rockEnd - GameConstants.topsoilEnd))
          .clamp(0.0, 1.0);
      return Color.lerp(
        const Color(0xFF2E1E10),
        const Color(0xFF1A1D24),
        t,
      )!;
    }
    if (depthFeet <= GameConstants.volcanicEnd) {
      final t = ((depthFeet - GameConstants.rockEnd) /
              (GameConstants.volcanicEnd - GameConstants.rockEnd))
          .clamp(0.0, 1.0);
      return Color.lerp(
        const Color(0xFF1A1D24),
        const Color(0xFF2A0E08),
        t,
      )!;
    }
    final t = ((depthFeet - GameConstants.volcanicEnd) /
            (GameConstants.maxDepth - GameConstants.volcanicEnd))
        .clamp(0.0, 1.0);
    return Color.lerp(
      const Color(0xFF2A0E08),
      const Color(0xFF150505),
      t,
    )!;
  }

  void _renderCaveWalls(
    Canvas canvas,
    Rect visibleRect,
    Vector2 cameraPos,
  ) {
    for (int layerIdx = 0; layerIdx < _layers.length; layerIdx++) {
      final parallaxFactor = 0.2 + layerIdx * 0.2;
      final baseOpacity = 0.15 + layerIdx * 0.12;

      final shiftX = cameraPos.x * (1 - parallaxFactor);
      final shiftY = cameraPos.y * (1 - parallaxFactor);

      for (final formation in _layers[layerIdx]) {
        final screenX = formation.x + shiftX;
        final screenY = formation.y + shiftY;

        if (screenX + formation.width < visibleRect.left ||
            screenX - formation.width > visibleRect.right ||
            screenY + formation.height < visibleRect.top ||
            screenY - formation.height > visibleRect.bottom ||
            screenY < 0) {
          continue;
        }

        final formationDepthFeet = screenY * GameConstants.feetPerTile;
        final baseColor = ColorUtils.getTerrainColor(formationDepthFeet);
        final darkened =
            ColorUtils.darken(baseColor, 0.35 + (1 - baseOpacity) * 0.15);

        _drawFormation(canvas, formation, screenX, screenY,
            darkened.withValues(alpha: baseOpacity));
      }
    }
  }

  void _renderStalactites(
    Canvas canvas,
    Rect visibleRect,
    Vector2 cameraPos,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;
    int rendered = 0;

    for (final stal in _stalactites) {
      if (rendered >= 40) break;

      final screenX = stal.x + cameraPos.x * 0.12;
      final screenY = stal.y + cameraPos.y * 0.12;

      if (screenX + stal.width < visibleRect.left - 2 ||
          screenX - stal.width > visibleRect.right + 2 ||
          screenY + stal.height < visibleRect.top - 2 ||
          screenY - stal.height > visibleRect.bottom + 2 ||
          screenY < 0) {
        continue;
      }

      final depthFeet = screenY * GameConstants.feetPerTile;
      final baseColor = ColorUtils.getTerrainColor(depthFeet);
      final darkened = ColorUtils.darken(baseColor, 0.5);
      paint.color = darkened.withValues(alpha: 0.25);

      // Stalactite shape: wider at top, narrow point at bottom
      final rng = Random(stal.seed);
      final path = Path();
      final halfW = stal.width / 2;
      path.moveTo(screenX - halfW, screenY);
      path.lineTo(screenX + halfW, screenY);
      // Slightly irregular tapering
      final midX = screenX + (rng.nextDouble() - 0.5) * halfW * 0.3;
      path.lineTo(
        midX + halfW * 0.15,
        screenY + stal.height * 0.6,
      );
      path.lineTo(midX, screenY + stal.height);
      path.lineTo(
        midX - halfW * 0.15,
        screenY + stal.height * 0.6,
      );
      path.close();
      canvas.drawPath(path, paint);

      // Drip highlight at tip
      paint.color = ColorUtils.brighten(baseColor, 0.2).withValues(alpha: 0.15);
      canvas.drawCircle(
        Offset(midX, screenY + stal.height),
        0.08,
        paint,
      );

      rendered++;
    }
  }

  void _renderCrystals(Canvas canvas, Rect visibleRect, Vector2 cameraPos) {
    final paint = Paint()..style = PaintingStyle.fill;
    int rendered = 0;

    for (final crystal in _crystals) {
      if (rendered >= 50) break;

      final screenX = crystal.x + cameraPos.x * 0.1;
      final screenY = crystal.y + cameraPos.y * 0.1;

      if (screenX < visibleRect.left - 2 ||
          screenX > visibleRect.right + 2 ||
          screenY < visibleRect.top - 2 ||
          screenY > visibleRect.bottom + 2) {
        continue;
      }

      final twinkle = sin(_time * 2.5 + crystal.phase) * 0.5 + 0.5;
      final alpha = twinkle * 0.8 + 0.1;

      // Core sparkle
      paint.color = crystal.color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(screenX, screenY), crystal.size, paint);

      // Cross-shaped sparkle rays on bright twinkle
      if (twinkle > 0.5) {
        final rayAlpha = (twinkle - 0.5) * 2.0 * alpha * 0.4;
        paint.color = crystal.color.withValues(alpha: rayAlpha);
        final rayLen = crystal.size * 2.5;
        final rayW = crystal.size * 0.3;
        // Horizontal ray
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(screenX, screenY),
            width: rayLen,
            height: rayW,
          ),
          paint,
        );
        // Vertical ray
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(screenX, screenY),
            width: rayW,
            height: rayLen,
          ),
          paint,
        );
      }

      // Glow halo
      if (twinkle > 0.4) {
        paint.color = crystal.color.withValues(alpha: alpha * 0.15);
        canvas.drawCircle(
            Offset(screenX, screenY), crystal.size * 4.0, paint);
      }

      rendered++;
    }
  }

  void _renderLavaGlow(Canvas canvas, Rect visibleRect, Vector2 cameraPos) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final glow in _lavaGlows) {
      final screenX = glow.x + cameraPos.x * 0.15;
      final screenY = glow.y + cameraPos.y * 0.15;

      final maxR = glow.radius;
      if (screenX + maxR < visibleRect.left ||
          screenX - maxR > visibleRect.right ||
          screenY + maxR < visibleRect.top ||
          screenY - maxR > visibleRect.bottom) {
        continue;
      }

      final pulse = sin(_time * glow.speed + glow.phase) * 0.5 + 0.5;
      final alpha = 0.1 + pulse * 0.18;
      final r = glow.radius * (0.8 + pulse * 0.2);

      // Outer glow
      paint.color = Color.from(
        alpha: alpha * 0.5,
        red: 1.0,
        green: 0.2 + pulse * 0.1,
        blue: 0.0,
      );
      canvas.drawCircle(Offset(screenX, screenY), r * 1.5, paint);

      // Main glow
      paint.color = Color.from(
        alpha: alpha,
        red: 1.0,
        green: 0.3 + pulse * 0.15,
        blue: 0.0,
      );
      canvas.drawCircle(Offset(screenX, screenY), r, paint);

      // Inner brighter core
      paint.color = Color.from(
        alpha: alpha * 0.7,
        red: 1.0,
        green: 0.6 + pulse * 0.1,
        blue: 0.1,
      );
      canvas.drawCircle(Offset(screenX, screenY), r * 0.35, paint);

      // Hot white center
      paint.color = Color.from(
        alpha: alpha * 0.3,
        red: 1.0,
        green: 0.9,
        blue: 0.5,
      );
      canvas.drawCircle(Offset(screenX, screenY), r * 0.15, paint);
    }
  }

  void _renderFloatingEmbers(
    Canvas canvas,
    Rect visibleRect,
    Vector2 cameraPos,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;
    int rendered = 0;

    for (final ember in _embers) {
      if (rendered >= 30) break;

      // Embers float upward slowly and drift sideways
      final t = (_time * ember.speed + ember.phase) % (pi * 4);
      final rise = sin(t * 0.5) * 3.0;
      final drift = sin(t * 0.3 + ember.phase) * ember.driftX;

      final screenX = ember.x + drift + cameraPos.x * 0.08;
      final screenY = ember.y - rise + cameraPos.y * 0.08;

      if (screenX < visibleRect.left - 1 ||
          screenX > visibleRect.right + 1 ||
          screenY < visibleRect.top - 1 ||
          screenY > visibleRect.bottom + 1 ||
          screenY < 0) {
        continue;
      }

      final flicker = sin(_time * 8 + ember.phase) * 0.3 + 0.7;
      final alpha = flicker * 0.6;

      // Ember core
      paint.color = Color.from(
        alpha: alpha,
        red: 1.0,
        green: 0.4 + flicker * 0.3,
        blue: 0.0,
      );
      canvas.drawCircle(Offset(screenX, screenY), ember.size, paint);

      // Tiny glow
      paint.color = Color.from(
        alpha: alpha * 0.3,
        red: 1.0,
        green: 0.3,
        blue: 0.0,
      );
      canvas.drawCircle(Offset(screenX, screenY), ember.size * 3.0, paint);

      rendered++;
    }
  }

  void _renderWaterDrips(
    Canvas canvas,
    Rect visibleRect,
    Vector2 cameraPos,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;
    int rendered = 0;

    for (final drip in _drips) {
      if (rendered >= 20) break;

      final screenX = drip.x + cameraPos.x * 0.05;
      final screenY = drip.y + cameraPos.y * 0.05;

      if (screenX < visibleRect.left - 1 ||
          screenX > visibleRect.right + 1 ||
          screenY < visibleRect.top - 1 ||
          screenY > visibleRect.bottom + 2 ||
          screenY < 0) {
        continue;
      }

      // Drip animation cycle
      final cycle = (_time * drip.speed + drip.phase) % (pi * 2);
      final dropProgress = (cycle / (pi * 2)).clamp(0.0, 1.0);

      // Drip drop falling
      final dropY = screenY + dropProgress * drip.length * 3;
      final dropAlpha = (1.0 - dropProgress) * 0.3;

      if (dropAlpha > 0.02) {
        // Water drop
        paint.color = Color.from(
          alpha: dropAlpha,
          red: 0.6,
          green: 0.75,
          blue: 1.0,
        );
        canvas.drawCircle(Offset(screenX, dropY), 0.05, paint);

        // Streak above drop
        final streakAlpha = dropAlpha * 0.5;
        paint.color = Color.from(
          alpha: streakAlpha,
          red: 0.6,
          green: 0.75,
          blue: 1.0,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(screenX, dropY - 0.1),
            width: 0.02,
            height: 0.15,
          ),
          paint,
        );
      }

      // Splash ripple at bottom of cycle
      if (dropProgress > 0.8) {
        final splashT = (dropProgress - 0.8) / 0.2;
        final splashAlpha = (1.0 - splashT) * 0.2;
        final splashR = 0.1 + splashT * 0.3;
        paint.color = Color.from(
          alpha: splashAlpha,
          red: 0.6,
          green: 0.75,
          blue: 1.0,
        );
        canvas.drawCircle(
          Offset(screenX, screenY + drip.length * 3),
          splashR,
          paint,
        );
      }

      rendered++;
    }
  }

  void _renderFogWisps(
    Canvas canvas,
    Rect visibleRect,
    Vector2 cameraPos,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;
    int rendered = 0;

    for (final wisp in _fogWisps) {
      if (rendered >= 30) break;

      final drift = sin(_time * wisp.speed + wisp.phase) * wisp.driftAmplitude;
      final screenX = wisp.x + drift + cameraPos.x * 0.05;
      final screenY = wisp.y + cameraPos.y * 0.05;

      if (screenX + wisp.width < visibleRect.left ||
          screenX - wisp.width > visibleRect.right ||
          screenY + wisp.height < visibleRect.top ||
          screenY - wisp.height > visibleRect.bottom ||
          screenY < 0) {
        continue;
      }

      final wispDepthFeet = screenY * GameConstants.feetPerTile;
      final depthFactor = (wispDepthFeet / 1500.0).clamp(0.0, 1.0);
      final breathe = sin(_time * 0.5 + wisp.phase) * 0.3 + 0.7;
      final alpha = depthFactor * 0.1 * breathe;

      if (alpha < 0.005) continue;

      Color fogColor;
      if (wispDepthFeet < GameConstants.rockEnd) {
        fogColor = const Color(0xFFCCCCDD);
      } else if (wispDepthFeet < GameConstants.volcanicEnd) {
        fogColor = const Color(0xFFDDAA88);
      } else {
        fogColor = const Color(0xFFCC6644);
      }

      paint.color = fogColor.withValues(alpha: alpha);

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(screenX, screenY),
          width: wisp.width,
          height: wisp.height,
        ),
        Radius.circular(wisp.height * 0.5),
      );
      canvas.drawRRect(rect, paint);
      rendered++;
    }
  }

  // ===================================================================
  // SKY SUB-RENDERERS
  // ===================================================================

  void _renderSkyGradient(Canvas canvas, Rect skyRect, double opacity) {
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.from(alpha: opacity, red: 0.03, green: 0.03, blue: 0.15),
        Color.from(alpha: opacity, red: 0.08, green: 0.1, blue: 0.35),
        Color.from(alpha: opacity, red: 0.15, green: 0.2, blue: 0.5),
        Color.from(alpha: opacity, red: 0.4, green: 0.35, blue: 0.55),
        Color.from(alpha: opacity, red: 0.85, green: 0.5, blue: 0.3),
        Color.from(alpha: opacity, red: 0.95, green: 0.6, blue: 0.4),
      ],
      stops: const [0.0, 0.15, 0.3, 0.55, 0.85, 1.0],
    );
    canvas.drawRect(
      skyRect,
      Paint()..shader = gradient.createShader(skyRect),
    );
  }

  void _renderStars(
      Canvas canvas, Rect visibleRect, Vector2 cameraPos, double opacity) {
    final starPaint = Paint()..style = PaintingStyle.fill;

    for (final star in _stars) {
      final sx = star.x + cameraPos.x * 0.02;
      final sy = star.y + cameraPos.y * 0.02;

      if (sx < visibleRect.left - 1 ||
          sx > visibleRect.right + 1 ||
          sy < visibleRect.top - 1 ||
          sy > visibleRect.bottom + 1) {
        continue;
      }

      final horizonFade =
          ((sy - visibleRect.top) / (visibleRect.bottom - visibleRect.top))
              .clamp(0.0, 1.0);
      final fade = (1.0 - horizonFade * 1.5).clamp(0.0, 1.0);

      final twinkle =
          0.6 + 0.4 * sin(_time * star.twinkleSpeed + star.x * 10);

      final alpha =
          (star.brightness * fade * twinkle * opacity).clamp(0.0, 1.0);
      if (alpha < 0.05) continue;

      starPaint.color = star.color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(sx, sy), star.radius, starPaint);

      // Subtle glow around bright stars
      if (star.radius > 0.07 && alpha > 0.3) {
        starPaint.color = star.color.withValues(alpha: alpha * 0.15);
        canvas.drawCircle(Offset(sx, sy), star.radius * 3.0, starPaint);
      }
    }
  }

  void _renderSun(
      Canvas canvas, Rect visibleRect, Vector2 cameraPos, double opacity) {
    final sunX = cameraPos.x * 0.05 + 5.0;
    final sunY = _sunWorldY + cameraPos.y * 0.03;

    if (sunY > visibleRect.bottom + 5 || sunY < visibleRect.top - 10) return;

    // Outer atmospheric glow
    const outerGlowRadius = 8.0;
    final outerPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.from(
              alpha: 0.15 * opacity, red: 1.0, green: 0.9, blue: 0.5),
          const Color.from(alpha: 0.0, red: 1.0, green: 0.8, blue: 0.3),
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(sunX, sunY), radius: outerGlowRadius));
    canvas.drawCircle(Offset(sunX, sunY), outerGlowRadius, outerPaint);

    // Main glow
    const glowRadius = 4.0;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.from(alpha: 0.7 * opacity, red: 1.0, green: 0.95, blue: 0.7),
          Color.from(alpha: 0.2 * opacity, red: 1.0, green: 0.85, blue: 0.5),
          const Color.from(alpha: 0.0, red: 1.0, green: 0.8, blue: 0.4),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(
          center: Offset(sunX, sunY), radius: glowRadius));
    canvas.drawCircle(Offset(sunX, sunY), glowRadius, glowPaint);

    // Sun disc
    const sunRadius = 1.2;
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.from(alpha: opacity, red: 1.0, green: 0.98, blue: 0.9),
          Color.from(alpha: opacity, red: 1.0, green: 0.92, blue: 0.65),
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(sunX, sunY), radius: sunRadius));
    canvas.drawCircle(Offset(sunX, sunY), sunRadius, sunPaint);
  }

  void _renderMountains(
      Canvas canvas, Rect visibleRect, Vector2 cameraPos, double opacity) {
    final colors = [
      Color.from(alpha: 0.4 * opacity, red: 0.3, green: 0.25, blue: 0.4),
      Color.from(alpha: 0.5 * opacity, red: 0.22, green: 0.2, blue: 0.32),
      Color.from(alpha: 0.65 * opacity, red: 0.15, green: 0.12, blue: 0.22),
      Color.from(alpha: 0.8 * opacity, red: 0.08, green: 0.06, blue: 0.12),
    ];
    final parallaxFactors = [0.1, 0.2, 0.35, 0.5];

    for (int i = 0; i < _mountainLayers.length; i++) {
      final points = _mountainLayers[i];
      final pf = parallaxFactors[i];
      final shiftX = cameraPos.x * (1 - pf);

      final path = Path();
      final firstX = points.first.dx + shiftX;
      path.moveTo(firstX, 0.0);

      for (final pt in points) {
        path.lineTo(pt.dx + shiftX, pt.dy);
      }

      final lastX = points.last.dx + shiftX;
      path.lineTo(lastX, 0.0);
      path.close();

      canvas.drawPath(path, Paint()..color = colors[i]);
    }
  }

  void _renderClouds(
      Canvas canvas, Rect visibleRect, Vector2 cameraPos, double opacity) {
    final cloudPaint = Paint()..style = PaintingStyle.fill;

    for (int layerIdx = 0; layerIdx < _cloudLayers.length; layerIdx++) {
      final pf = 0.1 + layerIdx * 0.15;

      for (final cloud in _cloudLayers[layerIdx]) {
        final driftX =
            cloud.baseX + _time * cloud.speed + cameraPos.x * (1 - pf);
        final cy = cloud.y + cameraPos.y * 0.05;

        final wrappedX = ((driftX + 70) % 140) - 70;

        if (wrappedX + cloud.width < visibleRect.left - 5 ||
            wrappedX - cloud.width > visibleRect.right + 5 ||
            cy + cloud.height < visibleRect.top - 2 ||
            cy - cloud.height > visibleRect.bottom + 2) {
          continue;
        }

        _drawNaturalCloud(canvas, wrappedX, cy, cloud, opacity, cloudPaint);
      }
    }
  }

  /// Draw a single cloud using overlapping bezier paths for natural shapes
  void _drawNaturalCloud(Canvas canvas, double cx, double cy, _Cloud cloud,
      double opacity, Paint paint) {
    final rng = Random(cloud.blobSeed);
    final w = cloud.width;
    final h = cloud.height;
    final cloudAlpha = (0.45 * opacity).clamp(0.0, 1.0);

    // Build a natural cloud shape using bezier curves
    // Main body path
    final bodyPath = Path();
    final bumpCount = 5 + rng.nextInt(3);
    final bumps = <_CloudBump>[];

    // Generate bumps along the top of the cloud
    for (int i = 0; i < bumpCount; i++) {
      final t = i / (bumpCount - 1);
      final bx = cx - w * 0.45 + t * w * 0.9;
      // Bumps are higher in the middle, lower at edges
      final edgeFade = 1.0 - (2 * t - 1).abs();
      final bumpH = h * (0.4 + rng.nextDouble() * 0.5) * (0.3 + edgeFade * 0.7);
      final bumpW = w * (0.2 + rng.nextDouble() * 0.15);
      bumps.add(_CloudBump(x: bx, y: cy, width: bumpW, height: bumpH));
    }

    // Draw shadow layer (underneath, offset down)
    paint.color = Color.from(
        alpha: cloudAlpha * 0.15, red: 0.5, green: 0.5, blue: 0.6);
    for (final bump in bumps) {
      final shadowPath = Path();
      shadowPath.addOval(Rect.fromCenter(
        center: Offset(bump.x, bump.y + bump.height * 0.1),
        width: bump.width * 1.1,
        height: bump.height * 0.8,
      ));
      canvas.drawPath(shadowPath, paint);
    }

    // Draw main cloud body (flat bottom, bumpy top)
    // Bottom flat edge
    bodyPath.moveTo(cx - w * 0.4, cy + h * 0.15);

    // Build the bumpy top outline using quadratic curves
    // Left rise
    bodyPath.quadraticBezierTo(
      cx - w * 0.45, cy - bumps.first.height * 0.3,
      bumps.first.x, cy - bumps.first.height,
    );

    // Bumps along top
    for (int i = 1; i < bumps.length; i++) {
      final prev = bumps[i - 1];
      final curr = bumps[i];
      final midX = (prev.x + curr.x) / 2;
      final dip = cy - min(prev.height, curr.height) * 0.4;

      bodyPath.quadraticBezierTo(
        midX, dip,
        curr.x, cy - curr.height,
      );
    }

    // Right descent back to flat bottom
    bodyPath.quadraticBezierTo(
      cx + w * 0.45, cy - bumps.last.height * 0.3,
      cx + w * 0.4, cy + h * 0.15,
    );
    bodyPath.close();

    // Main fill
    paint.color = Color.from(
        alpha: cloudAlpha, red: 0.95, green: 0.95, blue: 0.98);
    canvas.drawPath(bodyPath, paint);

    // Top highlight (brighter bumps)
    for (final bump in bumps) {
      final highlightPath = Path();
      highlightPath.addOval(Rect.fromCenter(
        center: Offset(bump.x, cy - bump.height * 0.75),
        width: bump.width * 0.7,
        height: bump.height * 0.5,
      ));
      paint.color = Color.from(
          alpha: cloudAlpha * 0.4, red: 1.0, green: 1.0, blue: 1.0);
      canvas.drawPath(highlightPath, paint);
    }

    // Bottom shading (darker underside)
    final bottomPath = Path();
    bottomPath.addRect(Rect.fromLTRB(
      cx - w * 0.35, cy, cx + w * 0.35, cy + h * 0.15,
    ));
    paint.color = Color.from(
        alpha: cloudAlpha * 0.2, red: 0.6, green: 0.6, blue: 0.75);
    canvas.drawPath(bottomPath, paint);
  }

  // ===================================================================
  // SHARED HELPERS
  // ===================================================================

  void _drawFormation(
    Canvas canvas,
    _RockFormation formation,
    double x,
    double y,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final random = Random(formation.seed);
    final w = formation.width;
    final h = formation.height;

    // More detailed formation shape with additional control points
    path.moveTo(x, y + h);
    path.lineTo(x + w * 0.08, y + h * (0.35 + random.nextDouble() * 0.2));
    path.lineTo(x + w * 0.18, y + h * (0.2 + random.nextDouble() * 0.15));
    path.lineTo(x + w * 0.3, y + h * (0.1 + random.nextDouble() * 0.12));
    path.lineTo(x + w * 0.42, y + h * (0.03 + random.nextDouble() * 0.08));
    path.lineTo(x + w * 0.5, y);
    path.lineTo(x + w * 0.58, y + h * (0.03 + random.nextDouble() * 0.08));
    path.lineTo(x + w * 0.7, y + h * (0.1 + random.nextDouble() * 0.12));
    path.lineTo(x + w * 0.82, y + h * (0.2 + random.nextDouble() * 0.15));
    path.lineTo(x + w * 0.92, y + h * (0.35 + random.nextDouble() * 0.2));
    path.lineTo(x + w, y + h);
    path.close();

    canvas.drawPath(path, paint);
  }
}

// ===================================================================
// DATA CLASSES
// ===================================================================

class _RockFormation {
  final double x, y, width, height;
  final int seed;
  const _RockFormation({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.seed,
  });
}

class _CrystalSparkle {
  final double x, y, phase, size;
  final Color color;
  const _CrystalSparkle({
    required this.x,
    required this.y,
    required this.phase,
    required this.color,
    required this.size,
  });
}

class _LavaGlow {
  final double x, y, radius, phase, speed;
  const _LavaGlow({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.speed,
  });
}

class _FogWisp {
  final double x, y, width, height, phase, speed, driftAmplitude;
  const _FogWisp({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.phase,
    required this.speed,
    required this.driftAmplitude,
  });
}

class _Stalactite {
  final double x, y, width, height;
  final int seed;
  const _Stalactite({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.seed,
  });
}

class _FloatingEmber {
  final double x, y, phase, speed, driftX, size;
  const _FloatingEmber({
    required this.x,
    required this.y,
    required this.phase,
    required this.speed,
    required this.driftX,
    required this.size,
  });
}

class _WaterDrip {
  final double x, y, phase, speed, length;
  const _WaterDrip({
    required this.x,
    required this.y,
    required this.phase,
    required this.speed,
    required this.length,
  });
}

class _Star {
  final double x, y, radius, brightness, twinkleSpeed;
  final Color color;
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.brightness,
    required this.twinkleSpeed,
    required this.color,
  });
}

class _Cloud {
  final double baseX, y, width, height, speed;
  final int blobSeed;
  const _Cloud({
    required this.baseX,
    required this.y,
    required this.width,
    required this.height,
    required this.speed,
    required this.blobSeed,
  });
}

class _CloudBump {
  final double x, y, width, height;
  const _CloudBump({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}
