import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart' hide Vector2;
import 'package:flame_forge2d/flame_forge2d.dart'
    hide ParticleSystem, ParticleType;

import 'package:motherlode/rendering/item_sprite_manager.dart';
import 'package:motherlode/rendering/particle_pool.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/utils/math_utils.dart';
import 'package:motherlode/world/terrain_cell.dart';

/// Individual particle with position, velocity, color, lifetime
/// Kept for dust particles which are persistent and don't use the pool
class Particle {
  double x, y;
  double vx, vy;
  Color color;
  double size;
  double life;
  double maxLife;
  double angularVelocity;
  double rotation;
  bool affectedByGravity;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.life,
    this.angularVelocity = 0,
    this.rotation = 0,
    this.affectedByGravity = false,
  }) : maxLife = life;

  double get lifeRatio => (life / maxLife).clamp(0.0, 1.0);
  bool get isDead => life <= 0;

  void update(double dt) {
    life -= dt;
    x += vx * dt;
    y += vy * dt;
    rotation += angularVelocity * dt;

    if (affectedByGravity) {
      vy += GameConstants.gravity * 18 * dt;
    }
  }
}

/// A short-lived animated sprite that pops up from a mined ore location.
class _PickupEffect {
  double x, y;
  final double startY;
  final String? spritePath;
  final Color color;
  double elapsed = 0;
  static const double duration = 0.6;
  static const double riseDistance = 1.5;
  static const double spriteFps = 10.0;

  _PickupEffect({
    required this.x,
    required this.y,
    this.spritePath,
    required this.color,
  }) : startY = y;

  bool get isDead => elapsed >= duration;

  double get progress => (elapsed / duration).clamp(0.0, 1.0);

  void update(double dt) {
    elapsed += dt;
    // Ease-out rise
    final t = progress;
    y = startY - riseDistance * (1 - (1 - t) * (1 - t));
  }
}

/// Expanding shockwave ring from an explosion.
class _ShockwaveRing {
  double x, y;
  double radius;
  final double maxRadius;
  double elapsed = 0;
  static const double duration = 0.4;

  _ShockwaveRing({required this.x, required this.y, required this.maxRadius})
      : radius = 0;

  bool get isDead => elapsed >= duration;

  double get progress => (elapsed / duration).clamp(0.0, 1.0);

  void update(double dt) {
    elapsed += dt;
    // Ease-out expansion
    final t = progress;
    radius = maxRadius * (1 - (1 - t) * (1 - t));
  }
}

/// Particle system using a pre-allocated object pool for zero-allocation
/// particle emission during gameplay.
class ParticleSystem extends Component {
  final ParticlePool _pool = ParticlePool();
  final Random _random = Random();
  final List<_PickupEffect> _pickupEffects = [];
  final List<_ShockwaveRing> _shockwaves = [];

  // Ambient dust particles (persistent, not pooled)
  final List<Particle> _dustParticles = [];
  bool _dustInitialized = false;

  /// Access the pool for stats/testing
  ParticlePool get pool => _pool;

  @override
  void update(double dt) {
    super.update(dt);

    // Update pooled particles
    _pool.update(dt);

    // Update pickup effects
    for (int i = _pickupEffects.length - 1; i >= 0; i--) {
      _pickupEffects[i].update(dt);
      if (_pickupEffects[i].isDead) {
        _pickupEffects.removeAt(i);
      }
    }

    // Update shockwave rings
    for (int i = _shockwaves.length - 1; i >= 0; i--) {
      _shockwaves[i].update(dt);
      if (_shockwaves[i].isDead) {
        _shockwaves.removeAt(i);
      }
    }

    // Update dust
    for (final dust in _dustParticles) {
      dust.update(dt);
      if (dust.isDead) {
        _resetDustParticle(dust);
      }
    }
  }

  // Pre-allocated Paint to avoid per-frame allocation
  final Paint _renderPaint = Paint()..style = PaintingStyle.fill;

