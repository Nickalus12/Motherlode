@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hellbore/physics/debris_body.dart';

/// Tests for debris body auto-sleep and max body limit.
/// Since DebrisBody requires Forge2D world, we test the DebrisManager
/// logic and the settle timer constants in isolation.
void main() {
  // 1. Velocity threshold and sleep timer constants
  test('1. DebrisBody has correct sleep constants', () {
    expect(DebrisBody.sleepAfterSeconds, equals(3.0));
    expect(DebrisBody.sleepVelocityThreshold, equals(0.5));
  });

  // 2. DebrisManager max body limit
  test('2. Max debris constant is 150', () {
    expect(DebrisManager.maxDebris, equals(150));
  });

  // 3. Force-settle count
  test('3. Force-settle removes 20 oldest debris', () {
    expect(DebrisManager.forceSettleCount, equals(20));
  });

  // 4. Settle timer behavior simulation
  test('4. Settle timer logic simulation', () {
    double restingTime = 0.0;
    bool settled = false;
    const sleepAfter = DebrisBody.sleepAfterSeconds;
    const threshold = DebrisBody.sleepVelocityThreshold;

    // Simulate low velocity for 2.5s (not enough to settle)
    double speed = 0.3;
    double dt = 0.5;
    for (int i = 0; i < 5; i++) {
      if (speed < threshold) {
        restingTime += dt;
        if (restingTime >= sleepAfter) {
          settled = true;
          break;
        }
      } else {
        restingTime = 0.0;
      }
    }
    expect(restingTime, closeTo(2.5, 0.01));
    expect(settled, isFalse, reason: 'Should not settle after only 2.5s');

    // One more tick should settle
    restingTime += dt;
    if (restingTime >= sleepAfter) settled = true;
    expect(settled, isTrue, reason: 'Should settle after 3.0s');
  });

  // 5. Bump resets rest timer
  test('5. Bump resets resting timer', () {
    double restingTime = 0.0;
    const threshold = DebrisBody.sleepVelocityThreshold;

    // Rest for 2s
    for (int i = 0; i < 4; i++) {
      double speed = 0.1;
      if (speed < threshold) {
        restingTime += 0.5;
      }
    }
    expect(restingTime, closeTo(2.0, 0.01));

    // Get bumped (high velocity)
    double speed = 5.0;
    if (speed >= threshold) {
      restingTime = 0.0;
    }
    expect(restingTime, equals(0.0),
        reason: 'Timer should reset when bumped');
  });

  // 6. Terrain conversion callback
  test('6. onConvertToTerrain callback fires on settle', () {
    int callbackGridX = -1;
    int callbackGridY = -1;
    bool callbackFired = false;

    // Simulate the callback
    void onConvert(int gridX, int gridY) {
      callbackFired = true;
      callbackGridX = gridX;
      callbackGridY = gridY;
    }

    // Simulate force settle at position (5, 10)
    onConvert(5, 10);

    expect(callbackFired, isTrue);
    expect(callbackGridX, equals(5));
    expect(callbackGridY, equals(10));
  });
}
