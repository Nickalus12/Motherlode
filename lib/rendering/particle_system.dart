import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart' hide Vector2;
import 'package:flame_forge2d/flame_forge2d.dart'
    hide ParticleSystem, ParticleType;

import 'package:motherlode/rendering/item_sprite_manager.dart';
import 'package:motherlode/rendering/particle_pool.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/utils/math_utils.dart';

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
      vy += GameConstants.gravity * 30 * dt;
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

/// Particle system using a pre-allocated object pool for zero-allocation
/// particle emission during gameplay.
class ParticleSystem extends Component {
  final ParticlePool _pool = ParticlePool();
  final Random _random = Random();
  final List<_PickupEffect> _pickupEffects = [];

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

  /// 1. DRILL PARTICLES: When drilling
  void emitDrillParticles(Vector2 position, Color terrainColor) {
    final count = MathUtils.randomRangeInt(
      GameConstants.drillParticlesMin,
      GameConstants.drillParticlesMax,
    );

    for (int i = 0; i < count; i++) {
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
        lifetime: 0.5,
        type: ParticleType.ore,
      );
    }
  }

  /// Ore pickup effect: animated sprite rising from mined location
  void emitOrePickup(Vector2 position, Color oreColor, String? spritePath) {
    _pickupEffects.add(_PickupEffect(
      x: position.x,
      y: position.y,
      color: oreColor,
      spritePath: spritePath,
    ));
  }

  /// 3. ENGINE EXHAUST: While thrusting upward
  void emitEngineExhaust(Vector2 position, Vector2 podVelocity) {
    for (int i = 0; i < 3; i++) {
      final t = _random.nextDouble();
      final color = Color.lerp(
        const Color(0xFFAADDFF),
        const Color(0xFFFF8800),
        t,
      )!;

      _emit(
        x: position.x + MathUtils.randomRange(-0.2, 0.2),
        y: position.y + 1.1,
        vx: podVelocity.x * 0.3 + MathUtils.randomRange(-0.5, 0.5),
        vy: 6 + podVelocity.y * 0.3,
        color: color,
        size: MathUtils.randomRange(0.08, 0.15),
        lifetime: 0.2,
        type: ParticleType.exhaust,
      );
    }
  }

  /// 4. EXPLOSION DEBRIS: On dynamite/explosive
  void emitExplosionDebris(Vector2 position, int radius) {
    final count = MathUtils.randomRangeInt(
      GameConstants.explosionParticlesMin,
      GameConstants.explosionParticlesMax,
    );

    for (int i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = MathUtils.randomRange(5, 25);
      final isLarge = _random.nextDouble() > 0.7;

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
        size: isLarge
            ? MathUtils.randomRange(0.2, 0.4)
            : MathUtils.randomRange(0.05, 0.15),
        lifetime: 1.5,
        angularVelocity: MathUtils.randomRange(-5, 5),
        type: ParticleType.explosion,
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

  /// 6. CAVE DUST: Initialize ambient floating dust motes
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

  /// Push dust particles away from a point (pod movement effect)
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
      _pool.activeCount + _dustParticles.length + _pickupEffects.length;
}
