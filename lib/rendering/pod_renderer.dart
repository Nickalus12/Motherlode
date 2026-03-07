import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';

/// Renders the mining robot using frame-based sprite animations.
///
/// Animations:
///   idle      — 4 frames  (48×48 px), breathing/idle loop
///   drill     — 16 frames (64×64 px), drilling downward
///   fly       — 16 frames (64×64 px), thruster propulsion
///   walk_east — 6 frames  (48×48 px), ground movement right
///   walk_west — 6 frames  (48×48 px), ground movement left
///   hover     — 16 frames (64×64 px), airborne without thrust
///   death     — 7 frames  (48×48 px), death sequence (plays once)
///   pickup    — 5 frames  (48×48 px), ore collection
class PodRenderer extends Component with HasGameReference<MotherlodeGame> {
  final Pod pod;
  double _time = 0;

  // Animation frame lists keyed by name
  final Map<String, List<ui.Image>> _anims = {};

  // Current animation state
  String _currentAnim = 'idle';
  int _frame = 0;
  double _frameTimer = 0;
  bool _flipX = false; // Mirror for facing direction

  // Previous animation for cross-fade transitions
  String? _prevAnim;
  int _prevFrame = 0;
  double _transitionProgress = 1.0; // 1.0 = fully transitioned
  static const double _transitionSpeed = 8.0; // Frames per second of blend

  // Death animation plays once then holds last frame
  bool _deathPlayed = false;

  // Pickup animation state (plays as overlay then returns to previous)
  bool _playingPickup = false;
  double _pickupTimer = 0;

  // Damage flash
  double _damageFlash = 0;
  double _lastHull = -1;

  // Drill available indicator
  double _drillAvailablePulse = 0;
  bool _canDrill = false;

  // Base FPS per animation (drill FPS is dynamic)
  static const Map<String, double> _baseFps = {
    'idle': 4.0,
    'drill': 8.0, // Base; scales up to 20 with drill progress
    'fly': 12.0,
    'walk_east': 10.0,
    'walk_west': 10.0,
    'hover': 8.0,
    'death': 8.0,
    'pickup': 12.0,
  };

  // Ground shadow state
  double _shadowOpacity = 0;

