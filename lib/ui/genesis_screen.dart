import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:motherlode/world/genesis_pipeline.dart';

// ---------------------------------------------------------------------------
// Phase accent colors
// ---------------------------------------------------------------------------

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
// Particle types
// ---------------------------------------------------------------------------

const _typeRock = 0;
const _typeMagma = 1;
const _typeOre = 2;
const _typeWater = 3;
const _typeGrass = 4;

// ---------------------------------------------------------------------------
// Particle data (plain class, minimal overhead)
// ---------------------------------------------------------------------------

class _Particle {
  double x, y, vx, vy, radius;
  Color color;
  int type;
  int spawnFrame; // for age-based removal

  _Particle({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.radius = 3.0,
    this.color = const Color(0xFF3A2A1A),
    this.type = _typeRock,
    this.spawnFrame = 0,
  });

  // Initialized as fields, not constructor params (avoids unused-param warnings)
  double life = 1.0;
  bool settled = false;
}

// ---------------------------------------------------------------------------
// Spatial hash for O(n) neighbor lookups
// ---------------------------------------------------------------------------

class _SpatialHash {
  static const double cellSize = 10.0;
  final Map<int, List<int>> _cells = {};

  void clear() => _cells.clear();

  int _key(double x, double y) {
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    // Pack two ints into one using Cantor pairing
    return cx * 73856093 ^ cy * 19349663;
  }

  void insert(int index, double x, double y) {
    final key = _key(x, y);
    (_cells[key] ??= []).add(index);
  }

