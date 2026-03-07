import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';

/// Renders the mining robot using frame-based sprite animations.
///
/// Animations (48×48 px frames):
///   idle      — 4 frames, breathing/idle loop
///   drill     — 16 frames, drilling downward
///   fly       — 16 frames, thruster propulsion
///   walk_east — 6 frames, ground movement right
///   walk_west — 6 frames, ground movement left
///   hover     — 16 frames, airborne without thrust
///   death     — 7 frames, death sequence (plays once)
///   pickup    — 5 frames, ore collection
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

  // Death animation plays once then holds last frame
  bool _deathPlayed = false;

  // Damage flash
  double _damageFlash = 0;
  double _lastHull = -1;

  // FPS per animation
  static const Map<String, double> _fps = {
    'idle': 4.0,
    'drill': 12.0,
    'fly': 12.0,
    'walk_east': 10.0,
    'walk_west': 10.0,
    'hover': 8.0,
    'death': 8.0,
    'pickup': 8.0,
  };

  // Pre-allocated Paint objects
  final _imgPaint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  final _flashPaint = ui.Paint()..blendMode = ui.BlendMode.plus;
  final _sparkPaint = ui.Paint()..style = ui.PaintingStyle.fill;
  final _statusPaint = ui.Paint();

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

    // Determine target animation from pod state + input
    final target = _resolveAnimation();

    // If animation changed, reset frame counter (except death which plays once)
    if (target != _currentAnim) {
      if (_currentAnim == 'death' && _deathPlayed) {
        // Stay on death
      } else {
        _currentAnim = target;
        _frame = 0;
        _frameTimer = 0;
        if (target == 'death') _deathPlayed = false;
      }
    }

    // Advance frame timer
    final fps = _fps[_currentAnim] ?? 8.0;
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
  }

  String _resolveAnimation() {
    if (pod.state == PodState.dead) return 'death';
    if (pod.state == PodState.drilling) return 'drill';

    // Any active thrust (keyboard or analog) → fly animation, regardless of state
    final isThrusting = pod.thrustUp || pod.thrustAnalogY < -0.1;
    final isMovingHoriz = pod.thrustLeft || pod.thrustRight ||
        pod.thrustAnalogX.abs() > 0.1;

    if (isThrusting) {
      if (pod.thrustLeft || pod.thrustAnalogX < -0.1) _flipX = true;
      if (pod.thrustRight || pod.thrustAnalogX > 0.1) _flipX = false;
      return 'fly';
    }

    // Grounded + horizontal input → walk
    if (pod.podBody.isGrounded || pod.state == PodState.grounded ||
        pod.state == PodState.idle || pod.state == PodState.surfaced) {
      if (isMovingHoriz) {
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

    // Airborne without thrust
    return 'idle';
  }

  @override
  void render(ui.Canvas canvas) {
    canvas.save();

    // Drilling vibration offset
    if (pod.state == PodState.drilling) {
      final shake = sin(_time * 40) * 0.03;
      canvas.translate(shake, 0);
    }

    // Draw the robot sprite (fly animation has built-in thruster VFX)
    _drawRobot(canvas);

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

  void _drawRobot(ui.Canvas canvas) {
    final frames = _anims[_currentAnim] ?? _anims['idle'];
    if (frames == null || frames.isEmpty) {
      _drawFallback(canvas);
      return;
    }

    final img = frames[_frame.clamp(0, frames.length - 1)];

    // Physics body: center at (0,0), half-extents (0.9, 1.1).
    // Bottom edge (ground contact) at y=+1.1.
    // Sprite is 48×48 px. The robot's feet sit at ~88% down the frame.
    // drawSize 2.4 gives good visual coverage of the 1.8×2.2 physics box.
    // Feet alignment: offsetY - halfDraw + 0.88 * drawSize = 1.1
    //   offsetY = 1.1 - 0.88 * 2.4 + 1.2 = 0.188
    const drawSize = 2.4;
    const spriteOffsetY = 0.19;

    final srcRect = ui.Rect.fromLTWH(
      0, 0, img.width.toDouble(), img.height.toDouble(),
    );

    canvas.save();

    // Apply horizontal flip if needed
    if (_flipX) {
      canvas.scale(-1, 1);
    }

    final dstRect = ui.Rect.fromCenter(
      center: const ui.Offset(0, spriteOffsetY),
      width: drawSize,
      height: drawSize,
    );

    canvas.drawImageRect(img, srcRect, dstRect, _imgPaint);
    canvas.restore();
  }

  void _drawDamageFlash(ui.Canvas canvas) {
    final flashAlpha = (_damageFlash * 0.6).clamp(0.0, 1.0);
    _flashPaint.color = ui.Color.from(
      alpha: flashAlpha, red: 1.0, green: 1.0, blue: 1.0,
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
        const ui.Color(0xFFFFFFCC), const ui.Color(0xFFFF6600), t,
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