  @override
  void render(Canvas canvas) {
    final paint = _renderPaint;

    // Render pooled particles
    for (final p in _pool.activeParticles) {
      final alpha = p.lifeRatio;

      // Smoke particles render as semi-transparent circles
      if (p.type == ParticleType.smoke) {
        paint.color = p.color.withValues(alpha: alpha * 0.4);
        canvas.drawCircle(Offset(p.x, p.y), p.size * (2.0 - alpha), paint);
        continue;
      }

      // Fire particles: circles that shrink
      if (p.type == ParticleType.fire) {
        paint.color = p.color.withValues(alpha: alpha * 0.8);
        canvas.drawCircle(Offset(p.x, p.y), p.size * alpha, paint);
        continue;
      }

      // Ambient particles: soft circles
      if (p.type == ParticleType.ambient) {
        paint.color = p.color.withValues(alpha: alpha * (p.color.a));
        canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
        continue;
      }

      // Spark particles: small bright dots
      if (p.type == ParticleType.spark) {
        paint.color = p.color.withValues(alpha: alpha);
        canvas.drawCircle(Offset(p.x, p.y), p.size * 0.5, paint);
        continue;
      }

      // Splash particles: stretched ellipses
      if (p.type == ParticleType.splash) {
        paint.color = p.color.withValues(alpha: alpha * 0.7);
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size * 1.5,
            height: p.size * 0.6,
          ),
          paint,
        );
        canvas.restore();
        continue;
      }

      paint.color = p.color.withValues(alpha: alpha * (p.color.a));

      canvas.save();
      canvas.translate(p.x, p.y);
      if (p.rotation != 0) {
        canvas.rotate(p.rotation);
      }

