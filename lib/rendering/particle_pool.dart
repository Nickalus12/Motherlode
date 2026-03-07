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
  fire,
  smoke,
  spark,
  ambient,
  splash,
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
  double get lifeRatio =>
      lifetime > 0 ? ((lifetime - age) / lifetime).clamp(0.0, 1.0) : 0.0;

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
  static const int poolSize = 600;

  final List<PooledParticle> _particles =
      List.generate(poolSize, (_) => PooledParticle());
  int _nextIndex = 0;

  /// Acquire a particle from the pool.
  /// Priority: recycle dead particles first, then the particle with the
  /// shortest remaining life (most about to die) to avoid stealing from
  /// long-lived effects like explosions.
  PooledParticle acquire() {
    // First pass: find a dead particle starting from _nextIndex
    for (int i = 0; i < poolSize; i++) {
      final idx = (_nextIndex + i) % poolSize;
      if (!_particles[idx].active) {
        _nextIndex = (idx + 1) % poolSize;
        final particle = _particles[idx];
        particle.reset();
        particle.active = true;
        return particle;
      }
    }

    // All particles active — recycle the one closest to death
    int bestIdx = _nextIndex;
    double bestRemaining = double.infinity;
    for (int i = 0; i < poolSize; i++) {
      final p = _particles[i];
      final remaining = p.lifetime - p.age;
      if (remaining < bestRemaining) {
        bestRemaining = remaining;
        bestIdx = i;
      }
    }

    _nextIndex = (bestIdx + 1) % poolSize;
    final particle = _particles[bestIdx];
    particle.reset();
    particle.active = true;
    return particle;
  }

  /// Cached list of active particles, rebuilt each update() to avoid
  /// creating a new filtered iterable every render frame.
  final List<PooledParticle> _activeList = [];

  /// Get all currently active particles (cached from last update)
  List<PooledParticle> get activeParticles => _activeList;

  /// Update all active particles each frame and rebuild active list cache.
  void update(double dt) {
    _activeList.clear();
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

      // Apply gravity to physical particle types
      if (p.type == ParticleType.dirt ||
          p.type == ParticleType.debris ||
          p.type == ParticleType.lava ||
          p.type == ParticleType.explosion ||
          p.type == ParticleType.spark ||
          p.type == ParticleType.splash) {
        p.vy += 980 * dt; // pixel gravity
      } else if (p.type == ParticleType.fire || p.type == ParticleType.smoke) {
        p.vy -= 200 * dt; // float upward
      }

      _activeList.add(p);
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
