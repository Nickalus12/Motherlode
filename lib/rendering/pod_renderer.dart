import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import 'package:motherlode/entities/pod/pod.dart';
import 'package:motherlode/motherlode_game.dart';

/// Renders the mining pod using pixel art sprites with animated drill sheets.
///
/// Hull: individual frame PNGs (idle_0..3, move_left, move_right, base)
/// Drills: 4×4 sprite sheets (96×96, each frame 24×24), 7 tiers (0-6)
class PodRenderer extends Component with HasGameReference<MotherlodeGame> {
  final Pod pod;
  double _time = 0;

  // Hull sprites per state
  final List<ui.Image> _idleFrames = [];
  ui.Image? _baseImage;
  ui.Image? _moveLeftImage;
  ui.Image? _moveRightImage;

  // Drill sprite sheets (96×96, 4×4 grid = 16 frames at 24×24 each)
  final Map<int, ui.Image> _drillSheets = {};

  // Sprite sheet layout
  static const int _sheetCols = 4;
  static const int _sheetRows = 4;
  static const int _drillFrameCount = 16;

  // Drill tier → asset path
  static const _drillAssets = {
    0: 'drills/drill_0/sheet.png',
    1: 'drills/drill_1/sheet.png',
    2: 'drills/drill_2/sheet.png',
    3: 'drills/drill_3/sheet.png',
    4: 'drills/drill_4/sheet.png',
    5: 'drills/drill_5/sheet.png',
    6: 'drills/drill_6/sheet.png',
  };

  // Animation timing
  int _idleFrame = 0;
  double _idleTimer = 0;
  static const double _idleFps = 4.0;

  int _drillFrame = 0;
  double _drillTimer = 0;
  static const double _drillFps = 12.0;

  // Damage flash
  double _damageFlash = 0;
  double _lastHull = -1;

  // Pre-allocated Paint objects to avoid per-frame GC pressure
  final _imgPaint = ui.Paint();
  final _drillPaint = ui.Paint();
  final _flashPaint = ui.Paint()..blendMode = ui.BlendMode.plus;
  final _sparkPaint = ui.Paint()..style = ui.PaintingStyle.fill;
  final _exhaustPaint = ui.Paint()..style = ui.PaintingStyle.fill;
  final _statusPaint = ui.Paint();
  final _bodyFillPaint = ui.Paint()..color = const ui.Color(0xFF4A6741);
  final _bodyStrokePaint = ui.Paint()
    ..color = const ui.Color(0xFF2D3F28)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 0.06;
  final _drillFallbackPaint = ui.Paint()
    ..color = const ui.Color(0xFFAAAAAA)
    ..style = ui.PaintingStyle.fill;

  PodRenderer({required this.pod});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Load hull base
    _baseImage = await _tryLoad('pod/hull_0/base.png');

    // Load idle animation frames
    for (int i = 0; i < 4; i++) {
      final img = await _tryLoad('pod/hull_0/idle_$i.png');
      if (img != null) _idleFrames.add(img);
    }

    // Load directional sprites
    _moveLeftImage = await _tryLoad('pod/hull_0/move_left.png');
    _moveRightImage = await _tryLoad('pod/hull_0/move_right.png');

