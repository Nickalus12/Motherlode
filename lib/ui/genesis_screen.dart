import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:motherlode/world/genesis_pipeline.dart';

// ---------------------------------------------------------------------------
// Phase display data
// ---------------------------------------------------------------------------

const _phaseInfo = <GenesisPhase, (String, String, String)>{
  GenesisPhase.tectonicFormation: (
    'FORMING BEDROCK',
    'Pressure and heat forge the foundation of your world',
    '4.6 Billion Years Ago',
  ),
  GenesisPhase.volcanicIntrusion: (
    'VOLCANIC ACTIVITY',
    'Magma chambers form deep beneath the crust',
    '3.8 Billion Years Ago',
  ),
  GenesisPhase.mineralSeeding: (
    'CRYSTALLIZATION',
    'Minerals precipitate from superheated fluid',
    '2.5 Billion Years Ago',
  ),
  GenesisPhase.waterTableBirth: (
    'DEEP AQUIFERS',
    'Water seeps through porous stone',
    '1.2 Billion Years Ago',
  ),
  GenesisPhase.greatErosion: (
    'THE GREAT EROSION',
    'Rivers carve through ancient stone',
    '500 Million Years Ago',
  ),
  GenesisPhase.caveNetworks: (
    'CAVE FORMATION',
    'Vast caverns hollow beneath the surface',
    '100 Million Years Ago',
  ),
  GenesisPhase.oreMaturation: (
    'ORE VEINS MATURE',
    'Precious metals settle into their final form',
    '10 Million Years Ago',
  ),
  GenesisPhase.surfaceWeathering: (
    'SURFACE DETAIL',
    'Wind and rain sculpt the landscape',
    '10,000 Years Ago',
  ),
  GenesisPhase.worldReady: (
    'WORLD READY',
    'The earth is ready. Begin your descent.',
    'Present Day',
  ),
};

const _phaseAccent = <GenesisPhase, Color>{
  GenesisPhase.tectonicFormation: Color(0xFFFF4400),
  GenesisPhase.volcanicIntrusion: Color(0xFFFF6600),
  GenesisPhase.mineralSeeding: Color(0xFF50C878),
  GenesisPhase.waterTableBirth: Color(0xFF4488CC),
  GenesisPhase.greatErosion: Color(0xFF6699CC),
  GenesisPhase.caveNetworks: Color(0xFF887766),
  GenesisPhase.oreMaturation: Color(0xFFFFD700),
  GenesisPhase.surfaceWeathering: Color(0xFF88AA66),
  GenesisPhase.worldReady: Color(0xFFFFCC44),
};

// ---------------------------------------------------------------------------
// Genesis Screen Widget
// ---------------------------------------------------------------------------

class GenesisScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final Stream<(GenesisPhase, double)>? progressStream;

  const GenesisScreen({
    super.key,
    required this.onComplete,
    this.progressStream,
  });

  @override
  State<GenesisScreen> createState() => _GenesisScreenState();
}

