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
/// - Keyboard: Arrow keys or WASD (binary on/off, overrides analog)
///
/// Touch creates a virtual joystick at the initial touch point. Dragging away
/// from that origin controls thrust direction and magnitude proportionally.
///
/// Features:
/// - Dead zone to prevent accidental micro-movements
/// - Cubic sensitivity curve for precise low-speed + fast high-speed control
/// - Smooth analog transitions (lerp) to prevent jerky thrust changes
/// - Directional bias: near-vertical drags snap to pure downward for drilling
class PodController extends Component
    with KeyboardHandler, HasGameReference<MotherlodeGame> {
  final Pod pod;

  /// Joystick dead zone radius in logical pixels.
  static const double _deadZone = 12.0;

  /// Maximum joystick radius — beyond this, thrust is 1.0.
  static const double _maxRadius = 120.0;

  /// Edge margin (pixels) where touches are ignored to prevent accidental input.
  static const double _edgeMargin = 16.0;

  /// Threshold angle (radians from straight down) within which drill activates.
  static const double _drillAngleThreshold = 1.0;

  /// Directional snap threshold: angle within this many degrees of pure down
  /// snaps horizontal input to zero for easier drilling (30 degrees = ~0.52 rad).
  static const double _drillSnapAngle = 0.52;

  /// Smooth lerp rate for analog input transitions (higher = faster response).
  static const double _analogLerpRate = 15.0;

  // Active touch tracking (origin + current position per pointer)
  final Map<int, _TouchState> _activeTouches = {};

  /// Whether keyboard is currently active (overrides analog touch input).
  bool _keyboardActive = false;

  // Smooth analog state — lerps toward target each frame
  double _smoothAnalogX = 0.0;
  double _smoothAnalogY = 0.0;
  double _targetAnalogX = 0.0;
  double _targetAnalogY = 0.0;

  /// Current joystick position for HUD visualization (null = no touch).
  Vector2? joystickOrigin;
  Vector2? joystickCurrent;
  double joystickMagnitude = 0.0;

  /// Whether touch is active (for HUD ring visualization).
  bool get isTouchActive => _activeTouches.isNotEmpty;

  PodController({required this.pod});

  @override
  void update(double dt) {
    super.update(dt);

    // Skip analog smoothing when keyboard is active
    if (_keyboardActive) return;

    // Smooth lerp analog values toward target
    final lerpFactor = (_analogLerpRate * dt).clamp(0.0, 1.0);
    _smoothAnalogX += (_targetAnalogX - _smoothAnalogX) * lerpFactor;
    _smoothAnalogY += (_targetAnalogY - _smoothAnalogY) * lerpFactor;

    // Snap to zero when very close to prevent drift
    if (_smoothAnalogX.abs() < 0.001) _smoothAnalogX = 0.0;
    if (_smoothAnalogY.abs() < 0.001) _smoothAnalogY = 0.0;

    // Apply smoothed values to pod
    pod.thrustAnalogX = _smoothAnalogX;
    pod.thrustAnalogY = _smoothAnalogY;
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    final anyMovementKey = keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW) ||
        keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA) ||
        keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD) ||
        keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS);

    _keyboardActive = anyMovementKey;

    // Movement keys
    pod.thrustUp = keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW);
    pod.thrustLeft = keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);
    pod.thrustRight = keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);
    pod.drillDown = keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS);

    // Clear analog when using keyboard (keyboard overrides touch)
    if (_keyboardActive) {
      pod.thrustAnalogX = 0.0;
      pod.thrustAnalogY = 0.0;
      _smoothAnalogX = 0.0;
      _smoothAnalogY = 0.0;
      _targetAnalogX = 0.0;
      _targetAnalogY = 0.0;
    }

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
    _keyboardActive = false;
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

  /// Apply cubic sensitivity curve: small inputs = precise, large inputs = fast.
  double _applySensitivityCurve(double rawMag) {
    return rawMag * rawMag * rawMag; // Cubic response
  }

  void _updateTouchInput() {
    if (_activeTouches.isEmpty) {
      // No touch — smoothly decay analog to zero
      _targetAnalogX = 0.0;
      _targetAnalogY = 0.0;
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
      _targetAnalogX = 0.0;
      _targetAnalogY = 0.0;
      pod.thrustUp = false;
      pod.thrustLeft = false;
      pod.thrustRight = false;
      pod.drillDown = false;
      joystickMagnitude = 0.0;
      return;
    }

    // Normalize direction
    double normX = dx / dist;
    double normY = dy / dist;

    // Directional bias: snap to pure downward when within snap angle
    final downAngle = atan2(normY, normX.abs());
    if (normY > 0 && downAngle > (pi / 2 - _drillSnapAngle)) {
      // Near-vertical downward: zero out horizontal component
      normX = 0.0;
      normY = 1.0;
    }

    // Cubic sensitivity curve for magnitude
    final rawMag =
        ((dist - _deadZone) / (_maxRadius - _deadZone)).clamp(0.0, 1.0);
    final magnitude = _applySensitivityCurve(rawMag);
    joystickMagnitude = magnitude;

    // Drill activates when dragging downward within angle threshold
    final angle = atan2(dy, dx.abs());
    final wantsDrill = angle > (pi / 2 - _drillAngleThreshold) &&
        normY > 0.3 &&
        magnitude > 0.1;

    if (wantsDrill) {
      // Drilling is mutually exclusive with thrust — clear all thrust
      pod.drillDown = true;
      pod.thrustUp = false;
      pod.thrustLeft = false;
      pod.thrustRight = false;
      _targetAnalogX = 0.0;
      _targetAnalogY = 0.0;
    } else {
      pod.drillDown = false;
      // Set smooth analog targets (actual values applied via lerp in update)
      _targetAnalogX = normX * magnitude;
      _targetAnalogY = normY * magnitude;

      // Set binary flags for state machine compatibility
      pod.thrustUp = normY < -0.3 && magnitude > 0.1;
      pod.thrustLeft = normX < -0.3 && magnitude > 0.1;
      pod.thrustRight = normX > 0.3 && magnitude > 0.1;
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
    } else if (key == LogicalKeyboardKey.keyB) {
      _useSupportBeam();
    } else if (key == LogicalKeyboardKey.keyG) {
      _useFlare();
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
      case 6:
        _useSupportBeam();
      case 7:
        _useFlare();
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

  void _useSupportBeam() {
    game.deployableSystem.placeBeam();
  }

  void _useFlare() {
    game.deployableSystem.launchFlare();
  }
}

/// Internal state for a tracked touch pointer.
class _TouchState {
  final Vector2 origin;
  Vector2 current;

  _TouchState({required this.origin, required this.current});
}
