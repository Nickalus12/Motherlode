import 'dart:math';
import 'package:flutter/material.dart';

// ─── FUEL TANK VISUAL ───

class FuelTankVisual extends StatefulWidget {
  final int level;
  final int maxLevel;
  final double fillPercent; // 0.0 to 1.0

  const FuelTankVisual({
    super.key,
    required this.level,
    required this.maxLevel,
    this.fillPercent = 1.0,
  });

  @override
  State<FuelTankVisual> createState() => _FuelTankVisualState();
}

class _FuelTankVisualState extends State<FuelTankVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(120, 120),
          painter: _FuelTankPainter(
            level: widget.level,
            maxLevel: widget.maxLevel,
            fillPercent: widget.fillPercent,
            wavePhase: _controller.value * 2 * pi,
          ),
        );
      },
    );
  }
}

class _FuelTankPainter extends CustomPainter {
  final int level;
  final int maxLevel;
  final double fillPercent;
  final double wavePhase;

  _FuelTankPainter({
    required this.level,
    required this.maxLevel,
    required this.fillPercent,
    required this.wavePhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Tank dimensions scale with level
    final scale = 0.6 + (level / maxLevel.clamp(1, 100)) * 0.4;
    final tankW = 50.0 * scale;
    final tankH = 70.0 * scale;
    final tankRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 5), width: tankW, height: tankH),
      const Radius.circular(6),
    );

    // Tank body outline
    final outlinePaint = Paint()
      ..color = Colors.white30
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(tankRect, outlinePaint);

    // Tank body fill (dark)
    final bodyPaint = Paint()..color = const Color(0xFF1A1A2E);
    canvas.drawRRect(tankRect, bodyPaint);

    // Liquid fill with wave
    final fillColor = Color.lerp(
      const Color(0xFFFF3333),
      const Color(0xFF33FF66),
      fillPercent,
    )!;

    canvas.save();
    canvas.clipRRect(tankRect);

    final liquidTop =
        tankRect.outerRect.bottom - (tankRect.outerRect.height * fillPercent);
    final liquidPath = Path();
    liquidPath.moveTo(tankRect.outerRect.left, tankRect.outerRect.bottom);
    liquidPath.lineTo(tankRect.outerRect.left, liquidTop);

    // Wave effect
    final waveAmp = 2.0 + level * 0.3;
    for (double x = tankRect.outerRect.left;
        x <= tankRect.outerRect.right;
        x += 2) {
      final normalized =
          (x - tankRect.outerRect.left) / tankRect.outerRect.width;
      final y = liquidTop + sin(wavePhase + normalized * 4 * pi) * waveAmp;
      liquidPath.lineTo(x, y);
    }

    liquidPath.lineTo(tankRect.outerRect.right, tankRect.outerRect.bottom);
    liquidPath.close();

    final liquidPaint = Paint()..color = fillColor.withValues(alpha: 0.7);
    canvas.drawPath(liquidPath, liquidPaint);

    // Liquid glow
    final glowPaint = Paint()
      ..color = fillColor.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(liquidPath, glowPaint);

    canvas.restore();

    // Re-draw outline on top
    canvas.drawRRect(tankRect, outlinePaint);

    // Cap on top
    final capW = tankW * 0.4;
    final capRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, tankRect.outerRect.top - 4),
        width: capW,
        height: 10,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(capRect, Paint()..color = Colors.grey.shade600);
    canvas.drawRRect(capRect, outlinePaint);

    // Pixel-art rivet details
    final rivetPaint = Paint()..color = Colors.white24;
    for (int i = 0; i < (level + 1).clamp(1, 4); i++) {
      final ry = tankRect.outerRect.top +
          10 +
          i * (tankRect.outerRect.height - 20) / 4;
      canvas.drawCircle(
          Offset(tankRect.outerRect.left + 5, ry), 1.5, rivetPaint);
      canvas.drawCircle(
          Offset(tankRect.outerRect.right - 5, ry), 1.5, rivetPaint);
    }

    // Level label
    _drawLabel(canvas, size,
        _fuelTankNames[level.clamp(0, _fuelTankNames.length - 1)]);
  }

  static const _fuelTankNames = [
    'MICRO',
    'MEDIUM',
    'HUGE',
    'GIGANTIC',
    'TITANIC',
    'LEVIATHAN',
    'COMPRESS',
    'INTEGRATOR',
  ];

  @override
  bool shouldRepaint(covariant _FuelTankPainter old) => true;
}

