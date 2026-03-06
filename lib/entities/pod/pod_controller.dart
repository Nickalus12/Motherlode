import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Touch/keyboard input -> thrust/drill commands
///
/// Supports:
/// - Touch: virtual joystick with proportional thrust (drag from touch origin)
/// - Keyboard: Arrow keys or WASD (binary on/off)
///
/// Touch creates a virtual joystick at the initial touch point. Dragging away
/// from that origin controls thrust direction and magnitude proportionally.
class PodController extends Component
    with KeyboardHandler, HasGameReference<MotherlodeGame> {
  final Pod pod;

  /// Joystick dead zone radius in logical pixels.
  static const double _deadZone = 20.0;

  /// Maximum joystick radius — beyond this, thrust is 1.0.
  static const double _maxRadius = 120.0;

  /// Edge margin (pixels) where touches are ignored to prevent accidental input.
  static const double _edgeMargin = 16.0;

  /// Threshold angle (radians from straight down) within which drill activates.
  static const double _drillAngleThreshold = 0.6; // ~34 degrees

  // Active touch tracking (origin + current position per pointer)
  final Map<int, _TouchState> _activeTouches = {};

  /// Current joystick position for HUD visualization (null = no touch).
  Vector2? joystickOrigin;
  Vector2? joystickCurrent;
  double joystickMagnitude = 0.0;

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

    // Clear analog when using keyboard
    pod.thrustAnalogX = 0.0;
    pod.thrustAnalogY = 0.0;

    // Consumable hotkeys
    if (event is KeyDownEvent) {
      _handleConsumableKey(event.logicalKey);
    }

    return true;
  }

  /// Handle touch input for mobile controls
  void handleTouchDown(int pointerId, Vector2 position) {
    final viewportSize = game.camera.viewport.size;

    // Ignore edge touches
    if (position.x < _edgeMargin ||
        position.x > viewportSize.x - _edgeMargin ||
        position.y < _edgeMargin ||
        position.y > viewportSize.y - _edgeMargin) {
      return;
    }

    _activeTouches[pointerId] = _TouchState(
      origin: position.clone(),
      current: position.clone(),
    );
    _updateTouchInput();
  }

  void handleTouchMove(int pointerId, Vector2 position) {
    final touch = _activeTouches[pointerId];
    if (touch == null) return;
    touch.current = position.clone();
    _updateTouchInput();
  }

  void handleTouchUp(int pointerId) {
    _activeTouches.remove(pointerId);
    _updateTouchInput();
  }

  void _updateTouchInput() {
    if (_activeTouches.isEmpty) {
      // No touch — clear analog and binary
      pod.thrustAnalogX = 0.0;
      pod.thrustAnalogY = 0.0;
      pod.thrustUp = false;
      pod.thrustLeft = false;
      pod.thrustRight = false;
      pod.drillDown = false;
      joystickOrigin = null;
      joystickCurrent = null;
      joystickMagnitude = 0.0;
      return;
    }

    // Use the first active touch as the primary joystick
    final touch = _activeTouches.values.first;
    final dx = touch.current.x - touch.origin.x;
    final dy = touch.current.y - touch.origin.y;
    final dist = sqrt(dx * dx + dy * dy);

    // Update joystick visualization state
    joystickOrigin = touch.origin;
    joystickCurrent = touch.current;

    if (dist < _deadZone) {
      // Within dead zone — no input
      pod.thrustAnalogX = 0.0;
      pod.thrustAnalogY = 0.0;
      pod.thrustUp = false;
      pod.thrustLeft = false;
      pod.thrustRight = false;
      pod.drillDown = false;
      joystickMagnitude = 0.0;
      return;
    }

    // Normalize direction
    final normX = dx / dist;
    final normY = dy / dist;

    // Proportional magnitude with quadratic response curve (fine control at low displacement)
    final rawMag =
        ((dist - _deadZone) / (_maxRadius - _deadZone)).clamp(0.0, 1.0);
    final magnitude = rawMag * rawMag;
    joystickMagnitude = magnitude;

    // Apply directional analog values
    pod.thrustAnalogX = normX * magnitude;
    pod.thrustAnalogY = normY * magnitude;

    // Set binary flags for state machine compatibility
    pod.thrustUp = normY < -0.3 && magnitude > 0.1;
    pod.thrustLeft = normX < -0.3 && magnitude > 0.1;
    pod.thrustRight = normX > 0.3 && magnitude > 0.1;

    // Drill activates when dragging downward within angle threshold
    final angle = atan2(dy, dx.abs());
    pod.drillDown = angle > (pi / 2 - _drillAngleThreshold) &&
        normY > 0.5 &&
        magnitude > 0.15;
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

  /// Use a consumable by index (for mobile tap buttons).
  void useConsumable(int index) {
    switch (index) {
      case 0:
        _useDynamite();
      case 1:
        _usePlasticExplosive();
      case 2:
        _useReserveFuel();
      case 3:
        _useNanobots();
      case 4:
        _useTeleporter();
      case 5:
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

  static final Random _rng = Random();

  void _useTeleporter() {
    if (game.teleporterCount <= 0) return;
    game.teleporterCount--;
    // Teleport to a random surface position near the landing zone
    final offsetX = (_rng.nextDouble() * 8.0 - 4.0);
    pod.body.setTransform(
      Vector2(offsetX, -3),
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

/// Internal state for a tracked touch pointer.
class _TouchState {
  final Vector2 origin;
  Vector2 current;

  _TouchState({required this.origin, required this.current});
}