      final halfSize = p.size * p.lifeRatio / 2;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: halfSize * 2,
          height: halfSize * 2,
        ),
        paint,
      );
      canvas.restore();
    }

    // Render dust
    for (final d in _dustParticles) {
      paint.color =
          const Color(0xFFFFFFFF).withValues(alpha: d.lifeRatio * 0.08);
      canvas.drawCircle(Offset(d.x, d.y), d.size, paint);
    }

    // Render pickup effects
    final spriteManager = ItemSpriteManager.instance;
    for (final effect in _pickupEffects) {
      final alpha = 1.0 - effect.progress;
      final scale = 0.6 + 0.4 * (1.0 - effect.progress);

      if (effect.spritePath != null) {
        final image = spriteManager.getImage(effect.spritePath!);
        if (image != null) {
          final frameIndex = spriteManager.getAnimatedFrame(
            effect.elapsed,
            _PickupEffect.spriteFps,
          );
          final srcRect = spriteManager.getFrame(
            effect.spritePath!,
            frameIndex,
          );
          final halfSize = scale * 0.5;
          final dstRect = Rect.fromLTWH(
            effect.x - halfSize,
            effect.y - halfSize,
            scale,
            scale,
          );
          paint.color = Color.from(
            alpha: alpha,
            red: 1.0,
            green: 1.0,
            blue: 1.0,
          );
          canvas.drawImageRect(image, srcRect, dstRect, paint);
          continue;
        }
      }

      // Fallback: colored circle
      paint.color = effect.color.withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(effect.x, effect.y),
        scale * 0.3,
        paint,
      );
    }

    // Render shockwave rings
    for (final ring in _shockwaves) {
      final alpha = (1.0 - ring.progress) * 0.6;
      final strokeWidth = 0.15 * (1.0 - ring.progress * 0.5);
      // Orange-white ring that fades and expands
      final t = ring.progress;
      final ringColor = Color.lerp(
        const Color(0xFFFFAA33),
        const Color(0xFFFFFFFF),
        t,
      )!;
      paint.color = ringColor.withValues(alpha: alpha);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = strokeWidth;
      canvas.drawCircle(
        Offset(ring.x, ring.y),
        ring.radius,
        paint,
      );
    }
    // Reset paint style
    paint.style = PaintingStyle.fill;
  }

  // ─── Emitter Methods (now using pool) ───

  PooledParticle _emit({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required Color color,
    required double size,
    required double lifetime,
    ParticleType type = ParticleType.dirt,
    double angularVelocity = 0,
  }) {
    final p = _pool.acquire();
    p.x = x;
    p.y = y;
    p.vx = vx;
    p.vy = vy;
    p.color = color;
    p.size = size;
    p.lifetime = lifetime;
    p.type = type;
    p.angularVelocity = angularVelocity;
    return p;
  }

  /// 1. DRILL PARTICLES: Material-specific when drilling
  void emitDrillParticles(Vector2 position, Color terrainColor,
      [CellType? cellType]) {
    final count = MathUtils.randomRangeInt(
      GameConstants.drillParticlesMin,
      GameConstants.drillParticlesMax,
    );

    final material = cellType ?? CellType.dirt;

    for (int i = 0; i < count; i++) {
      switch (material) {
        case CellType.sand:
          _emitSandParticle(position);
        case CellType.rock:
          _emitRockParticle(position);
        case CellType.obsidian:
          _emitObsidianParticle(position);
        case CellType.ore:
          _emitOreChipParticle(position, terrainColor);
        default:
          _emitDirtParticle(position, terrainColor);
      }
    }

    // Rock and obsidian also emit sparks
    if (material == CellType.rock || material == CellType.obsidian) {
      final sparkCount = MathUtils.randomRangeInt(2, 5);
      for (int i = 0; i < sparkCount; i++) {
        _emitDrillSpark(position, material);
      }
    }
  }

  void _emitSandParticle(Vector2 position) {
    // Small yellow puffs that float briefly
    final angle = pi / 2 + MathUtils.randomRange(-0.8, 0.8);
    final speed = MathUtils.randomRange(3, 7);
    _emit(
      x: position.x + MathUtils.randomRange(-0.3, 0.3),
      y: position.y,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed - 1,
      color: Color.from(
        alpha: 0.8,
        red: MathUtils.randomRange(0.85, 0.95),
        green: MathUtils.randomRange(0.70, 0.80),
        blue: MathUtils.randomRange(0.30, 0.45),
      ),
      size: MathUtils.randomRange(0.06, 0.10),
      lifetime: 0.4,
      type: ParticleType.smoke, // Renders as circle, floats up
    );
  }

  void _emitRockParticle(Vector2 position) {
    // Grey sharp angular fragments
    final angle = pi / 2 + MathUtils.randomRange(-0.52, 0.52);
    final speed = MathUtils.randomRange(8, 16);
    final grey = MathUtils.randomRange(0.4, 0.65);
    _emit(
      x: position.x + MathUtils.randomRange(-0.3, 0.3),
      y: position.y,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
      color: Color.from(alpha: 1.0, red: grey, green: grey, blue: grey),
      size: MathUtils.randomRange(0.08, 0.18),
      lifetime: 0.5,
      type: ParticleType.dirt,
      angularVelocity: MathUtils.randomRange(-8, 8),
    );
  }

  void _emitObsidianParticle(Vector2 position) {
    // Dark shards
    final angle = pi / 2 + MathUtils.randomRange(-0.52, 0.52);
    final speed = MathUtils.randomRange(10, 18);
    _emit(
      x: position.x + MathUtils.randomRange(-0.2, 0.2),
      y: position.y,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
      color: Color.from(
        alpha: 1.0,
        red: MathUtils.randomRange(0.15, 0.25),
        green: MathUtils.randomRange(0.08, 0.18),
        blue: MathUtils.randomRange(0.20, 0.35),
      ),
      size: MathUtils.randomRange(0.06, 0.14),
      lifetime: 0.4,
      type: ParticleType.dirt,
      angularVelocity: MathUtils.randomRange(-10, 10),
    );
  }

  void _emitOreChipParticle(Vector2 position, Color oreColor) {
    // Glowing colored fragments matching ore color
    final angle = pi / 2 + MathUtils.randomRange(-0.6, 0.6);
    final speed = MathUtils.randomRange(6, 12);
    final brightness = MathUtils.randomRange(0.0, 0.2);
    _emit(
      x: position.x + MathUtils.randomRange(-0.3, 0.3),
      y: position.y,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
      color: Color.from(
        alpha: 1.0,
        red: (oreColor.r + brightness).clamp(0.0, 1.0),
        green: (oreColor.g + brightness).clamp(0.0, 1.0),
        blue: (oreColor.b + brightness).clamp(0.0, 1.0),
      ),
      size: MathUtils.randomRange(0.08, 0.15),
      lifetime: 0.5,
      type: ParticleType.ore,
    );
  }

  void _emitDirtParticle(Vector2 position, Color terrainColor) {
    final angle = pi / 2 + MathUtils.randomRange(-0.52, 0.52);
    final speed = MathUtils.randomRange(8, 14);
    final brightness = MathUtils.randomRange(-0.1, 0.1);

    final r = (terrainColor.r + brightness).clamp(0.0, 1.0);
    final g = (terrainColor.g + brightness).clamp(0.0, 1.0);
    final b = (terrainColor.b + brightness).clamp(0.0, 1.0);

    _emit(
      x: position.x + MathUtils.randomRange(-0.3, 0.3),
      y: position.y,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
      color: Color.from(alpha: 1.0, red: r, green: g, blue: b),
      size: MathUtils.randomRange(0.08, 0.15),
      lifetime: 0.3,
      type: ParticleType.dirt,
    );
  }

  void _emitDrillSpark(Vector2 position, CellType material) {
    final angle = MathUtils.randomRange(-pi, pi);
    final speed = MathUtils.randomRange(15, 30);
    final isObsidian = material == CellType.obsidian;
    _emit(
      x: position.x + MathUtils.randomRange(-0.2, 0.2),
      y: position.y,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
      color: isObsidian
          ? Color.from(
              alpha: 1.0,
              red: MathUtils.randomRange(0.6, 0.8),
              green: MathUtils.randomRange(0.2, 0.4),
              blue: MathUtils.randomRange(0.8, 1.0),
            )
          : Color.from(
              alpha: 1.0,
              red: 1.0,
              green: MathUtils.randomRange(0.7, 1.0),
              blue: MathUtils.randomRange(0.2, 0.5),
            ),
      size: MathUtils.randomRange(0.03, 0.06),
      lifetime: MathUtils.randomRange(0.1, 0.25),
      type: ParticleType.spark,
    );
  }

  /// 2. ORE SPARKLE: When ore cell collected
  void emitOreSparkle(Vector2 position, Color oreColor) {
    for (int i = 0; i < GameConstants.oreSparkleParticles; i++) {
      final angle = (i / GameConstants.oreSparkleParticles) * 2 * pi;
      final speed = MathUtils.randomRange(3, 8);

      _emit(
        x: position.x,
        y: position.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 2,
        color: oreColor,
        size: MathUtils.randomRange(0.1, 0.2),
        lifetime: 0.75,
        type: ParticleType.ore,
      );
    }
  }

  /// Ore pickup effect: animated sprite rising from mined location
  /// Now also emits a spiral of colored particles
  void emitOrePickup(Vector2 position, Color oreColor, String? spritePath) {
    _pickupEffects.add(_PickupEffect(
      x: position.x,
      y: position.y,
      color: oreColor,
      spritePath: spritePath,
    ));

    // Spiral particles rising toward HUD (upward)
    for (int i = 0; i < 8; i++) {
      final t = i / 8.0;
      final spiralAngle = t * 2 * pi;
      final spiralRadius = 0.3 + t * 0.5;
      _emit(
        x: position.x + cos(spiralAngle) * spiralRadius * 0.3,
        y: position.y + sin(spiralAngle) * spiralRadius * 0.3,
        vx: cos(spiralAngle) * 2,
        vy: -8 - t * 4, // Rise upward, faster particles last
        color: Color.from(
          alpha: 1.0,
          red: (oreColor.r + 0.2).clamp(0.0, 1.0),
          green: (oreColor.g + 0.2).clamp(0.0, 1.0),
          blue: (oreColor.b + 0.2).clamp(0.0, 1.0),
        ),
        size: MathUtils.randomRange(0.04, 0.08),
        lifetime: 0.4 + t * 0.3,
        type: ParticleType.spark,
      );
    }
  }

  /// 3. ENGINE EXHAUST: Matches thrust direction
  void emitEngineExhaust(Vector2 position, Vector2 podVelocity,
      [double thrustX = 0, double thrustY = -1]) {
    // Determine exhaust direction (opposite of thrust)
    final exhaustDirX = -thrustX;
    final exhaustDirY = -thrustY;

    // Normalize
    final mag = sqrt(exhaustDirX * exhaustDirX + exhaustDirY * exhaustDirY);
    final normX = mag > 0 ? exhaustDirX / mag : 0.0;
    final normY = mag > 0 ? exhaustDirY / mag : 1.0;

    for (int i = 0; i < 2; i++) {
      final t = _random.nextDouble();
      final color = Color.lerp(
        const Color(0xFFAADDFF),
        const Color(0xFFFF8800),
        t,
      )!;

      // Offset from pod center in exhaust direction
      final offsetX = normX * 1.1;
      final offsetY = normY * 1.1;

      _emit(
        x: position.x + offsetX + MathUtils.randomRange(-0.2, 0.2),
        y: position.y + offsetY + MathUtils.randomRange(-0.2, 0.2),
        vx: normX * 6 + podVelocity.x * 0.3 + MathUtils.randomRange(-0.5, 0.5),
        vy: normY * 6 + podVelocity.y * 0.3 + MathUtils.randomRange(-0.5, 0.5),
        color: color,
        size: MathUtils.randomRange(0.08, 0.15),
        lifetime: 0.2,
        type: ParticleType.exhaust,
      );
    }
  }

  /// 4. EXPLOSION DEBRIS: More varied with fire and smoke
  void emitExplosionDebris(Vector2 position, int radius) {
    final count = MathUtils.randomRangeInt(
      GameConstants.explosionParticlesMin,
      GameConstants.explosionParticlesMax,
    );

    for (int i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = MathUtils.randomRange(5, 25);
      final sizeRoll = _random.nextDouble();

      // Varied sizes: 20% large chunks, 30% medium, 50% tiny
      double particleSize;
      if (sizeRoll > 0.8) {
        particleSize = MathUtils.randomRange(0.3, 0.5); // Large chunks
      } else if (sizeRoll > 0.5) {
        particleSize = MathUtils.randomRange(0.12, 0.25); // Medium
      } else {
        particleSize = MathUtils.randomRange(0.04, 0.12); // Tiny
      }

      _emit(
        x: position.x + MathUtils.randomRange(-0.5, 0.5),
        y: position.y + MathUtils.randomRange(-0.5, 0.5),
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        color: Color.from(
          alpha: 1.0,
          red: MathUtils.randomRange(0.3, 0.6),
          green: MathUtils.randomRange(0.2, 0.4),
          blue: MathUtils.randomRange(0.1, 0.2),
        ),
        size: particleSize,
        lifetime: 1.5,
        angularVelocity: MathUtils.randomRange(-5, 5),
        type: ParticleType.explosion,
      );
    }

    // Fire particles (brief bright flames)
    final fireCount = MathUtils.randomRangeInt(4, 8);
    for (int i = 0; i < fireCount; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = MathUtils.randomRange(2, 8);
      final t = _random.nextDouble();
      _emit(
        x: position.x + MathUtils.randomRange(-0.3, 0.3),
        y: position.y + MathUtils.randomRange(-0.3, 0.3),
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 2,
        color: Color.lerp(
          const Color(0xFFFF4400),
          const Color(0xFFFFFF00),
          t,
        )!,
        size: MathUtils.randomRange(0.15, 0.35),
        lifetime: MathUtils.randomRange(0.3, 0.6),
        type: ParticleType.fire,
      );
    }

    // Smoke trail particles
    final smokeCount = MathUtils.randomRangeInt(3, 5);
    for (int i = 0; i < smokeCount; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = MathUtils.randomRange(1, 4);
      _emit(
        x: position.x + MathUtils.randomRange(-0.5, 0.5),
        y: position.y + MathUtils.randomRange(-0.5, 0.5),
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 1,
        color: Color.from(
          alpha: 0.6,
          red: MathUtils.randomRange(0.3, 0.5),
          green: MathUtils.randomRange(0.3, 0.5),
          blue: MathUtils.randomRange(0.3, 0.5),
        ),
        size: MathUtils.randomRange(0.2, 0.4),
        lifetime: MathUtils.randomRange(0.8, 1.5),
        type: ParticleType.smoke,
      );
    }

    // Flash effect
    _emit(
      x: position.x,
      y: position.y,
      vx: 0,
      vy: 0,
      color: const Color(0xFFFFFF00),
      size: radius.toDouble() * 0.5,
      lifetime: 0.1,
      type: ParticleType.explosion,
    );
  }

  /// Shockwave ring effect for explosions
  void emitShockwaveRing(Vector2 position, double radius) {
    _shockwaves.add(_ShockwaveRing(
      x: position.x,
      y: position.y,
      maxRadius: radius * 1.5,
    ));
  }

  /// 5. LAVA SPLASH: When hitting lava cell
  void emitLavaSplash(Vector2 position) {
    for (int i = 0; i < GameConstants.lavaSplashParticles; i++) {
      final angle = -pi / 2 + MathUtils.randomRange(-0.8, 0.8);
      final speed = MathUtils.randomRange(5, 15);

      _emit(
        x: position.x + MathUtils.randomRange(-0.3, 0.3),
        y: position.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        color: Color.from(
          alpha: 1.0,
          red: 1.0,
          green: MathUtils.randomRange(0.2, 0.5),
          blue: 0.0,
        ),
        size: MathUtils.randomRange(0.1, 0.2),
        lifetime: 0.8,
        type: ParticleType.lava,
      );
    }
  }

  /// 6. WATER SPLASH: When pod contacts water table depth
  void emitWaterSplash(Vector2 position) {
    for (int i = 0; i < 12; i++) {
      final angle = -pi / 2 + MathUtils.randomRange(-1.0, 1.0);
      final speed = MathUtils.randomRange(4, 12);
      _emit(
        x: position.x + MathUtils.randomRange(-0.4, 0.4),
        y: position.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        color: Color.from(
          alpha: 0.7,
          red: MathUtils.randomRange(0.3, 0.5),
          green: MathUtils.randomRange(0.5, 0.7),
          blue: MathUtils.randomRange(0.8, 1.0),
        ),
        size: MathUtils.randomRange(0.08, 0.18),
        lifetime: 0.6,
        type: ParticleType.splash,
      );
    }
  }

  /// 7. AMBIENT DEPTH PARTICLES: Biome-appropriate floating particles
  void emitAmbientParticles(Vector2 podPosition, double depthFeet) {
    // Rate limit: only emit occasionally
    if (_random.nextDouble() > 0.15) return;

    if (depthFeet < GameConstants.sandLayerEnd) {
      // Near surface: floating dust motes
      _emitAmbientDustMote(podPosition);
    } else if (depthFeet >= GameConstants.rockEnd &&
        depthFeet < GameConstants.volcanicEnd) {
      // Volcanic zone: ember/ash particles
      _emitVolcanicEmber(podPosition);
    } else if (depthFeet >= GameConstants.hellStart) {
      // Hell zone: soul wisps
      _emitSoulWisp(podPosition);
    }
  }

  void _emitAmbientDustMote(Vector2 center) {
    _emit(
      x: center.x + MathUtils.randomRange(-8, 8),
      y: center.y + MathUtils.randomRange(-6, 6),
      vx: MathUtils.randomRange(-0.3, 0.3),
      vy: MathUtils.randomRange(-0.2, 0.2),
      color: Color.from(
        alpha: 0.15,
        red: 1.0,
        green: MathUtils.randomRange(0.9, 1.0),
        blue: MathUtils.randomRange(0.7, 0.9),
      ),
      size: MathUtils.randomRange(0.02, 0.05),
      lifetime: MathUtils.randomRange(3, 6),
      type: ParticleType.ambient,
    );
  }

  void _emitVolcanicEmber(Vector2 center) {
    _emit(
      x: center.x + MathUtils.randomRange(-10, 10),
      y: center.y + MathUtils.randomRange(-8, 8),
      vx: MathUtils.randomRange(-0.5, 0.5),
      vy: MathUtils.randomRange(-2, -0.5), // Float upward
      color: Color.from(
        alpha: 0.9,
        red: 1.0,
        green: MathUtils.randomRange(0.3, 0.6),
        blue: MathUtils.randomRange(0.0, 0.1),
      ),
      size: MathUtils.randomRange(0.03, 0.06),
      lifetime: MathUtils.randomRange(1.5, 3),
      type: ParticleType.fire,
    );
  }

  void _emitSoulWisp(Vector2 center) {
    // Eerie purple-white wisps that drift slowly
    final angle = _random.nextDouble() * 2 * pi;
    _emit(
      x: center.x + MathUtils.randomRange(-10, 10),
      y: center.y + MathUtils.randomRange(-8, 8),
      vx: cos(angle) * MathUtils.randomRange(0.2, 0.8),
      vy: sin(angle) * MathUtils.randomRange(0.2, 0.8) - 0.5,
      color: Color.from(
        alpha: 0.3,
        red: MathUtils.randomRange(0.6, 0.9),
        green: MathUtils.randomRange(0.3, 0.5),
        blue: MathUtils.randomRange(0.8, 1.0),
      ),
      size: MathUtils.randomRange(0.04, 0.08),
      lifetime: MathUtils.randomRange(2, 5),
      type: ParticleType.ambient,
    );
  }

  /// 8. LANDING DUST: Burst of biome-colored dust when landing
  void emitLandingDust(Vector2 position, double impactSpeed, double depthFeet) {
    // Scale particle count with landing velocity (3-12 particles)
    final count = (impactSpeed * 1.5).clamp(3.0, 12.0).toInt();

    // Biome-colored dust
    final Color baseColor;
    if (depthFeet < GameConstants.sandLayerEnd) {
      baseColor = const Color(0xFF8B6B3D); // Sandy brown
    } else if (depthFeet < GameConstants.topsoilEnd) {
      baseColor = const Color(0xFF5C4A38); // Dark brown
    } else if (depthFeet < GameConstants.rockEnd) {
      baseColor = const Color(0xFF787878); // Gray rock
    } else if (depthFeet < GameConstants.volcanicEnd) {
      baseColor = const Color(0xFFAA4422); // Red volcanic
    } else {
      baseColor = const Color(0xFF3A1515); // Dark crimson
    }

    for (int i = 0; i < count; i++) {
      final angle = pi + MathUtils.randomRange(-0.6, 0.6); // Spray sideways
      final side = (i % 2 == 0) ? 1.0 : -1.0;
      final speed = MathUtils.randomRange(2, 5) * (impactSpeed / 8.0).clamp(0.5, 2.0);
      final brightness = MathUtils.randomRange(-0.05, 0.05);

      _emit(
        x: position.x + side * MathUtils.randomRange(0.2, 0.8),
        y: position.y + 1.0, // At feet level
        vx: side * speed * cos(angle).abs(),
        vy: -MathUtils.randomRange(1, 3), // Slight upward drift
        color: Color.from(
          alpha: 0.7,
          red: (baseColor.r + brightness).clamp(0.0, 1.0),
          green: (baseColor.g + brightness).clamp(0.0, 1.0),
          blue: (baseColor.b + brightness).clamp(0.0, 1.0),
        ),
        size: MathUtils.randomRange(0.06, 0.14),
        lifetime: MathUtils.randomRange(0.3, 0.6),
        type: ParticleType.smoke,
      );
    }
  }

  /// 9. MOVEMENT DUST: Small dust trail when moving on ground
  void emitMovementDust(Vector2 position, double horizSpeed, double depthFeet) {
    // Rate-limit: only emit when moving meaningfully
    if (horizSpeed.abs() < 1.0) return;
    if (_random.nextDouble() > (horizSpeed.abs() / 6.0).clamp(0.0, 0.8)) return;

    // Biome-colored dust (same palette as landing)
    final Color baseColor;
    if (depthFeet < GameConstants.sandLayerEnd) {
      baseColor = const Color(0xFF8B6B3D);
    } else if (depthFeet < GameConstants.topsoilEnd) {
      baseColor = const Color(0xFF5C4A38);
    } else if (depthFeet < GameConstants.rockEnd) {
      baseColor = const Color(0xFF787878);
    } else if (depthFeet < GameConstants.volcanicEnd) {
      baseColor = const Color(0xFFAA4422);
    } else {
      baseColor = const Color(0xFF3A1515);
    }

    // Emit behind the robot (opposite to movement direction)
    final behind = horizSpeed > 0 ? -1.0 : 1.0;
    _emit(
      x: position.x + behind * MathUtils.randomRange(0.3, 0.7),
      y: position.y + 1.0 + MathUtils.randomRange(-0.1, 0.1),
      vx: behind * MathUtils.randomRange(0.5, 1.5),
      vy: MathUtils.randomRange(-0.5, -0.2),
      color: baseColor.withValues(alpha: 0.4),
      size: MathUtils.randomRange(0.04, 0.08),
      lifetime: MathUtils.randomRange(0.2, 0.4),
      type: ParticleType.smoke,
    );
  }

  /// 10. CAVE DUST: Initialize ambient floating dust motes
  void initializeCaveDust(double viewWidth, double viewHeight) {
    if (_dustInitialized) return;
    _dustInitialized = true;

    final count = MathUtils.randomRangeInt(
      GameConstants.caveDustParticlesMin,
      GameConstants.caveDustParticlesMax,
    );

    for (int i = 0; i < count; i++) {
      _dustParticles.add(Particle(
        x: MathUtils.randomRange(-viewWidth, viewWidth),
        y: MathUtils.randomRange(-viewHeight, viewHeight),
        vx: MathUtils.randomRange(-0.2, 0.2),
        vy: MathUtils.randomRange(-0.1, 0.1),
        color: const Color(0xFFFFFFFF),
        size: MathUtils.randomRange(0.02, 0.05),
        life: MathUtils.randomRange(5, 15),
      ));
    }
  }

  void _resetDustParticle(Particle dust) {
    dust.x = MathUtils.randomRange(-20, 20);
    dust.y = MathUtils.randomRange(-15, 15);
    dust.vx = MathUtils.randomRange(-0.2, 0.2);
    dust.vy = MathUtils.randomRange(-0.1, 0.1);
    dust.life = MathUtils.randomRange(5, 15);
    dust.maxLife = dust.life;
  }

  /// Push dust particles away from a point (robot movement effect)
  void pushDust(Vector2 position, double force) {
    for (final dust in _dustParticles) {
      final dx = dust.x - position.x;
      final dy = dust.y - position.y;
      final distSq = dx * dx + dy * dy;
      if (distSq < 4 && distSq > 0.01) {
        final dist = sqrt(distSq);
        dust.vx += (dx / dist) * force * 0.1;
        dust.vy += (dy / dist) * force * 0.1;
      }
    }
  }

  /// Clear all active particles
  void clear() {
    // Pooled particles will be recycled naturally
  }

  /// Number of active particles (pooled + dust)
  int get activeCount =>
      _pool.activeCount +
      _dustParticles.length +
      _pickupEffects.length +
      _shockwaves.length;
}
