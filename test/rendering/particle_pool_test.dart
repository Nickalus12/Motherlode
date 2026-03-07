@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:motherlode/rendering/particle_pool.dart';

void main() {
  // 1. Pool never allocates new objects after init
  test('1. Pool pre-allocates all particles at init', () {
    final pool = ParticlePool();
    expect(pool.capacity, equals(ParticlePool.poolSize));
    expect(pool.activeCount, equals(0));

    // Acquire some particles
    for (int i = 0; i < 100; i++) {
      pool.acquire();
    }
    expect(pool.activeCount, equals(100));
    // Pool capacity unchanged (no new allocations)
    expect(pool.capacity, equals(ParticlePool.poolSize));
  });

  // 2. Acquiring 501 particles wraps around and recycles oldest
  test('2. Round-robin wraps and recycles oldest particles', () {
    final pool = ParticlePool();

    // Fill the entire pool
    for (int i = 0; i < ParticlePool.poolSize; i++) {
      final p = pool.acquire();
      p.x = i.toDouble();
      p.lifetime = 10.0; // Long lifetime so they stay active
    }

    expect(pool.activeCount, equals(ParticlePool.poolSize));

    // Acquire one more — should recycle the first particle
    final recycled = pool.acquire();
    recycled.lifetime = 10.0;

    // Active count should still be poolSize (recycled one, created one)
    expect(pool.activeCount, equals(ParticlePool.poolSize));
  });

  // 3. Active count never exceeds pool size
  test('3. Active count never exceeds pool size', () {
    final pool = ParticlePool();

    for (int i = 0; i < ParticlePool.poolSize * 3; i++) {
      final p = pool.acquire();
      p.lifetime = 100.0;
    }

    expect(pool.activeCount, lessThanOrEqualTo(ParticlePool.poolSize));
  });

  // 4. Positions update correctly each dt
  test('4. Particle positions update correctly', () {
    final pool = ParticlePool();
    final p = pool.acquire();
    p.x = 10.0;
    p.y = 20.0;
    p.vx = 5.0;
    p.vy = -3.0;
    p.lifetime = 1.0;
    p.type = ParticleType.ore; // Not affected by gravity

    pool.update(0.5);

    expect(p.x, closeTo(12.5, 0.01)); // 10 + 5*0.5
    expect(p.y, closeTo(18.5, 0.01)); // 20 + (-3)*0.5
    expect(p.age, closeTo(0.5, 0.01));
  });

  // 5. Particles deactivate when age >= lifetime
  test('5. Particles deactivate when expired', () {
    final pool = ParticlePool();
    final p = pool.acquire();
    p.lifetime = 0.3;

    expect(p.active, isTrue);

    pool.update(0.1);
    expect(p.active, isTrue);

    pool.update(0.1);
    expect(p.active, isTrue);

    pool.update(0.15); // Total age now 0.35 >= 0.3
    expect(p.active, isFalse);
  });

  // 6. Dirt particles accelerate downward (gravity applied)
  test('6. Dirt particles have gravity applied', () {
    final pool = ParticlePool();
    final p = pool.acquire();
    p.x = 0;
    p.y = 0;
    p.vx = 0;
    p.vy = 0;
    p.lifetime = 2.0;
    p.type = ParticleType.dirt;

    pool.update(1.0);

    // vy should increase due to gravity (980 * dt)
    expect(p.vy, greaterThan(0), reason: 'Dirt particle should fall down');
    expect(p.vy, closeTo(980.0, 1.0));
  });

  // 7. Engine exhaust particles do NOT accelerate downward
  test('7. Exhaust particles have no gravity', () {
    final pool = ParticlePool();
    final p = pool.acquire();
    p.x = 0;
    p.y = 0;
    p.vx = 0;
    p.vy = 5.0;
    p.lifetime = 2.0;
    p.type = ParticleType.exhaust;

    pool.update(1.0);

    // vy should remain constant (no gravity for exhaust)
    expect(p.vy, closeTo(5.0, 0.01),
        reason: 'Exhaust particle should not be affected by gravity');
  });

  // 8. PooledParticle.lifeRatio edge cases
  test('8. lifeRatio clamps and handles edge cases', () {
    final p = PooledParticle();

    // Fresh particle
    p.lifetime = 1.0;
    p.age = 0.0;
    expect(p.lifeRatio, 1.0);

    // Half-life
    p.age = 0.5;
    expect(p.lifeRatio, closeTo(0.5, 0.001));

    // Expired
    p.age = 2.0;
    expect(p.lifeRatio, 0.0);

    // Zero lifetime
    p.lifetime = 0.0;
    p.age = 0.0;
    expect(p.lifeRatio, 0.0);
  });

  // 9. Reset clears mutable state
  test('9. PooledParticle reset clears state', () {
    final p = PooledParticle();
    p.age = 5.0;
    p.active = true;
    p.rotation = 3.14;
    p.angularVelocity = 2.0;
    p.reset();
    expect(p.age, 0.0);
    expect(p.active, isFalse);
    expect(p.rotation, 0.0);
    expect(p.angularVelocity, 0.0);
  });

  // 10. Angular velocity updates rotation
  test('10. Angular velocity updates rotation', () {
    final pool = ParticlePool();
    final p = pool.acquire();
    p.lifetime = 5.0;
    p.angularVelocity = 3.14;
    p.rotation = 0.0;
    p.type = ParticleType.exhaust; // No gravity interference

    pool.update(1.0);
    expect(p.rotation, closeTo(3.14, 0.01));
  });

  // 11. Lava and explosion particles get gravity
  test('11. Lava and explosion particles have gravity', () {
    final pool = ParticlePool();

    final lava = pool.acquire();
    lava.lifetime = 5.0;
    lava.type = ParticleType.lava;
    lava.vy = 0;

    final explosion = pool.acquire();
    explosion.lifetime = 5.0;
    explosion.type = ParticleType.explosion;
    explosion.vy = 0;

    pool.update(0.1);
    expect(lava.vy, greaterThan(0));
    expect(explosion.vy, greaterThan(0));
  });

  // 12. Dust and ore particles do NOT get gravity
  test('12. Dust and ore particles have no gravity', () {
    final pool = ParticlePool();

    final dust = pool.acquire();
    dust.lifetime = 5.0;
    dust.type = ParticleType.dust;
    dust.vy = 0;

    final ore = pool.acquire();
    ore.lifetime = 5.0;
    ore.type = ParticleType.ore;
    ore.vy = 0;

    pool.update(0.1);
    expect(dust.vy, 0.0);
    expect(ore.vy, 0.0);
  });

  // 13. Acquire prefers dead particles over shortest-remaining
  test('13. Acquire prefers dead particles over recycling', () {
    final pool = ParticlePool();

    // Acquire two particles
    final p1 = pool.acquire();
    p1.lifetime = 0.05;
    final p2 = pool.acquire();
    p2.lifetime = 10.0;

    // Kill p1
    pool.update(0.1);
    expect(p1.active, isFalse);
    expect(p2.active, isTrue);
    expect(pool.activeCount, 1);

    // Next acquire should reuse dead p1, not recycle living p2
    final p3 = pool.acquire();
    expect(p3.active, isTrue);
    expect(pool.activeCount, 2);
  });

  // 14. ParticleType enum completeness
  test('14. All expected ParticleType values exist', () {
    expect(ParticleType.values.length, 12);
    expect(
        ParticleType.values,
        containsAll([
          ParticleType.dirt,
          ParticleType.debris,
          ParticleType.ore,
          ParticleType.exhaust,
          ParticleType.lava,
          ParticleType.explosion,
          ParticleType.dust,
          ParticleType.fire,
          ParticleType.smoke,
          ParticleType.spark,
          ParticleType.ambient,
          ParticleType.splash,
        ]));
  });
}
