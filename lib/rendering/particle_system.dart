import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import 'package:hellbore/utils/constants.dart';
import 'package:hellbore/utils/math_utils.dart';

/// Individual particle with position, velocity, color, lifetime
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

  /// Remaining life ratio (1.0 = fresh, 0.0 = dead)
  double get lifeRatio => (life / maxLife).clamp(0.0, 1.0);

  /// Whether this particle has expired
  bool get isDead => life <= 0;

  /// Update particle physics
  void update(double dt) {
    life -= dt;
    x += vx * dt;
    y += vy * dt;
    rotation += angularVelocity * dt;

    if (affectedByGravity) {
      vy += GameConstants.gravity * 30 * dt; // Scaled for visual effect
    }
  }
}

/// Particle system managing all particle emitters and rendering
class ParticleSystem extends Component {
  final List<Particle> _particles = [];
  final Random _random = Random();

  // Ambient dust particles (persistent)
  final List<Particle> _dustParticles = [];
  bool _dustInitialized = false;

  @override
  void update(double dt) {
    super.update(dt);

    // Update active particles
    _particles.removeWhere((p) {
      p.update(dt);
      return p.isDead;
    });

    // Update dust
    for (final dust in _dustParticles) {
      dust.update(dt);
      if (dust.isDead) {
        _resetDustParticle(dust);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Render active particles
    for (final p in _particles) {
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
      paint.color = Colors.white.withValues(alpha: d.lifeRatio * 0.08);
      canvas.drawCircle(Offset(d.x, d.y), d.size, paint);
    }
  }

  // ─── Emitter Methods ───

  /// 1. DRILL PARTICLES: When drilling
  void emitDrillParticles(Vector2 position, Color terrainColor) {
    final count = MathUtils.randomRangeInt(
      GameConstants.drillParticlesMin,
      GameConstants.drillParticlesMax,
    );

    for (int i = 0; i < count; i++) {
      final angle = pi / 2 + MathUtils.randomRange(-0.52, 0.52); // ±30°
      final speed = MathUtils.randomRange(8, 14);
      final brightness = MathUtils.randomRange(-0.1, 0.1);

      // Slight color variation
      final r = (terrainColor.r + brightness).clamp(0.0, 1.0);
      final g = (terrainColor.g + brightness).clamp(0.0, 1.0);
      final b = (terrainColor.b + brightness).clamp(0.0, 1.0);

      _particles.add(Particle(
        x: position.x + MathUtils.randomRange(-0.3, 0.3),
        y: position.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        color: Color.from(alpha: 1.0, red: r, green: g, blue: b),
        size: MathUtils.randomRange(0.08, 0.15),
        life: 0.3,
        affectedByGravity: true,
      ));
    }
  }

  /// 2. ORE SPARKLE: When ore cell collected
  void emitOreSparkle(Vector2 position, Color oreColor) {
    for (int i = 0; i < GameConstants.oreSparkleParticles; i++) {
      final angle = (i / GameConstants.oreSparkleParticles) * 2 * pi;
      final speed = MathUtils.randomRange(3, 8);

      _particles.add(Particle(
        x: position.x,
        y: position.y,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 2, // Slight upward float
        color: oreColor,
        size: MathUtils.randomRange(0.1, 0.2),
        life: 0.5,
      ));
    }
  }

  /// 3. ENGINE EXHAUST: While thrusting upward
  void emitEngineExhaust(Vector2 position, Vector2 podVelocity) {
    for (int i = 0; i < 3; i++) {
      final t = _random.nextDouble();
      final color = Color.lerp(
        const Color(0xFFAADDFF), // Blue-white
        const Color(0xFFFF8800), // Orange
        t,
      )!;

      _particles.add(Particle(
        x: position.x + MathUtils.randomRange(-0.2, 0.2),
        y: position.y + 1.1,
        vx: podVelocity.x * 0.3 + MathUtils.randomRange(-0.5, 0.5),
        vy: 6 + podVelocity.y * 0.3,
        color: color,
        size: MathUtils.randomRange(0.08, 0.15),
        life: 0.2,
      ));
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

      _particles.add(Particle(
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
        life: 1.5,
        angularVelocity: MathUtils.randomRange(-5, 5),
        affectedByGravity: true,
      ));
    }

    // Flash effect
    _particles.add(Particle(
      x: position.x,
      y: position.y,
      vx: 0,
      vy: 0,
      color: const Color(0xFFFFFF00),
      size: radius.toDouble() * 0.5,
      life: 0.1,
    ));
  }

  /// 5. LAVA SPLASH: When hitting lava cell
  void emitLavaSplash(Vector2 position) {
    for (int i = 0; i < GameConstants.lavaSplashParticles; i++) {
      final angle = -pi / 2 + MathUtils.randomRange(-0.8, 0.8);
      final speed = MathUtils.randomRange(5, 15);

      _particles.add(Particle(
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
        life: 0.8,
        affectedByGravity: true,
      ));
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
        color: Colors.white,
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
    _particles.clear();
  }

  /// Number of active particles
  int get activeCount => _particles.length;
}