// ─── HULL VISUAL ───

class HullVisual extends StatefulWidget {
  final int level;
  final int maxLevel;
  final double hpPercent; // 0.0 to 1.0

  const HullVisual({
    super.key,
    required this.level,
    required this.maxLevel,
    this.hpPercent = 1.0,
  });

  @override
  State<HullVisual> createState() => _HullVisualState();
}

class _HullVisualState extends State<HullVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(120, 120),
          painter: _HullPainter(
            level: widget.level,
            maxLevel: widget.maxLevel,
            hpPercent: widget.hpPercent,
            shimmer: _controller.value,
          ),
        );
      },
    );
  }
}

class _HullPainter extends CustomPainter {
  final int level;
  final int maxLevel;
  final double hpPercent;
  final double shimmer;

  _HullPainter({
    required this.level,
    required this.maxLevel,
    required this.hpPercent,
    required this.shimmer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Shield shape
    final shieldPath = Path();
    final sw = 40.0 + level * 3.0;
    final sh = 50.0 + level * 3.0;
    shieldPath.moveTo(cx, cy - sh / 2);
    shieldPath.quadraticBezierTo(cx + sw / 2, cy - sh / 2 + 5, cx + sw / 2, cy);
    shieldPath.quadraticBezierTo(
        cx + sw / 2 - 5, cy + sh / 2 - 10, cx, cy + sh / 2);
    shieldPath.quadraticBezierTo(
        cx - sw / 2 + 5, cy + sh / 2 - 10, cx - sw / 2, cy);
    shieldPath.quadraticBezierTo(cx - sw / 2, cy - sh / 2 + 5, cx, cy - sh / 2);
    shieldPath.close();

    // Metallic gradient based on level
    final colors = _hullColors[level.clamp(0, _hullColors.length - 1)];
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [colors[0], colors[1], colors[0]],
      stops: [0.0, 0.3 + shimmer * 0.4, 1.0],
    );

    final shieldPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCenter(center: Offset(cx, cy), width: sw, height: sh),
      );
    canvas.drawPath(shieldPath, shieldPaint);

    // Armor plate layers
    final plateLayers = (level + 1).clamp(1, 5);
    for (int i = 0; i < plateLayers; i++) {
      final plateOffset = 3.0 + i * 2.5;
      final platePaint = Paint()
        ..color = colors[0].withValues(alpha: 0.15 + i * 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.save();
      canvas.translate(0, plateOffset * 0.5);
      canvas.drawPath(shieldPath, platePaint);
      canvas.restore();
    }

    // Outline
    final outlinePaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(shieldPath, outlinePaint);

    // Damage cracks when low HP
    if (hpPercent < 0.4) {
      final crackPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final rng = Random(42);
      final crackCount = ((1.0 - hpPercent) * 6).toInt().clamp(1, 5);
      for (int i = 0; i < crackCount; i++) {
        final startX = cx + (rng.nextDouble() - 0.5) * sw * 0.6;
        final startY = cy + (rng.nextDouble() - 0.5) * sh * 0.6;
        final crackPath = Path()..moveTo(startX, startY);
        for (int j = 0; j < 3; j++) {
          crackPath.relativeLineTo(
            (rng.nextDouble() - 0.5) * 12,
            rng.nextDouble() * 8,
          );
        }
        canvas.drawPath(crackPath, crackPaint);
      }
    }

    // Glow for high levels
    if (level >= 5) {
      final glowPaint = Paint()
        ..color = colors[1].withValues(alpha: 0.1 + shimmer * 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawPath(shieldPath, glowPaint);
    }

    _drawLabel(canvas, size, _hullNames[level.clamp(0, _hullNames.length - 1)]);
  }

  static const _hullNames = [
    'STOCK',
    'IRONIUM',
    'BRONZIUM',
    'STEEL',
    'PLATINIUM',
    'EINSTEIN',
    'E-SHIELD',
    'REGEN',
  ];

  static const _hullColors = [
    [Color(0xFF888888), Color(0xFFAAAAAA)], // Stock - grey
    [Color(0xFF7A7A8A), Color(0xFFB0B0C0)], // Ironium
    [Color(0xFF8B6914), Color(0xFFCD853F)], // Bronzium
    [Color(0xFF606878), Color(0xFF98A0B0)], // Steel
    [Color(0xFFB0B0C8), Color(0xFFE0E0F0)], // Platinium
    [Color(0xFF6633CC), Color(0xFF9966FF)], // Einsteinium
    [Color(0xFF0088FF), Color(0xFF44BBFF)], // Energy-shield
    [Color(0xFF00CC44), Color(0xFF44FF88)], // Regenerative
  ];

  @override
  bool shouldRepaint(covariant _HullPainter old) => true;
}

// ─── ENGINE VISUAL ───

class EngineVisual extends StatefulWidget {
  final int level;
  final int maxLevel;