class _GenesisScreenState extends State<GenesisScreen>
    with TickerProviderStateMixin {
  StreamSubscription<(GenesisPhase, double)>? _progressSubscription;

  GenesisPhase _currentPhase = GenesisPhase.tectonicFormation;
  double _phaseProgress = 0.0;
  double _overallProgress = 0.0;
  bool _worldReady = false;
  bool _exiting = false;

  late final AnimationController _pulseController;
  late final AnimationController _particleController;
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _progressSubscription = widget.progressStream?.listen((event) {
      if (!mounted) return;
      setState(() {
        _currentPhase = event.$1;
        _phaseProgress = event.$2;
        _overallProgress = GenesisPipeline.overallProgress(
          event.$1,
          event.$2,
        );
        if (event.$1 == GenesisPhase.worldReady && event.$2 >= 1.0) {
          _worldReady = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _pulseController.dispose();
    _particleController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!_worldReady || _exiting) return;
    setState(() => _exiting = true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final info = _phaseInfo[_currentPhase];
    final title = info?.$1 ?? '';
    final description = info?.$2 ?? '';
    final year = info?.$3 ?? '';
    final accent = _phaseAccent[_currentPhase] ?? Colors.orange;

    return GestureDetector(
      onTap: _onTap,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Animated background gradient that shifts with phase
            AnimatedBuilder(
              animation: _bgController,
              builder: (context, _) {
                final wave = sin(_bgController.value * pi * 2) * 0.03;
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, 0.3 + wave),
                      radius: 1.2,
                      colors: [
                        Color.lerp(const Color(0xFF0A0A0A), accent, 0.08 + wave)!,
                        const Color(0xFF050505),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                );
              },
            ),

            // Floating particle system
            AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _GenesisParticlePainter(
                    phase: _particleController.value,
                    accentColor: accent,
                    intensity: _overallProgress,
                  ),
                );
              },
            ),

            // Horizontal accent lines (geological strata feel)
            AnimatedBuilder(
              animation: _bgController,
              builder: (context, _) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _StrataLinesPainter(
                    phase: _bgController.value,
                    accent: accent,
                    progress: _overallProgress,
                  ),
                );
              },
            ),

            // Center content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 3),

                    // Year / era label
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: Text(
                        year.toUpperCase(),
                        key: ValueKey(year),
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Phase title with glow
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        title,
                        key: ValueKey(title),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 5,
                          decoration: TextDecoration.none,
                          shadows: [
                            Shadow(
                              color: accent.withValues(alpha: 0.4),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Accent line under title
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, _) {
                        final pulse = _pulseController.value;
                        return Container(
                          width: 120 + 20 * pulse,
                          height: 1.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                accent.withValues(alpha: 0.4 + 0.2 * pulse),
                                accent.withValues(alpha: 0.4 + 0.2 * pulse),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.2 * pulse),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Description
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      child: Text(
                        description,
                        key: ValueKey(description),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                          letterSpacing: 0.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Custom phase progress bar
                    _buildPhaseProgress(accent),

                    const Spacer(flex: 2),

                    // Overall progress
                    _buildOverallProgress(accent),

                    const SizedBox(height: 28),

                    // Tap to begin
                    if (_worldReady)
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final pulse = _pulseController.value;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: accent.withValues(alpha: 0.3 + 0.3 * pulse),
                              ),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.1 * pulse),
                                  blurRadius: 20,
                                  spreadRadius: -4,
                                ),
                              ],
                            ),
                            child: Opacity(
                              opacity: 0.5 + 0.5 * pulse,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          'TAP TO BEGIN',
                          style: TextStyle(
                            color: accent,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 6,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 47),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseProgress(Color accent) {
    final percent = (_phaseProgress * 100).round();
    return Column(
      children: [
        // Phase progress percentage
        Text(
          '$percent%',
          style: TextStyle(
            color: accent.withValues(alpha: 0.6),
            fontSize: 36,
            fontWeight: FontWeight.w100,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 16),
        // Custom progress bar
        SizedBox(
          width: 220,
          height: 4,
          child: CustomPaint(
            painter: _ProgressBarPainter(
              progress: _phaseProgress.clamp(0.0, 1.0),
              color: accent,
              glowIntensity: _pulseController.value,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverallProgress(Color accent) {
    return Column(
      children: [
        // Phase dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: GenesisPhase.values.map((phase) {
            final isDone = phase.index < _currentPhase.index;
            final isCurrent = phase == _currentPhase;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isCurrent ? 12 : 6,
                height: isCurrent ? 4 : 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: isDone
                      ? accent.withValues(alpha: 0.5)
                      : isCurrent
                          ? accent
                          : Colors.white.withValues(alpha: 0.08),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // Overall progress bar
        SizedBox(
          width: 260,
          height: 2,
          child: CustomPaint(
            painter: _ProgressBarPainter(
              progress: _overallProgress.clamp(0.0, 1.0),
              color: Colors.white.withValues(alpha: 0.3),
              glowIntensity: 0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(_overallProgress * 100).round()}% complete',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.18),
            fontSize: 10,
            fontWeight: FontWeight.w400,
            letterSpacing: 1,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painters
// ---------------------------------------------------------------------------

/// Floating particles that rise upward with the phase accent color.
class _GenesisParticlePainter extends CustomPainter {
  final double phase;
  final Color accentColor;
  final double intensity;

  _GenesisParticlePainter({
    required this.phase,
    required this.accentColor,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final paint = Paint()..style = PaintingStyle.fill;
    final count = 30 + (intensity * 40).toInt();

    for (int i = 0; i < count; i++) {
      final baseX = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final speed = 0.3 + rng.nextDouble() * 1.2;
      final pSize = 0.5 + rng.nextDouble() * 2.0;

      // Rise upward, drift sideways
      final x = baseX + sin(phase * pi * 2 * speed + i * 0.7) * 20;
      final y = (baseY - phase * size.height * speed * 0.15) % size.height;

      final alpha =
          (0.1 + 0.4 * sin(phase * pi * 2 + i * 0.3)).clamp(0.0, 1.0) *
              (0.5 + intensity * 0.5);

      if (alpha < 0.02) continue;

      // Mix between accent and warm ember colors
      final t = rng.nextDouble();
      final r = accentColor.r * (1 - t) + 1.0 * t;
      final g = accentColor.g * (1 - t) + 0.4 * t;
      final b = accentColor.b * (1 - t);

      paint.color = Color.from(
        alpha: alpha,
        red: r.clamp(0.0, 1.0),
        green: g.clamp(0.0, 1.0),
        blue: b.clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(x, y), pSize, paint);

      // Glow around larger particles
      if (pSize > 1.5) {
        paint.color = Color.from(
          alpha: alpha * 0.12,
          red: r.clamp(0.0, 1.0),
          green: g.clamp(0.0, 1.0),
          blue: b.clamp(0.0, 1.0),
        );
        canvas.drawCircle(Offset(x, y), pSize * 4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GenesisParticlePainter old) => true;
}

/// Horizontal strata-like lines that slowly drift, giving geological feel.
class _StrataLinesPainter extends CustomPainter {
  final double phase;
  final Color accent;
  final double progress;

  _StrataLinesPainter({
    required this.phase,
    required this.accent,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;
    final lineCount = 5 + (progress * 8).toInt();

    for (int i = 0; i < lineCount; i++) {
      final yBase = size.height * (0.1 + i * 0.08);
      final y = yBase + sin(phase * pi * 2 + i * 1.5) * 15;
      final alpha = (0.02 + 0.04 * sin(phase * pi * 2 + i)).clamp(0.0, 0.08);

      paint.color = accent.withValues(alpha: alpha);
      paint.strokeWidth = 0.5 + sin(i * 0.8) * 0.3;

      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x <= size.width; x += 20) {
        final localY = y + sin(x * 0.005 + phase * pi * 2 + i) * 8;
        path.lineTo(x, localY);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrataLinesPainter old) => true;
}

/// Custom progress bar with rounded ends and optional glow.
class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double glowIntensity;

  _ProgressBarPainter({
    required this.progress,
    required this.color,
    required this.glowIntensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final r = h / 2;

    // Track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, h),
        Radius.circular(r),
      ),
      trackPaint,
    );

    if (progress <= 0) return;

    final fillWidth = size.width * progress;

    // Glow behind fill
    if (glowIntensity > 0) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.15 * glowIntensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, -2, fillWidth, h + 4),
          Radius.circular(r + 2),
        ),
        glowPaint,
      );
    }

    // Fill bar
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, fillWidth, h),
        Radius.circular(r),
      ),
      fillPaint,
    );

    // Bright tip
    final tipPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(fillWidth - r, h / 2),
      r * 0.6,
      tipPaint,
    );
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.glowIntensity != glowIntensity;
}
