import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';

import 'package:hellbore/entities/pod/pod.dart';

/// Procedurally renders the mining pod sprite, drill arm, and engine exhaust
///
/// No sprite sheets - everything is drawn with Canvas primitives
class PodRenderer extends Component {
  final Pod pod;
  double _time = 0;

  PodRenderer({required this.pod});

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();

    // Pod body (rounded trapezoid shape)
    _drawBody(canvas);

    // Cockpit window
    _drawCockpit(canvas);

    // Drill arm at bottom
    _drawDrill(canvas);

    // Engine exhausts
    if (pod.thrustUp || pod.state == PodState.flying) {
      _drawExhaust(canvas);
    }

    // Headlight beam
    _drawHeadlight(canvas);

    // Damage indicators
    if (pod.state != PodState.dead) {
      _drawStatusIndicators(canvas);
    }

    canvas.restore();
  }

  void _drawBody(Canvas canvas) {
    final bodyPath = Path();

    // Main hull shape (trapezoid with rounded feel)
    bodyPath.moveTo(-0.7, -0.8); // Top-left
    bodyPath.lineTo(0.7, -0.8); // Top-right
    bodyPath.lineTo(0.8, 0.4); // Bottom-right (wider)
    bodyPath.lineTo(0.6, 0.9); // Bottom-right corner
    bodyPath.lineTo(-0.6, 0.9); // Bottom-left corner
    bodyPath.lineTo(-0.8, 0.4); // Bottom-left (wider)
    bodyPath.close();

    // Main body fill
    final bodyPaint = Paint()
      ..color = const Color(0xFF4A6741) // Military green
      ..style = PaintingStyle.fill;
    canvas.drawPath(bodyPath, bodyPaint);

    // Outline
    final outlinePaint = Paint()
      ..color = const Color(0xFF2D3F28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06;
    canvas.drawPath(bodyPath, outlinePaint);

    // Side panels
    final panelPaint = Paint()
      ..color = const Color(0xFF3D5A36)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      const Rect.fromLTWH(-0.65, -0.3, 0.2, 0.8),
      panelPaint,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0.45, -0.3, 0.2, 0.8),
      panelPaint,
    );

    // Rivets / detail dots
    final rivetPaint = Paint()
      ..color = const Color(0xFF5A7A50)
      ..style = PaintingStyle.fill;
    for (final offset in [
      const Offset(-0.4, -0.5),
      const Offset(0.4, -0.5),
      const Offset(-0.5, 0.2),
      const Offset(0.5, 0.2),
    ]) {
      canvas.drawCircle(offset, 0.04, rivetPaint);
    }
  }

  void _drawCockpit(Canvas canvas) {
    // Cockpit glass (slightly tinted blue)
    final glassPath = Path();
    glassPath.moveTo(-0.35, -0.75);
    glassPath.lineTo(0.35, -0.75);
    glassPath.lineTo(0.3, -0.35);
    glassPath.lineTo(-0.3, -0.35);
    glassPath.close();

    final glassPaint = Paint()
      ..color = const Color(0x8044AACC)
      ..style = PaintingStyle.fill;
    canvas.drawPath(glassPath, glassPaint);

    // Glass reflection
    final reflectionPaint = Paint()
      ..color = const Color(0x3066DDFF)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      const Rect.fromLTWH(-0.2, -0.7, 0.15, 0.15),
      reflectionPaint,
    );
  }

  void _drawDrill(Canvas canvas) {
    // Drill arm
    final drillColor = pod.state == PodState.drilling
        ? Color.lerp(
            const Color(0xFFAAAAAA),
            const Color(0xFFFFAA00),
            (sin(_time * 20) + 1) / 2,
          )!
        : const Color(0xFFAAAAAA);

    // Drill shaft
    final shaftPaint = Paint()
      ..color = drillColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      const Rect.fromLTWH(-0.08, 0.85, 0.16, 0.35),
      shaftPaint,
    );

    // Drill bit (triangle)
    final bitPath = Path();
    bitPath.moveTo(-0.12, 1.2);
    bitPath.lineTo(0.12, 1.2);
    bitPath.lineTo(0.0, 1.45);
    bitPath.close();

    canvas.drawPath(bitPath, shaftPaint);

    // Drill rotation effect while drilling
    if (pod.state == PodState.drilling) {
      final spiralPaint = Paint()
        ..color = const Color(0x60FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03;

      final rotation = _time * 15;
      for (int i = 0; i < 3; i++) {
        final angle = rotation + i * (2 * pi / 3);
        final y = 0.9 + (sin(angle) + 1) * 0.15;
        final x = cos(angle) * 0.06;
        canvas.drawCircle(Offset(x, y), 0.02, spiralPaint);
      }
    }
  }

  void _drawExhaust(Canvas canvas) {
    // Engine nozzles on sides
    final nozzlePaint = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      const Rect.fromLTWH(-0.85, 0.2, 0.15, 0.2),
      nozzlePaint,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0.7, 0.2, 0.15, 0.2),
      nozzlePaint,
    );

    // Exhaust flames
    final flamePhase = _time * 20;
    for (int side = -1; side <= 1; side += 2) {
      final baseX = side * 0.77;
      for (int i = 0; i < 4; i++) {
        final flicker = sin(flamePhase + i * 1.5) * 0.1;
        final flameLength = 0.3 + i * 0.08 + flicker;
        final flameWidth = 0.06 - i * 0.01;
        final t = i / 4.0;
        final flameColor = Color.lerp(
          const Color(0xFFFFFFCC), // White-hot
          const Color(0xFFFF4400), // Orange
          t,
        )!.withValues(alpha: 1.0 - t * 0.5);

        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(baseX, 0.5 + flameLength / 2),
            width: flameWidth,
            height: flameLength,
          ),
          Paint()
            ..color = flameColor
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  void _drawHeadlight(Canvas canvas) {
    // Small headlight dot at top
    final lightPaint = Paint()
      ..color = const Color(0xCCFFFFAA)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(0, -0.8), 0.06, lightPaint);

    // Light glow
    final glowPaint = Paint()
      ..color = const Color(0x30FFFFCC)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(0, -0.8), 0.12, glowPaint);
  }

  void _drawStatusIndicators(Canvas canvas) {
    // Cargo weight indicator (small bar on side)
    final cargoRatio = pod.cargoSystem.fillRatio;
    if (cargoRatio > 0) {
      final cargoColor = cargoRatio > 0.9
          ? const Color(0xFFFF0000)
          : const Color(0xFF00CCCC);
      canvas.drawRect(
        Rect.fromLTWH(-0.9, 0.6 - cargoRatio * 0.5, 0.04, cargoRatio * 0.5),
        Paint()..color = cargoColor,
      );
    }
  }
}