  const EngineVisual({
    super.key,
    required this.level,
    required this.maxLevel,
  });

  @override
  State<EngineVisual> createState() => _EngineVisualState();
}

class _EngineVisualState extends State<EngineVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(120, 120),
          painter: _EnginePainter(
            level: widget.level,
            maxLevel: widget.maxLevel,
            flicker: _controller.value,
          ),
        );
      },
    );
  }
}

class _EnginePainter extends CustomPainter {
  final int level;
  final int maxLevel;
  final double flicker;

  _EnginePainter({
    required this.level,
    required this.maxLevel,
    required this.flicker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rng = Random((flicker * 1000).toInt());

    // Engine block
    final blockW = 40.0 + level * 2.5;
    final blockH = 30.0 + level * 2.0;
    final blockRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(cx, cy - 5), width: blockW, height: blockH),
      const Radius.circular(4),
    );

    // Engine block gradient
    final blockPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4A4A5A), Color(0xFF2A2A3A)],
      ).createShader(blockRect.outerRect);
    canvas.drawRRect(blockRect, blockPaint);

    // Cylinder heads
    final cylinders = [2, 4, 4, 6, 8, 12, 16, 16][level.clamp(0, 7)];
    final cylW = (blockW - 8) / (cylinders / 2).clamp(1, 8);
    for (int i = 0; i < (cylinders / 2).clamp(1, 8).toInt(); i++) {
      final cx2 = blockRect.outerRect.left + 4 + i * cylW + cylW / 2;
      final cylRect = Rect.fromCenter(
        center: Offset(cx2, blockRect.outerRect.top - 3),
        width: cylW * 0.7,
        height: 6,
      );
      canvas.drawRect(cylRect, Paint()..color = const Color(0xFF555568));
      canvas.drawRect(
        cylRect,
        Paint()
          ..color = Colors.white12
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }

    // Engine outline
    canvas.drawRRect(
      blockRect,
      Paint()
        ..color = Colors.white30
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Exhaust flames
    final flameCount = 1 + (level / 2).floor();
    final flameSpacing = blockW / (flameCount + 1);
    for (int i = 0; i < flameCount; i++) {
      final fx = blockRect.outerRect.left + flameSpacing * (i + 1);
      final fy = blockRect.outerRect.bottom;

      final flameH = 15.0 + level * 3.0 + rng.nextDouble() * 8;
      final flameW = 6.0 + level * 0.5;

      // Outer flame (red/orange)
      final outerFlame = Path()
        ..moveTo(fx - flameW, fy)
        ..quadraticBezierTo(
          fx - flameW * 0.3 + rng.nextDouble() * 2,
          fy + flameH * 0.6,
          fx + (rng.nextDouble() - 0.5) * 3,
          fy + flameH,
        )
        ..quadraticBezierTo(
          fx + flameW * 0.3 - rng.nextDouble() * 2,
          fy + flameH * 0.6,
          fx + flameW,
          fy,
        )
        ..close();

      final flameColors = level >= 6
          ? [const Color(0xFF4488FF), const Color(0xFF88CCFF)]
          : level >= 4
              ? [const Color(0xFFFF6600), const Color(0xFFFFCC00)]
              : [const Color(0xFFFF3300), const Color(0xFFFF8800)];

      canvas.drawPath(
        outerFlame,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [flameColors[0], flameColors[1].withValues(alpha: 0.3)],
          ).createShader(Rect.fromLTWH(fx - flameW, fy, flameW * 2, flameH)),
      );

      // Inner flame (white/yellow core)
      final innerH = flameH * 0.5;
      final innerW = flameW * 0.4;
      final innerFlame = Path()
        ..moveTo(fx - innerW, fy)
        ..quadraticBezierTo(fx, fy + innerH * 0.7, fx, fy + innerH)
        ..quadraticBezierTo(fx, fy + innerH * 0.7, fx + innerW, fy)
        ..close();
      canvas.drawPath(
        innerFlame,
        Paint()..color = const Color(0xCCFFFFCC),
      );

      // Flame glow
      canvas.drawCircle(
        Offset(fx, fy + 4),
        flameW + 3,
        Paint()
          ..color = flameColors[0].withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Power text
    final power = [3, 4.5, 6.5, 9, 12, 16, 22, 35][level.clamp(0, 7)];
    final tp = TextPainter(
      text: TextSpan(
        text: '${power}K',
        style: TextStyle(
          color: Colors.amber.withValues(alpha: 0.8),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 - 5));

    _drawLabel(
        canvas, size, _engineNames[level.clamp(0, _engineNames.length - 1)]);
  }

  static const _engineNames = [
    'STOCK',
    'V4 1600',
    'V4 TURBO',
    'V6 3.8L',
    'V8 5.0L',
    'V12 6.0L',
    'V16 JAG',
    'HYPER',
  ];

  @override
  bool shouldRepaint(covariant _EnginePainter old) => true;
}

// ─── RADIATOR VISUAL ───

class RadiatorVisual extends StatefulWidget {
  final int level;
  final int maxLevel;

  const RadiatorVisual({
    super.key,
    required this.level,
    required this.maxLevel,
  });

  @override
  State<RadiatorVisual> createState() => _RadiatorVisualState();
}

class _RadiatorVisualState extends State<RadiatorVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(120, 120),
          painter: _RadiatorPainter(
            level: widget.level,
            maxLevel: widget.maxLevel,
            phase: _controller.value,
          ),
        );
      },
    );
  }
}

