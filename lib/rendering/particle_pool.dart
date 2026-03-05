import 'dart:ui';

/// Types of particles in the system
enum ParticleType {
  dirt,
  debris,
  ore,
  exhaust,
  lava,
  explosion,
  dust,
}

/// Pooled particle with mutable fields — no allocations after init
class PooledParticle {
  double x = 0.0;
  double y = 0.0;
  double vx = 0.0;
  double vy = 0.0;
  Color color = const Color(0xFFFFFFFF);
  double size = 4.0;
  double lifetime = 0.3;
  double age = 0.0;
  bool active = false;
  ParticleType type = ParticleType.dirt;
  double angularVelocity = 0.0;
  double rotation = 0.0;

  /// Remaining life ratio (1.0 = fresh, 0.0 = dead)
  double get lifeRatio => lifetime > 0 ? ((lifetime - age) / lifetime).clamp(0.0, 1.0) : 0.0;

  void reset() {
    age = 0.0;
    active = false;
    rotation = 0.0;
    angularVelocity = 0.0;
  }
}

/// Pre-allocated particle pool with round-robin acquisition.
/// Zero heap allocation after initialization.
class ParticlePool {
  static const int poolSize = 500;

  final List<PooledParticle> _particles =
      List.generate(poolSize, (_) => PooledParticle());
  int _nextIndex = 0;

  /// Acquire a particle from the pool.
  /// Round-robin: if the particle at nextIndex is still active, it gets recycled.
  PooledParticle acquire() {
    final particle = _particles[_nextIndex];
    particle.reset();
    particle.active = true;
    _nextIndex = (_nextIndex + 1) % poolSize;
    return particle;
  }

  /// Get all currently active particles (creates a filtered view)
  Iterable<PooledParticle> get activeParticles =>
      _particles.where((p) => p.active);

  /// Update all active particles each frame
  void update(double dt) {
    for (final p in _particles) {
      if (!p.active) continue;
      p.age += dt;
      if (p.age >= p.lifetime) {
        p.active = false;
        continue;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rotation += p.angularVelocity * dt;

      // Apply gravity to dirt/debris particles only
      if (p.type == ParticleType.dirt || p.type == ParticleType.debris) {
        p.vy += 980 * dt; // pixel gravity
      }
    }
  }

  /// Number of active particles
  int get activeCount {
    int count = 0;
    for (final p in _particles) {
      if (p.active) count++;
    }
    return count;
  }

  /// Total pool capacity
  int get capacity => poolSize;
}