    // Load all drill sprite sheets
    for (final entry in _drillAssets.entries) {
      final img = await _tryLoad(entry.value);
      if (img != null) _drillSheets[entry.key] = img;
    }
  }

  Future<ui.Image?> _tryLoad(String path) async {
    try {
      return await Flame.images.load(path);
    } catch (_) {
      return null;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;

    // Idle frame cycling
    _idleTimer += dt;
    if (_idleTimer >= 1.0 / _idleFps && _idleFrames.isNotEmpty) {
      _idleTimer = 0;
      _idleFrame = (_idleFrame + 1) % _idleFrames.length;
    }

    // Drill frame cycling (only when drilling, reset when not)
    if (pod.state == PodState.drilling) {
      _drillTimer += dt;
      if (_drillTimer >= 1.0 / _drillFps) {
        _drillTimer = 0;
        _drillFrame = (_drillFrame + 1) % _drillFrameCount;
      }
    } else {
      _drillFrame = 0;
      _drillTimer = 0;
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

  @override
  void render(ui.Canvas canvas) {
    canvas.save();

    // Drilling vibration offset
    if (pod.state == PodState.drilling) {
      final shake = sin(_time * 40) * 0.03;
      canvas.translate(shake, 0);
    }

    // Draw hull
    _drawHull(canvas);

    // Draw drill below hull (only when drilling or grounded)
    if (pod.state == PodState.drilling ||
        pod.state == PodState.grounded ||
        pod.state == PodState.idle) {
      _drawDrill(canvas);
    }

    // Procedural exhaust flames
    if (pod.thrustUp || pod.state == PodState.flying) {
      _drawExhaust(canvas);
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

  void _drawHull(ui.Canvas canvas) {
    // Choose hull image based on state
    ui.Image? img;
    if (pod.thrustLeft && !pod.thrustRight && _moveLeftImage != null) {
      img = _moveLeftImage;
    } else if (pod.thrustRight && !pod.thrustLeft && _moveRightImage != null) {
      img = _moveRightImage;
    } else if (_idleFrames.isNotEmpty) {
      img = _idleFrames[_idleFrame];
    } else {
      img = _baseImage;
    }

    if (img != null) {
      // Hull centered on physics body; body is setAsBoxXY(0.9, 1.1) = 1.8×2.2
      _drawImage(canvas, img, const ui.Offset(0, 0), 1.8, 2.2);
    } else {
      _drawBodyFallback(canvas);
    }
  }

  void _drawDrill(ui.Canvas canvas) {
    final drillLevel = game.drillLevel.clamp(0, 6);
    final sheet = _drillSheets[drillLevel];

    if (sheet != null) {
      // Sprite sheet: 96×96 with 4×4 grid = 24×24 per frame
      final frameW = sheet.width / _sheetCols;
      final frameH = sheet.height / _sheetRows;

      // Pick frame: animate when drilling, frame 0 otherwise
      final frame = pod.state == PodState.drilling ? _drillFrame : 0;
      final col = frame % _sheetCols;
      final row = frame ~/ _sheetCols;

      final srcRect = ui.Rect.fromLTWH(
        col * frameW,
        row * frameH,
        frameW,
        frameH,
      );

      // Drill sits below hull, within physics bounds
      const drillWidth = 0.6;
      const drillHeight = 0.6;
      final dstRect = ui.Rect.fromCenter(
        center: const ui.Offset(0, 0.85),
        width: drillWidth,
        height: drillHeight,
      );

      // Glow pulse when drilling
      if (pod.state == PodState.drilling) {
        _drillPaint.colorFilter = ui.ColorFilter.mode(
          ui.Color.from(
            alpha: (sin(_time * 10) + 1) * 0.1,
            red: 1.0,
            green: 0.7,
            blue: 0.0,
          ),
          ui.BlendMode.plus,
        );
      } else {
        _drillPaint.colorFilter = null;
      }

      canvas.drawImageRect(sheet, srcRect, dstRect, _drillPaint);
    } else {
      _drawDrillFallback(canvas);
    }
  }

  void _drawImage(
    ui.Canvas canvas,
    ui.Image img,
    ui.Offset center,
    double width,
    double height,
  ) {
    final srcRect = ui.Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final dstRect = ui.Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    canvas.drawImageRect(img, srcRect, dstRect, _imgPaint);
  }

  void _drawDamageFlash(ui.Canvas canvas) {
    final flashAlpha = (_damageFlash * 0.6).clamp(0.0, 1.0);
    _flashPaint.color = ui.Color.from(
      alpha: flashAlpha,
      red: 1.0,
      green: 1.0,
      blue: 1.0,
    );
    canvas.drawRect(
      ui.Rect.fromCenter(
        center: const ui.Offset(0, 0),
        width: 1.8,
        height: 2.2,
      ),
      _flashPaint,
    );
  }

  void _drawDrillSparks(ui.Canvas canvas) {
    final random = Random((_time * 30).toInt());

    for (int i = 0; i < 6; i++) {
      final sparkX = (random.nextDouble() - 0.5) * 0.5;
      final sparkY = 1.1 + random.nextDouble() * 0.2;
      final size = 0.02 + random.nextDouble() * 0.03;
      final t = random.nextDouble();
      _sparkPaint.color = ui.Color.lerp(
        const ui.Color(0xFFFFFFCC),
        const ui.Color(0xFFFF6600),
        t,
      )!;
      canvas.drawCircle(ui.Offset(sparkX, sparkY), size, _sparkPaint);
    }
  }

  void _drawExhaust(ui.Canvas canvas) {
    final flamePhase = _time * 20;
    // Exhaust comes from the side panels of the mech, near the top of the body
    for (int side = -1; side <= 1; side += 2) {
      final baseX = side * 0.45; // tight against side panels of the mech body
      const baseY = -0.2; // shoulder area where engines would be
      for (int i = 0; i < 4; i++) {
        final flicker = sin(flamePhase + i * 1.5 + side) * 0.08;
        final flameLength = 0.2 + i * 0.05 + flicker;
        final flameWidth = 0.06 - i * 0.01;
        final t = i / 4.0;
        final flameColor = ui.Color.lerp(
          const ui.Color(0xFFFFFFCC),
          const ui.Color(0xFFFF4400),
          t,
        )!
            .withValues(alpha: 1.0 - t * 0.5);

        _exhaustPaint.color = flameColor;
        canvas.drawRect(
          ui.Rect.fromCenter(
            center: ui.Offset(baseX, baseY + flameLength / 2),
            width: flameWidth,
            height: flameLength,
          ),
          _exhaustPaint,
        );
      }
    }
  }

  void _drawStatusIndicators(ui.Canvas canvas) {
    final cargoRatio = pod.cargoSystem.fillRatio;
    if (cargoRatio > 0) {
      final cargoColor = cargoRatio > 0.9
          ? const ui.Color(0xFFFF0000)
          : const ui.Color(0xFF00CCCC);
      _statusPaint.color = cargoColor;
      canvas.drawRect(
        ui.Rect.fromLTWH(-0.85, 0.3 - cargoRatio * 0.5, 0.04, cargoRatio * 0.5),
        _statusPaint,
      );
    }
  }

  // Fallback renderers in case sprites fail to load
  void _drawBodyFallback(ui.Canvas canvas) {
    final bodyPath = ui.Path();
    bodyPath.moveTo(-0.7, -1.1);
    bodyPath.lineTo(0.7, -1.1);
    bodyPath.lineTo(0.8, 0.3);
    bodyPath.lineTo(0.6, 0.8);
    bodyPath.lineTo(-0.6, 0.8);
    bodyPath.lineTo(-0.8, 0.3);
    bodyPath.close();

    canvas.drawPath(bodyPath, _bodyFillPaint);
    canvas.drawPath(bodyPath, _bodyStrokePaint);
  }

  void _drawDrillFallback(ui.Canvas canvas) {
    canvas.drawRect(
      const ui.Rect.fromLTWH(-0.08, 0.7, 0.16, 0.3),
      _drillFallbackPaint,
    );
    final bitPath = ui.Path();
    bitPath.moveTo(-0.1, 1.0);
    bitPath.lineTo(0.1, 1.0);
    bitPath.lineTo(0.0, 1.15);
    bitPath.close();
    canvas.drawPath(bitPath, _drillFallbackPaint);
  }
}