  /// Returns indices of particles in the same and neighboring cells.
  void queryNeighbors(double x, double y, List<int> result) {
    result.clear();
    final cx = (x / cellSize).floor();
    final cy = (y / cellSize).floor();
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final key = (cx + dx) * 73856093 ^ (cy + dy) * 19349663;
        final cell = _cells[key];
        if (cell != null) result.addAll(cell);
      }
    }
  }
}

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
  double _overallProgress = 0.0;
  bool _worldReady = false;
  bool _exiting = false;

  late final AnimationController _pulseController;
  late final AnimationController _simController;
  late final AnimationController _enterController;
  late final AnimationController _exitController;

  // Physics sim state
  final List<_Particle> _particles = [];
  final _SpatialHash _spatialHash = _SpatialHash();
  final Random _rng = Random(42);
  int _frameCount = 0;
  double _lastTime = 0;

  // Pre-allocated paint objects
  final Paint _solidPaint = Paint()..style = PaintingStyle.fill;
  final Paint _glowPaint = Paint()..style = PaintingStyle.fill;

  // Reusable neighbor list
  final List<int> _neighborBuf = [];

  // Pod descent for worldReady phase
  double _podY = -30;
  bool _podActive = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _simController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _simController.addListener(_tick);

    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _progressSubscription = widget.progressStream?.listen((event) {
      if (!mounted) return;
      setState(() {
        _currentPhase = event.$1;
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
    _simController.removeListener(_tick);
    _pulseController.dispose();
    _simController.dispose();
    _enterController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!_worldReady || _exiting) return;
    setState(() => _exiting = true);
    _exitController.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  // -----------------------------------------------------------------------
  // Physics simulation tick
  // -----------------------------------------------------------------------

  void _tick() {
    final now = _simController.lastElapsedDuration?.inMicroseconds ?? 0;
    final nowSec = now / 1000000.0;
    var dt = nowSec - _lastTime;
    _lastTime = nowSec;

    // Clamp dt to avoid explosion on first frame or tab-away
    if (dt <= 0 || dt > 0.05) dt = 0.016;

    final size = MediaQuery.of(context).size;
    final screenW = size.width;
    final screenH = size.height;

    // Spawn particles based on phase
    if (_currentPhase != GenesisPhase.worldReady) {
      _spawnParticles(screenW, screenH);
    } else if (!_podActive) {
      _podActive = true;
      _podY = -30;
    }

    // Pod descent animation
    if (_podActive && _podY < _findTopSurface(screenW / 2, screenH) - 20) {
      _podY += 40 * dt;
    }

    // Rebuild spatial hash
    _spatialHash.clear();
    for (int i = 0; i < _particles.length; i++) {
      _spatialHash.insert(i, _particles[i].x, _particles[i].y);
    }

    // Physics update
    const gravity = 200.0;
    const bounceDamp = 0.3;
    const friction = 0.98;

    for (int i = 0; i < _particles.length; i++) {
      final p = _particles[i];

      // Phase-specific forces
      _applyPhaseForces(p, dt);

      // Dissolving particles (cave phase)
      if (p.life <= 0) continue;

      if (!p.settled || p.type == _typeWater) {
        // Gravity
        p.vy += gravity * dt;

        // Apply velocity
        p.x += p.vx * dt;
        p.y += p.vy * dt;

        // Horizontal friction
        p.vx *= friction;

        // Floor collision
        if (p.y + p.radius > screenH) {
          p.y = screenH - p.radius;
          p.vy = -p.vy * bounceDamp;
          p.vx *= 0.9;
          if (p.vy.abs() < 5) {
            p.vy = 0;
            p.settled = true;
          }
        }

        // Wall collision
        if (p.x - p.radius < 0) {
          p.x = p.radius;
          p.vx = -p.vx * bounceDamp;
        } else if (p.x + p.radius > screenW) {
          p.x = screenW - p.radius;
          p.vx = -p.vx * bounceDamp;
        }

        // Particle-particle collision (only check neighbors)
        _spatialHash.queryNeighbors(p.x, p.y, _neighborBuf);
        for (final j in _neighborBuf) {
          if (j <= i) continue;
          final q = _particles[j];
          final dx = q.x - p.x;
          final dy = q.y - p.y;
          final dist = sqrt(dx * dx + dy * dy);
          final minDist = p.radius + q.radius;
          if (dist < minDist && dist > 0.01) {
            final nx = dx / dist;
            final ny = dy / dist;
            final overlap = (minDist - dist) * 0.5;
            p.x -= nx * overlap;
            p.y -= ny * overlap;
            q.x += nx * overlap;
            q.y += ny * overlap;

            // Simple elastic-ish response
            final relVx = p.vx - q.vx;
            final relVy = p.vy - q.vy;
            final relDot = relVx * nx + relVy * ny;
            if (relDot > 0) {
              final impulse = relDot * bounceDamp;
              p.vx -= impulse * nx;
              p.vy -= impulse * ny;
              q.vx += impulse * nx;
              q.vy += impulse * ny;
            }

            // Settling check
            if (p.vy.abs() < 3 && p.y + p.radius >= screenH - 1) {
              p.settled = true;
              p.vy = 0;
            }
            if (q.vy.abs() < 3 && q.y + q.radius >= screenH - 1) {
              q.settled = true;
              q.vy = 0;
            }
          }
        }

        // Settle if barely moving and on floor
        if (p.vy.abs() < 2 && p.vx.abs() < 2 &&
            p.y + p.radius >= screenH - 2) {
          p.settled = true;
          p.vy = 0;
        }
      }
    }

    // Remove dead particles
    _particles.removeWhere((p) => p.life <= 0);

    // Cap at 400: remove oldest settled particles
    while (_particles.length > 400) {
      final idx = _particles.indexWhere((p) => p.settled);
      if (idx >= 0) {
        _particles.removeAt(idx);
      } else {
        _particles.removeAt(0);
      }
    }

    _frameCount++;
    setState(() {});
  }

  void _spawnParticles(double screenW, double screenH) {
    final count = 3 + _rng.nextInt(3); // 3-5 per frame
    for (int i = 0; i < count; i++) {
      switch (_currentPhase) {
        case GenesisPhase.tectonicFormation:
          _spawnRock(screenW, screenH);
          break;
        case GenesisPhase.volcanicIntrusion:
          _spawnMagma(screenW, screenH);
          break;
        case GenesisPhase.mineralSeeding:
          _spawnOre(screenW, screenH);
          break;
        case GenesisPhase.waterTableBirth:
          _spawnWater(screenW, screenH);
          break;
        case GenesisPhase.greatErosion:
          _applyErosionWind();
          break;
        case GenesisPhase.caveNetworks:
          _dissolveSomeRocks();
          break;
        case GenesisPhase.oreMaturation:
          _pulseOres();
          break;
        case GenesisPhase.surfaceWeathering:
          _spawnGrass(screenW, screenH);
          break;
        case GenesisPhase.worldReady:
          break;
      }
    }
  }

  Color _randomRockColor() {
    final t = _rng.nextDouble();
    return Color.lerp(
      const Color(0xFF3A2A1A),
      const Color(0xFF5A4A3A),
      t,
    )!;
  }

  Color _randomMagmaColor() {
    final t = _rng.nextDouble();
    return Color.lerp(
      const Color(0xFFFF4400),
      const Color(0xFFFF8800),
      t,
    )!;
  }

  Color _randomOreColor() {
    final colors = [
      const Color(0xFFFFD700),
      const Color(0xFF50C878),
      const Color(0xFF4488CC),
    ];
    return colors[_rng.nextInt(colors.length)];
  }

  Color _randomWaterColor() {
    final t = _rng.nextDouble();
    return Color.lerp(
      const Color(0xFF2266AA),
      const Color(0xFF4488CC),
      t,
    )!;
  }

  Color _randomGrassColor() {
    final t = _rng.nextDouble();
    return Color.lerp(
      const Color(0xFF446622),
      const Color(0xFF669933),
      t,
    )!;
  }

  void _spawnRock(double w, double h) {
    _particles.add(_Particle(
      x: _rng.nextDouble() * w,
      y: -10 - _rng.nextDouble() * 40,
      vx: (_rng.nextDouble() - 0.5) * 30,
      vy: _rng.nextDouble() * 50,
      radius: 2.5 + _rng.nextDouble() * 3.5,
      color: _randomRockColor(),
      type: _typeRock,
      spawnFrame: _frameCount,
    ));
  }

  void _spawnMagma(double w, double h) {
    final cx = w * 0.3 + _rng.nextDouble() * w * 0.4;
    _particles.add(_Particle(
      x: cx + (_rng.nextDouble() - 0.5) * 60,
      y: h + 5,
      vx: (_rng.nextDouble() - 0.5) * 80,
      vy: -150 - _rng.nextDouble() * 200,
      radius: 2.0 + _rng.nextDouble() * 3.0,
      color: _randomMagmaColor(),
      type: _typeMagma,
      spawnFrame: _frameCount,
    ));
  }

  void _spawnOre(double w, double h) {
    // Spawn within the settled pile area
    final targetY = h - 20 - _rng.nextDouble() * (h * 0.3);
    _particles.add(_Particle(
      x: _rng.nextDouble() * w,
      y: targetY,
      vx: (_rng.nextDouble() - 0.5) * 10,
      vy: (_rng.nextDouble() - 0.5) * 10,
      radius: 1.5 + _rng.nextDouble() * 2.0,
      color: _randomOreColor(),
      type: _typeOre,
      spawnFrame: _frameCount,
    ));
  }

  void _spawnWater(double w, double h) {
    _particles.add(_Particle(
      x: _rng.nextDouble() * w,
      y: -5 - _rng.nextDouble() * 20,
      vx: (_rng.nextDouble() - 0.5) * 20,
      vy: 30 + _rng.nextDouble() * 60,
      radius: 1.5 + _rng.nextDouble() * 2.0,
      color: _randomWaterColor(),
      type: _typeWater,
      spawnFrame: _frameCount,
    ));
  }

  void _applyErosionWind() {
    // Apply horizontal wind to water particles, scatter some rocks
    final windForce = 60.0 + _rng.nextDouble() * 40;
    for (final p in _particles) {
      if (p.type == _typeWater) {
        p.vx += windForce * 0.3;
        p.settled = false;
      } else if (p.type == _typeRock && _rng.nextDouble() < 0.02) {
        p.vx += (_rng.nextDouble() - 0.3) * windForce;
        p.vy -= 20 + _rng.nextDouble() * 40;
        p.settled = false;
      }
    }
  }

  void _dissolveSomeRocks() {
    // Shrink and fade random settled rock particles
    for (final p in _particles) {
      if (p.type == _typeRock && p.settled && _rng.nextDouble() < 0.008) {
        p.life -= 0.15;
        p.radius *= 0.85;
      }
    }
  }

  void _pulseOres() {
    // Make ore particles pulse brighter
    for (final p in _particles) {
      if (p.type == _typeOre) {
        final pulse = (sin(_frameCount * 0.15 + p.x * 0.1) + 1) * 0.5;
        p.life = 0.6 + 0.4 * pulse;
      }
    }
  }

  void _spawnGrass(double w, double h) {
    // Spawn green particles on the top surface of the pile
    final topY = _findTopSurface(
      _rng.nextDouble() * w,
      h,
    );
    _particles.add(_Particle(
      x: _rng.nextDouble() * w,
      y: topY - 2,
      vx: 0,
      vy: 5,
      radius: 1.5 + _rng.nextDouble() * 1.5,
      color: _randomGrassColor(),
      type: _typeGrass,
      spawnFrame: _frameCount,
    ));
  }

  double _findTopSurface(double x, double screenH) {
    // Find the topmost settled particle near x
    double minY = screenH;
    for (final p in _particles) {
      if (p.settled && (p.x - x).abs() < 20 && p.y < minY) {
        minY = p.y;
      }
    }
    return minY;
  }

  void _applyPhaseForces(_Particle p, double dt) {
    // Erosion wind during greatErosion
    if (_currentPhase == GenesisPhase.greatErosion && p.type == _typeWater) {
      p.vx += 15 * dt;
    }
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final accent = _phaseAccent[_currentPhase] ?? Colors.orange;

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _enterController,
        curve: Curves.easeOut,
      ),
      child: GestureDetector(
        onTap: _onTap,
        child: FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
          ),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Subtle background gradient that shifts with phase
                _AnimatedBg(accent: accent, pulse: _pulseController),

                // Physics particle canvas
                CustomPaint(
                  painter: _PhysicsParticlePainter(
                    particles: _particles,
                    solidPaint: _solidPaint,
                    glowPaint: _glowPaint,
                    podY: _podActive ? _podY : null,
                    podX: MediaQuery.of(context).size.width / 2,
                    accentColor: accent,
                    orePhase: _currentPhase == GenesisPhase.oreMaturation,
                    frameCount: _frameCount,
                  ),
                  size: MediaQuery.of(context).size,
                ),

                // Bottom UI: progress dots + bar + percentage + tap to begin
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        const Spacer(),

                        // Progress indicator
                        _buildProgress(accent),

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
                                    color: accent.withValues(
                                        alpha: 0.3 + 0.3 * pulse),
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(
                                          alpha: 0.1 * pulse),
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
        ),
      ),
    );
  }

  Widget _buildProgress(Color accent) {
    final percent = (_overallProgress * 100).round();
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
                width: isCurrent ? 14 : 6,
                height: 4,
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
        // Progress bar
        SizedBox(
          width: 260,
          height: 4,
          child: CustomPaint(
            painter: _ProgressBarPainter(
              progress: _overallProgress.clamp(0.0, 1.0),
              color: accent,
              glowIntensity: _pulseController.value,
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Percentage
        Text(
          '$percent%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 2,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Animated background gradient widget
// ---------------------------------------------------------------------------

class _AnimatedBg extends StatelessWidget {
  final Color accent;
  final AnimationController pulse;

  const _AnimatedBg({required this.accent, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final wave = sin(pulse.value * pi * 2) * 0.03;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 0.6 + wave),
              radius: 1.4,
              colors: [
                Color.lerp(
                    const Color(0xFF0A0A0A), accent, 0.06 + wave)!,
                const Color(0xFF050505),
                Colors.black,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Physics particle painter
// ---------------------------------------------------------------------------

class _PhysicsParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final Paint solidPaint;
  final Paint glowPaint;
  final double? podY;
  final double podX;
  final Color accentColor;
  final bool orePhase;
  final int frameCount;

  _PhysicsParticlePainter({
    required this.particles,
    required this.solidPaint,
    required this.glowPaint,
    required this.podY,
    required this.podX,
    required this.accentColor,
    required this.orePhase,
    required this.frameCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.life <= 0) continue;

      final alpha = p.life.clamp(0.0, 1.0);

      // Glow behind particle
      glowPaint.color = p.color.withValues(alpha: 0.08 * alpha);
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.radius * 3,
        glowPaint,
      );

      // Ore pulsing during oreMaturation
      double effectiveAlpha = alpha;
      if (orePhase && p.type == _typeOre) {
        final pulse = (sin(frameCount * 0.15 + p.x * 0.1) + 1) * 0.5;
        effectiveAlpha = (0.5 + 0.5 * pulse).clamp(0.0, 1.0);
        // Extra bright glow
        glowPaint.color = p.color.withValues(alpha: 0.2 * pulse);
        canvas.drawCircle(
          Offset(p.x, p.y),
          p.radius * 5,
          glowPaint,
        );
      }

      // Solid circle
      solidPaint.color = p.color.withValues(alpha: effectiveAlpha);
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.radius,
        solidPaint,
      );

      // Specular highlight for ores and magma
      if ((p.type == _typeOre || p.type == _typeMagma) && p.radius > 2) {
        solidPaint.color = Colors.white.withValues(alpha: 0.25 * effectiveAlpha);
        canvas.drawCircle(
          Offset(p.x - p.radius * 0.25, p.y - p.radius * 0.25),
          p.radius * 0.35,
          solidPaint,
        );
      }
    }

    // Draw pod during worldReady
    if (podY != null) {
      _drawPod(canvas, podX, podY!);
    }
  }

  void _drawPod(Canvas canvas, double x, double y) {
    // Tiny pod silhouette: a rounded trapezoid shape
    final podPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    // Glow beneath pod
    glowPaint.color = accentColor.withValues(alpha: 0.15);
    canvas.drawCircle(Offset(x, y + 4), 14, glowPaint);

    // Body (rounded rect)
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, y), width: 12, height: 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(bodyRect, podPaint);

    // Drill tip
    final drillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    final drillPath = Path()
      ..moveTo(x - 3, y + 8)
      ..lineTo(x + 3, y + 8)
      ..lineTo(x, y + 14)
      ..close();
    canvas.drawPath(drillPath, drillPaint);

    // Exhaust particles (small dots above pod)
    final exhaustPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    final rng = Random(frameCount);
    for (int i = 0; i < 3; i++) {
      final ex = x + (rng.nextDouble() - 0.5) * 8;
      final ey = y - 10 - rng.nextDouble() * 12;
      canvas.drawCircle(Offset(ex, ey), 1.0 + rng.nextDouble(), exhaustPaint);
    }
  }

  @override
  bool shouldRepaint(_PhysicsParticlePainter old) => true;
}

// ---------------------------------------------------------------------------
// Progress bar painter (preserved from original)
// ---------------------------------------------------------------------------

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