class _RadiatorPainter extends CustomPainter {
  final int level;
  final int maxLevel;
  final double phase;

  _RadiatorPainter({
    required this.level,
    required this.maxLevel,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Core unit
    final coreSize = 20.0 + level * 2.0;
    final coreRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: coreSize,
      height: coreSize,
    );

    // Blue glow that intensifies
    final glowIntensity = 0.05 + (level / maxLevel.clamp(1, 100)) * 0.2;
    final glowRadius = coreSize + 10 + level * 4.0;
    canvas.drawCircle(
      Offset(cx, cy),
      glowRadius,
      Paint()
        ..color = const Color(0xFF0088FF).withValues(alpha: glowIntensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );

    // Radiator fins
    final finCount = 4 + level;
    final finLength = 15.0 + level * 2.5;
    const finWidth = 3.0;
    for (int i = 0; i < finCount; i++) {
      final angle = (i / finCount) * 2 * pi + phase * 0.3;
      final x1 = cx + cos(angle) * (coreSize / 2);
      final y1 = cy + sin(angle) * (coreSize / 2);
      final x2 = cx + cos(angle) * (coreSize / 2 + finLength);
      final y2 = cy + sin(angle) * (coreSize / 2 + finLength);

      final finPaint = Paint()
        ..color = Color.lerp(
          const Color(0xFF4488AA),
          const Color(0xFF88CCFF),
          (sin(phase * 2 * pi + i) + 1) / 2,
        )!
        ..strokeWidth = finWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), finPaint);
    }

    // Core body
    final corePaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFF3366AA),
          Color(0xFF1A2A44),
        ],
      ).createShader(coreRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(coreRect, const Radius.circular(4)),
      corePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(coreRect, const Radius.circular(4)),
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Frost crystals for higher levels
    if (level >= 2) {
      final crystalCount = level;
      final rng = Random(7);
      for (int i = 0; i < crystalCount; i++) {
        final angle = rng.nextDouble() * 2 * pi;
        final dist = coreSize / 2 + 5 + rng.nextDouble() * finLength * 0.8;
        final fx = cx + cos(angle) * dist;
        final fy = cy + sin(angle) * dist;

        // Animate crystal opacity with phase offset
        final crystalAlpha =
            (sin(phase * 2 * pi + i * 1.5) + 1) / 2 * 0.6 + 0.2;

        // Draw a small snowflake/crystal shape
        final crystalSize = 2.0 + rng.nextDouble() * 3;
        final crystalPaint = Paint()
          ..color = const Color(0xFFAADDFF).withValues(alpha: crystalAlpha)
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round;

        for (int j = 0; j < 3; j++) {
          final a = j * pi / 3;
          canvas.drawLine(
            Offset(fx + cos(a) * crystalSize, fy + sin(a) * crystalSize),
            Offset(fx - cos(a) * crystalSize, fy - sin(a) * crystalSize),
            crystalPaint,
          );
        }
      }
    }

    // Frost particles floating upward
    if (level >= 3) {
      final particleCount = level - 1;
      for (int i = 0; i < particleCount; i++) {
        final px = cx +
            sin(phase * 2 * pi * 0.7 + i * 2.3) * (coreSize + finLength * 0.5);
        final py = cy - (phase + i * 0.15) % 1.0 * 30 - 10;
        final pAlpha = (1.0 - ((phase + i * 0.15) % 1.0)) * 0.5;
        canvas.drawCircle(
          Offset(px, py),
          1.5,
          Paint()..color = const Color(0xFF88CCFF).withValues(alpha: pAlpha),
        );
      }
    }

    _drawLabel(canvas, size,
        _radiatorNames[level.clamp(0, _radiatorNames.length - 1)]);
  }

  static const _radiatorNames = [
    'STOCK FAN',
    'DUAL FANS',
    'TURBINE',
    'DUAL TURB',
    'PURON',
    'TRI-TURB',
    'MAGMA CVT',
  ];

  @override
  bool shouldRepaint(covariant _RadiatorPainter old) => true;
}

