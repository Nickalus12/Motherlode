import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Touch/keyboard input → thrust/drill commands
///
/// Supports:
/// - Touch: directional zones on screen (left/right halves for horizontal,
///   top half for thrust, bottom half for drill)
/// - Keyboard: Arrow keys or WASD
class PodController extends Component
    with KeyboardHandler, HasGameReference<MotherlodeGame> {
  final Pod pod;

  // Touch zones (relative to viewport)

  // Active touch tracking
  final Map<int, Vector2> _activeTouches = {};

  PodController({required this.pod});

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Movement keys
    pod.thrustUp = keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW);
    pod.thrustLeft = keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);
    pod.thrustRight = keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);
    pod.drillDown = keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS);

    // Consumable hotkeys
    if (event is KeyDownEvent) {
      _handleConsumableKey(event.logicalKey);
    }

    return true;
  }

  /// Handle touch input for mobile controls
  void handleTouchDown(int pointerId, Vector2 position) {
    _activeTouches[pointerId] = position;
    _updateTouchInput();
  }

  void handleTouchMove(int pointerId, Vector2 position) {
    _activeTouches[pointerId] = position;
    _updateTouchInput();
  }

  void handleTouchUp(int pointerId) {
    _activeTouches.remove(pointerId);
    _updateTouchInput();
  }

  void _updateTouchInput() {
    // Reset all inputs
    pod.thrustUp = false;
    pod.thrustLeft = false;
    pod.thrustRight = false;
    pod.drillDown = false;

    final viewportSize = game.camera.viewport.size;
    final centerX = viewportSize.x / 2;
    final centerY = viewportSize.y / 2;

    for (final touch in _activeTouches.values) {
      final relX = touch.x / viewportSize.x;
      final relY = touch.y / viewportSize.y;

      final dx = touch.x - centerX;
      final dy = touch.y - centerY;

      // Use angular zones instead of axis-dominant for more responsive controls.
      // Dead zone in the center (10% of screen size)
      final deadZone = viewportSize.x * 0.08;
      final dist = (dx * dx + dy * dy);
      if (dist < deadZone * deadZone) continue;

      // Use angle-based zones with overlap for simultaneous inputs
      // Top zone: thrust up (upper 120 degrees)
      if (dy < -viewportSize.y * 0.08) {
        pod.thrustUp = true;
      }

      // Bottom zone: drill down (lower 120 degrees)
      if (dy > viewportSize.y * 0.08) {
        pod.drillDown = true;
      }

      // Left zone: thrust left (with generous overlap)
      if (dx < -viewportSize.x * 0.1) {
        pod.thrustLeft = true;
      }

      // Right zone: thrust right
      if (dx > viewportSize.x * 0.1) {
        pod.thrustRight = true;
      }

      // Corner combos (override for clarity)
      if (relX < 0.25 && relY < 0.25) {
        pod.thrustUp = true;
        pod.thrustLeft = true;
        pod.drillDown = false;
      } else if (relX > 0.75 && relY < 0.25) {
        pod.thrustUp = true;
        pod.thrustRight = true;
        pod.drillDown = false;
      } else if (relX < 0.25 && relY > 0.75) {
        pod.drillDown = true;
        pod.thrustLeft = true;
        pod.thrustUp = false;
      } else if (relX > 0.75 && relY > 0.75) {
        pod.drillDown = true;
        pod.thrustRight = true;
        pod.thrustUp = false;
      }
    }
  }

  void _handleConsumableKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyX) {
      _useDynamite();
    } else if (key == LogicalKeyboardKey.keyC) {
      _usePlasticExplosive();
    } else if (key == LogicalKeyboardKey.keyF) {
      _useReserveFuel();
    } else if (key == LogicalKeyboardKey.keyR) {
      _useNanobots();
    } else if (key == LogicalKeyboardKey.keyQ) {
      _useTeleporter();
    } else if (key == LogicalKeyboardKey.keyM) {
      _useTransmitter();
    }
  }

  void _useDynamite() {
    if (game.dynamiteCount <= 0) return;
    game.dynamiteCount--;
    game.earthquakeSystem.triggerExplosion(
      pod.position,
      GameConstants.dynamiteRadius,
      GameConstants.dynamiteForce,
    );
  }

  void _usePlasticExplosive() {
    if (game.plasticExplosiveCount <= 0) return;
    game.plasticExplosiveCount--;
    game.earthquakeSystem.triggerExplosion(
      pod.position,
      GameConstants.plasticExplosiveRadius,
      GameConstants.plasticExplosiveForce,
    );
  }

  void _useReserveFuel() {
    if (game.reserveFuelCount <= 0) return;
    game.reserveFuelCount--;
    game.fuelSystem.addFuel(GameConstants.reserveFuelAmount);
  }

  void _useNanobots() {
    if (game.nanobotCount <= 0) return;
    game.nanobotCount--;
    game.hullSystem.repair(GameConstants.nanobotHealAmount);
  }

  void _useTeleporter() {
    if (game.teleporterCount <= 0) return;
    game.teleporterCount--;
    // Random surface position
    pod.body.setTransform(
      Vector2(pod.position.x + (game.teleporterCount % 5 - 2).toDouble(), -3),
      0,
    );
    pod.body.linearVelocity = Vector2.zero();
  }

  void _useTransmitter() {
    if (game.transmitterCount <= 0) return;
    game.transmitterCount--;
    // Safe teleport to surface center
    pod.body.setTransform(Vector2(0, -3), 0);
    pod.body.linearVelocity = Vector2.zero();
  }
}
