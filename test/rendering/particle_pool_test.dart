@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hellbore/rendering/particle_pool.dart';

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
}