// ─── CARGO BAY VISUAL ───

class CargoBayVisual extends StatefulWidget {
  final int level;
  final int maxLevel;
  final double fillPercent; // 0.0 to 1.0

  const CargoBayVisual({
    super.key,
    required this.level,
    required this.maxLevel,
    this.fillPercent = 0.0,
  });

  @override
  State<CargoBayVisual> createState() => _CargoBayVisualState();
}

class _CargoBayVisualState extends State<CargoBayVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(120, 120),
          painter: _CargoBayPainter(
            level: widget.level,
            maxLevel: widget.maxLevel,
            fillPercent: widget.fillPercent,
            pulse: _controller.value,
          ),
        );
      },
    );
  }
}

class _CargoBayPainter extends CustomPainter {
  final int level;
  final int maxLevel;
  final double fillPercent;
  final double pulse;

  _CargoBayPainter({
    required this.level,
    required this.maxLevel,
    required this.fillPercent,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Container size scales with level
    final scale = 0.55 + (level / maxLevel.clamp(1, 100)) * 0.45;
    final boxW = 55.0 * scale;
    final boxH = 45.0 * scale;
    final boxRect = Rect.fromCenter(
      center: Offset(cx, cy + 2),
      width: boxW,
      height: boxH,
    );

    // 3D perspective - draw side panel
    final depthOffset = 8.0 * scale;
    final sidePath = Path()
      ..moveTo(boxRect.right, boxRect.top)
      ..lineTo(boxRect.right + depthOffset, boxRect.top - depthOffset)
      ..lineTo(boxRect.right + depthOffset, boxRect.bottom - depthOffset)
      ..lineTo(boxRect.right, boxRect.bottom)
      ..close();
    canvas.drawPath(sidePath, Paint()..color = const Color(0xFF2A2A38));

    // Top panel
    final topPath = Path()
      ..moveTo(boxRect.left, boxRect.top)
      ..lineTo(boxRect.left + depthOffset, boxRect.top - depthOffset)
      ..lineTo(boxRect.right + depthOffset, boxRect.top - depthOffset)
      ..lineTo(boxRect.right, boxRect.top)
      ..close();
    canvas.drawPath(topPath, Paint()..color = const Color(0xFF3A3A4A));

    // Main face
    canvas.drawRect(boxRect, Paint()..color = const Color(0xFF222233));

    // Fill indicator
    if (fillPercent > 0) {
      final fillH = boxH * fillPercent;
      final fillRect = Rect.fromLTWH(
        boxRect.left + 2,
        boxRect.bottom - fillH - 2,
        boxW - 4,
        fillH,
      );
      final fillColor = Color.lerp(
        const Color(0xFF336633),
        const Color(0xFFCC6633),
        fillPercent,
      )!;
      canvas.drawRect(
          fillRect, Paint()..color = fillColor.withValues(alpha: 0.5));

      // Ore chunks inside
      final rng = Random(13);
      final oreCount = (fillPercent * 8).ceil().clamp(0, 8);
      for (int i = 0; i < oreCount; i++) {
        final ox = fillRect.left + rng.nextDouble() * fillRect.width;
        final oy = fillRect.top + rng.nextDouble() * fillRect.height;
        final oreSize = 2.0 + rng.nextDouble() * 3;
        final oreColors = [
          const Color(0xFF8B6914),
          const Color(0xFFC0C0C0),
          const Color(0xFFFFD700),
          const Color(0xFF00CC66),
        ];
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset(ox, oy), width: oreSize, height: oreSize),
          Paint()..color = oreColors[i % oreColors.length],
        );
      }
    }

