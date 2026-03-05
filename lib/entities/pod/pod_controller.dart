import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/services.dart';

import 'package:hellbore/entities/pod/pod.dart';
import 'package:hellbore/hellbore_game.dart';

/// Touch/keyboard input → thrust/drill commands
///
/// Supports:
/// - Touch: directional zones on screen (left/right halves for horizontal,
///   top half for thrust, bottom half for drill)
/// - Keyboard: Arrow keys or WASD
class PodController extends Component
    with KeyboardHandler, HasGameReference<HellboreGame> {
  final Pod pod;

  // Touch zones (relative to viewport)
  static const double _touchZoneMargin = 0.15;

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

    final viewportSize = game.size;
    final centerX = viewportSize.x / 2;
    final centerY = viewportSize.y / 2;

    for (final touch in _activeTouches.values) {
      final relX = touch.x / viewportSize.x;
      final relY = touch.y / viewportSize.y;

      // Determine direction based on touch position relative to center
      final dx = touch.x - centerX;
      final dy = touch.y - centerY;

      // Determine primary direction
      if (dx.abs() > dy.abs()) {
        // Horizontal movement
        if (dx < -viewportSize.x * _touchZoneMargin) {
          pod.thrustLeft = true;
        } else if (dx > viewportSize.x * _touchZoneMargin) {
          pod.thrustRight = true;
        }
      } else {
        // Vertical movement
        if (dy < -viewportSize.y * _touchZoneMargin) {
          pod.thrustUp = true;
        } else if (dy > viewportSize.y * _touchZoneMargin) {
          pod.drillDown = true;
        }
      }

      // Allow simultaneous horizontal + vertical in corners
      if (relX < 0.3 && relY < 0.3) {
        pod.thrustUp = true;
        pod.thrustLeft = true;
      } else if (relX > 0.7 && relY < 0.3) {
        pod.thrustUp = true;
        pod.thrustRight = true;
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