  // Pre-allocated Paint objects
  final _imgPaint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  final _flashPaint = ui.Paint()..blendMode = ui.BlendMode.plus;
  final _sparkPaint = ui.Paint()..style = ui.PaintingStyle.fill;
  final _statusPaint = ui.Paint();
  final _glowPaint = ui.Paint()
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 0.3);
  final _shadowPaint = ui.Paint()
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 0.15);

  PodRenderer({required this.pod});

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await _loadAnim('idle', 4);
    await _loadAnim('drill', 16);
    await _loadAnim('fly', 16);
    await _loadAnim('walk_east', 6);
    await _loadAnim('walk_west', 6);
    await _loadAnim('hover', 16);
    await _loadAnim('death', 7);
    await _loadAnim('pickup', 5);
  }

  Future<void> _loadAnim(String name, int frameCount) async {
    final frames = <ui.Image>[];
    for (int i = 0; i < frameCount; i++) {
      final path = 'robot/$name/frame_${i.toString().padLeft(3, '0')}.png';
      try {
        final img = await Flame.images.load(path);
        frames.add(img);
      } catch (_) {
        // Skip missing frames
      }
    }
    if (frames.isNotEmpty) {
      _anims[name] = frames;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    // Check if ore was collected this frame -> trigger pickup animation
    if (pod.drillSystem.oreCollectedThisFrame && !_playingPickup) {
      _playingPickup = true;
      _pickupTimer = 0;
    }

    // Update pickup animation timer
    if (_playingPickup) {
      _pickupTimer += dt;
      final pickupFrames = _anims['pickup'];
      final pickupFps = _baseFps['pickup'] ?? 12.0;
      final pickupDuration = (pickupFrames?.length ?? 5) / pickupFps;
      if (_pickupTimer >= pickupDuration) {
        _playingPickup = false;
      }
    }

    // Determine target animation from robot state + input
    final target = _resolveAnimation();

    // If animation changed, start cross-fade transition
    if (target != _currentAnim) {
      if (_currentAnim == 'death' && _deathPlayed) {
        // Stay on death
      } else {
        _prevAnim = _currentAnim;
        _prevFrame = _frame;
        _transitionProgress = 0;
        _currentAnim = target;
        _frame = 0;
        _frameTimer = 0;
        if (target == 'death') _deathPlayed = false;
      }
    }

    // Progress cross-fade
    if (_transitionProgress < 1.0) {
      _transitionProgress =
          (_transitionProgress + dt * _transitionSpeed).clamp(0.0, 1.0);
    }

    // Dynamic FPS for drill and walk animations
    double fps;
    if (_currentAnim == 'drill') {
      // Drill: 8 at 0% progress -> 20 at 100% progress
      final progress = pod.drillSystem.drillProgress;
      fps = 8.0 + progress * 12.0;
    } else if (_currentAnim == 'walk_east' || _currentAnim == 'walk_west') {
      // Walk: scale FPS with actual horizontal speed to prevent moonwalking
      final horizSpeed = pod.body.linearVelocity.x.abs();
      fps = (horizSpeed * 3.0).clamp(4.0, 14.0);
    } else {
      fps = _baseFps[_currentAnim] ?? 8.0;
    }

    // Advance frame timer
    _frameTimer += dt;
    if (_frameTimer >= 1.0 / fps) {
      _frameTimer -= 1.0 / fps;
      final frames = _anims[_currentAnim];
      if (frames != null && frames.isNotEmpty) {
        if (_currentAnim == 'death') {
          if (_frame < frames.length - 1) {
            _frame++;
          } else {
            _deathPlayed = true;
          }
        } else {
          _frame = (_frame + 1) % frames.length;
        }
      }
    }

    // Detect hull damage for flash effect
    final currentHull = game.hullSystem.currentHull;
    if (_lastHull >= 0 && currentHull < _lastHull) {
      _damageFlash = 1.0;
    }
    _lastHull = currentHull;
    if (_damageFlash > 0) {
      _damageFlash = (_damageFlash - dt * 4).clamp(0.0, 1.0);
    }

    // Update ground shadow opacity — fade in when grounded, fade out when airborne
    final isGrounded = pod.podBody.isGrounded;
    final targetShadowOpacity = isGrounded ? 0.35 : 0.0;
    _shadowOpacity += (targetShadowOpacity - _shadowOpacity) * (dt * 8.0);
    _shadowOpacity = _shadowOpacity.clamp(0.0, 0.35);

    // Drill available indicator: check if grounded + drillable cell below
    _updateDrillAvailable(dt);
  }

  void _updateDrillAvailable(double dt) {
    if (pod.state != PodState.drilling &&
        pod.podBody.isGrounded &&
        pod.state != PodState.dead) {
      final gridX = pod.position.x.round();
      final gridY = (pod.position.y + 1.2).round();
      final cell = game.chunkManager.getTerrainCell(gridX, gridY);
      _canDrill = cell != null && cell.isDrillable;
    } else {
      _canDrill = false;
    }

    if (_canDrill) {
      _drillAvailablePulse += dt * 3.0;
    } else {
      _drillAvailablePulse = 0;
    }
  }

  String _resolveAnimation() {
    if (pod.state == PodState.dead) return 'death';
    if (pod.state == PodState.drilling) return 'drill';

    // Any active thrust (keyboard or analog) → fly animation, regardless of state
    final isThrusting = pod.thrustUp || pod.thrustAnalogY < -0.1;
    final isMovingHoriz =
        pod.thrustLeft || pod.thrustRight || pod.thrustAnalogX.abs() > 0.1;

    if (isThrusting) {
      if (pod.thrustLeft || pod.thrustAnalogX < -0.1) _flipX = true;
      if (pod.thrustRight || pod.thrustAnalogX > 0.1) _flipX = false;
      return 'fly';
    }

    // Grounded + horizontal input + actually moving → walk
    if (pod.podBody.isGrounded ||
        pod.state == PodState.grounded ||
        pod.state == PodState.idle ||
        pod.state == PodState.surfaced) {
      // Check actual velocity to avoid walk animation when stuck against walls
      final actualHorizSpeed = pod.body.linearVelocity.x.abs();
      if (isMovingHoriz && actualHorizSpeed > 0.5) {
        if (pod.thrustLeft || pod.thrustAnalogX < -0.1) {
          _flipX = false;
          return 'walk_west';
        }
        if (pod.thrustRight || pod.thrustAnalogX > 0.1) {
          _flipX = false;
          return 'walk_east';
        }
      }
      return 'idle';
    }

    // Airborne without thrust — use hover animation
    return 'hover';
  }

  @override
  void render(ui.Canvas canvas) {
    canvas.save();

    // Drilling vibration offset (scales with progress)
    if (pod.state == PodState.drilling) {
      final progress = pod.drillSystem.drillProgress;
      final shakeAmp = 0.02 + progress * 0.04;
      final shake = sin(_time * 40) * shakeAmp;
      canvas.translate(shake, 0);
    }

    // Ground contact shadow
    if (_shadowOpacity > 0.01) {
      _drawGroundShadow(canvas);
    }

    // Drill available glow (subtle pulsing outline when grounded over drillable terrain)
    if (_canDrill && pod.state != PodState.drilling) {
      _drawDrillAvailableGlow(canvas);
    }

    // Cross-fade: draw previous animation frame with fading opacity
    if (_transitionProgress < 1.0 && _prevAnim != null) {
      final prevFrames = _anims[_prevAnim!];
      if (prevFrames != null && prevFrames.isNotEmpty) {
        final prevImg = prevFrames[_prevFrame.clamp(0, prevFrames.length - 1)];
        _drawSpriteWithOpacity(canvas, prevImg, 1.0 - _transitionProgress);
      }
    }

    // Draw the robot sprite (current animation)
    final opacity = _transitionProgress < 1.0 ? _transitionProgress : 1.0;
    _drawRobotWithOpacity(canvas, opacity);

    // Pickup animation overlay (plays on top of current anim)
    if (_playingPickup) {
      _drawPickupOverlay(canvas);
    }

    // Damage white flash overlay
    if (_damageFlash > 0) {
      _drawDamageFlash(canvas);
    }

    // Status indicators
    if (pod.state != PodState.dead) {
      _drawStatusIndicators(canvas);
    }

    // Drilling sparks
    if (pod.state == PodState.drilling) {
      _drawDrillSparks(canvas);
    }

    canvas.restore();
  }

  static const double _drawSize = 2.4;
  static const double _spriteOffsetY = 0.19;

  void _drawRobotWithOpacity(ui.Canvas canvas, double opacity) {
    final frames = _anims[_currentAnim] ?? _anims['idle'];
    if (frames == null || frames.isEmpty) {
      _drawFallback(canvas);
      return;
    }

    final img = frames[_frame.clamp(0, frames.length - 1)];
    _drawSpriteWithOpacity(canvas, img, opacity);
  }

  void _drawSpriteWithOpacity(ui.Canvas canvas, ui.Image img, double opacity) {
    final srcRect = ui.Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );

    canvas.save();

    if (_flipX) {
      canvas.scale(-1, 1);
    }

    final dstRect = ui.Rect.fromCenter(
      center: const ui.Offset(0, _spriteOffsetY),
      width: _drawSize,
      height: _drawSize,
    );

    if (opacity < 1.0) {
      _imgPaint.color = ui.Color.from(
        alpha: opacity.clamp(0.0, 1.0),
        red: 1.0,
        green: 1.0,
        blue: 1.0,
      );
    } else {
      _imgPaint.color = const ui.Color(0xFFFFFFFF);
    }

    canvas.drawImageRect(img, srcRect, dstRect, _imgPaint);
    _imgPaint.color = const ui.Color(0xFFFFFFFF); // Reset
    canvas.restore();
  }

  void _drawPickupOverlay(ui.Canvas canvas) {
    final frames = _anims['pickup'];
    if (frames == null || frames.isEmpty) return;

    final pickupFps = _baseFps['pickup'] ?? 12.0;
    final pickupFrame =
        (_pickupTimer * pickupFps).floor().clamp(0, frames.length - 1);
    final img = frames[pickupFrame];

    // Pickup fades in then out
    final totalDuration = frames.length / pickupFps;
    final t = (_pickupTimer / totalDuration).clamp(0.0, 1.0);
    final alpha = t < 0.3 ? t / 0.3 : (1.0 - t) / 0.7;

    _drawSpriteWithOpacity(canvas, img, alpha.clamp(0.0, 0.7));
  }

  void _drawDrillAvailableGlow(ui.Canvas canvas) {
    final pulse = (sin(_drillAvailablePulse) * 0.5 + 0.5); // 0..1
    final alpha = 0.15 + pulse * 0.2;

    _glowPaint.color = ui.Color.from(
      alpha: alpha,
      red: 0.3,
      green: 0.8,
      blue: 1.0,
    );

    // Soft glow around the robot's lower half (drill zone)
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: const ui.Offset(0, 0.8),
        width: 1.8 + pulse * 0.3,
        height: 1.2 + pulse * 0.2,
      ),
      _glowPaint,
    );
  }

  void _drawGroundShadow(ui.Canvas canvas) {
    // Get slope normal from SDF collision system for shadow deformation
    double normalX = 0.0;
    try {
      normalX = game.sdfCollisionSystem.slopeNormal.x;
    } catch (_) {
      // System not yet available
    }

    _shadowPaint.color = ui.Color.from(
      alpha: _shadowOpacity,
      red: 0.0,
      green: 0.0,
      blue: 0.0,
    );

    // Skew shadow ellipse based on terrain slope
    canvas.save();
    // Shadow at the robot's feet (y=1.1 is physics bottom)
    canvas.translate(normalX * 0.3, 1.1);
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset.zero,
        width: 1.6 + normalX.abs() * 0.4,
        height: 0.25,
      ),
      _shadowPaint,
    );
    canvas.restore();
  }

  void _drawDamageFlash(ui.Canvas canvas) {
    final flashAlpha = (_damageFlash * 0.6).clamp(0.0, 1.0);
    _flashPaint.color = ui.Color.from(
      alpha: flashAlpha,
      red: 1.0,
      green: 1.0,
      blue: 1.0,
    );
    // Cover the sprite area (centered on the sprite draw rect)
    canvas.drawRect(
      ui.Rect.fromCenter(
        center: const ui.Offset(0, 0.19),
        width: 2.0,
        height: 2.4,
      ),
      _flashPaint,
    );
  }

  void _drawDrillSparks(ui.Canvas canvas) {
    final random = Random((_time * 30).toInt());
    final drillProgress = pod.drillSystem.drillProgress;

    // Spark count increases with drill progress for satisfying feedback
    final sparkCount = 4 + (drillProgress * 8).toInt();
    for (int i = 0; i < sparkCount; i++) {
      final sparkX = (random.nextDouble() - 0.5) * 0.6;
      // Sparks emit from feet (physics bottom y=1.1) and spray downward
      final sparkY = 1.1 + random.nextDouble() * 0.3;
      final size = 0.02 + random.nextDouble() * 0.04;
      final t = random.nextDouble();
      _sparkPaint.color = ui.Color.lerp(
        const ui.Color(0xFFFFFFCC),
        const ui.Color(0xFFFF6600),
        t,
      )!;
      canvas.drawCircle(ui.Offset(sparkX, sparkY), size, _sparkPaint);
    }

    // Drill progress arc around the robot's feet for visual feedback
    if (drillProgress > 0.05) {
      final arcPaint = ui.Paint()
        ..color = ui.Color.from(
          alpha: 0.5 + drillProgress * 0.3,
          red: 1.0,
          green: 0.6 - drillProgress * 0.4,
          blue: 0.1,
        )
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 0.06;
      canvas.drawArc(
        ui.Rect.fromCenter(
          center: const ui.Offset(0, 1.1),
          width: 1.2,
          height: 0.4,
        ),
        0,
        drillProgress * 2 * pi,
        false,
        arcPaint,
      );
    }
  }

  void _drawStatusIndicators(ui.Canvas canvas) {
    final cargoRatio = pod.cargoSystem.fillRatio;
    if (cargoRatio > 0) {
      final cargoColor = cargoRatio > 0.9
          ? const ui.Color(0xFFFF0000)
          : const ui.Color(0xFF00CCCC);
      _statusPaint.color = cargoColor;
      // Cargo bar along the left side of the sprite
      final barTop = 0.19 - 0.5 + (1.0 - cargoRatio) * 1.0;
      canvas.drawRect(
        ui.Rect.fromLTWH(-1.05, barTop, 0.05, cargoRatio * 1.0),
        _statusPaint,
      );
    }
  }

  void _drawFallback(ui.Canvas canvas) {
    final bodyPaint = ui.Paint()..color = const ui.Color(0xFF4A6741);
    final path = ui.Path();
    // Fallback shape matches physics body extents (-0.9..0.9, -1.1..1.1)
    path.moveTo(-0.7, -1.0);
    path.lineTo(0.7, -1.0);
    path.lineTo(0.8, 0.6);
    path.lineTo(0.6, 1.1);
    path.lineTo(-0.6, 1.1);
    path.lineTo(-0.8, 0.6);
    path.close();
    canvas.drawPath(path, bodyPaint);
  }
}