    // Outlines
    final outlinePaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(boxRect, outlinePaint);
    canvas.drawPath(sidePath, outlinePaint);
    canvas.drawPath(topPath, outlinePaint);

    // Lock/latch details
    final latchY = boxRect.top + boxH * 0.35;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, latchY), width: boxW * 0.3, height: 3),
      Paint()..color = Colors.amber.withValues(alpha: 0.5),
    );

    // Capacity text
    final cap = [50, 100, 200, 400, 750, 1200, 2500][level.clamp(0, 6)];
    final tp = TextPainter(
      text: TextSpan(
        text: '${cap}kg',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, boxRect.bottom - tp.height - 4));

    // Portal glow for last level
    if (level >= 6) {
      final portalAlpha = 0.1 + sin(pulse * 2 * pi) * 0.05;
      canvas.drawCircle(
        Offset(cx, cy),
        boxW * 0.6,
        Paint()
          ..color = const Color(0xFF9933FF).withValues(alpha: portalAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    _drawLabel(
        canvas, size, _cargoNames[level.clamp(0, _cargoNames.length - 1)]);
  }

  static const _cargoNames = [
    'MICRO',
    'MEDIUM',
    'HUGE',
    'GIGANTIC',
    'TITANIC',
    'LEVIATHAN',
    'WORMHOLE',
  ];

  @override
  bool shouldRepaint(covariant _CargoBayPainter old) => true;
}

// ─── DRILL VISUAL WIDGET (wraps sprite with glow) ───

class DrillVisualWidget extends StatefulWidget {
  final int level;
  final int maxLevel;

  const DrillVisualWidget({
    super.key,
    required this.level,
    required this.maxLevel,
  });

  @override
  State<DrillVisualWidget> createState() => _DrillVisualWidgetState();
}

class _DrillVisualWidgetState extends State<DrillVisualWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _drillAssets = {
    0: 'assets/images/drills/drill_basic.png',
    1: 'assets/images/drills/drill_silver.png',
    2: 'assets/images/drills/drill_gold.png',
    3: 'assets/images/drills/drill_emerald.png',
    4: 'assets/images/drills/drill_magma.png',
    5: 'assets/images/drills/drill_diamond.png',
  };

  static const _drillGlowColors = [
    Color(0xFF888888), // basic - grey
    Color(0xFFC0C0C0), // silver
    Color(0xFFFFD700), // gold
    Color(0xFF00CC66), // emerald
    Color(0xFFFF4400), // magma
    Color(0xFF44CCFF), // diamond
    Color(0xFF00FFAA), // amazonite
    Color(0xFFFF00FF), // multi
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowColor =
        _drillGlowColors[widget.level.clamp(0, _drillGlowColors.length - 1)];
    final assetPath = _drillAssets[widget.level.clamp(0, 5)];

    return SizedBox(
      width: 120,
      height: 120,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final glowOpacity = 0.2 + _controller.value * 0.3;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Glow aura
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(alpha: glowOpacity),
                      blurRadius: 20 + widget.level * 3.0,
                      spreadRadius: 2 + widget.level * 1.0,
                    ),
                  ],
                ),
              ),
              // Drill sprite
              if (assetPath != null)
                Image.asset(
                  assetPath,
                  width: 72,
                  height: 72,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _fallbackDrill(),
                )
              else
                _fallbackDrill(),
              // Level label at bottom
              Positioned(
                bottom: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _drillNames[widget.level.clamp(0, _drillNames.length - 1)],
                    style: TextStyle(
                      color: glowColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fallbackDrill() {
    return const Icon(Icons.hardware, color: Colors.amber, size: 48);
  }

  static const _drillNames = [
    'STOCK',
    'SILVIDE',
    'GOLDIUM',
    'EMERALD',
    'RUBY',
    'DIAMOND',
    'AMAZONITE',
    'MULTI',
  ];
}

// ─── SHARED LABEL HELPER ───

void _drawLabel(Canvas canvas, Size size, String text) {
  final bgRect = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(size.width / 2, size.height - 8),
      width: text.length * 6.5 + 10,
      height: 14,
    ),
    const Radius.circular(3),
  );
  canvas.drawRRect(bgRect, Paint()..color = const Color(0xAA000000));

  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        color: Color(0xCCFFBB33),
        fontSize: 10,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
        letterSpacing: 0.5,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(
    canvas,
    Offset(size.width / 2 - tp.width / 2, size.height - 8 - tp.height / 2),
  );
}
