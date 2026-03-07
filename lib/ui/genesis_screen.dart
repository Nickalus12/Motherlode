import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:motherlode/world/genesis_pipeline.dart';

/// Genesis Screen — Cinematic earth-toned loading animation with particle rain.
class GenesisScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final Stream<(GenesisPhase, double)>? progressStream;
  const GenesisScreen(
      {super.key, required this.onComplete, this.progressStream});
  @override
  State<GenesisScreen> createState() => _GenesisScreenState();
}

class _GenesisScreenState extends State<GenesisScreen>
    with TickerProviderStateMixin {
  StreamSubscription<(GenesisPhase, double)>? _sub;
  double _progress = 0.0;
  GenesisPhase _currentPhase = GenesisPhase.tectonicFormation;
  bool _worldReady = false, _exiting = false;

  late final AnimationController _pulseCtrl, _enterCtrl, _exitCtrl, _tapBtnCtrl;
  late final Ticker _ticker;
  final Stopwatch _sw = Stopwatch();
  int _lastMicros = 0;

  // Particle simulation state — updated by ticker, read by painter
  final List<_Particle> _particles = [];
  final List<_DustMote> _dust = [];
  final List<_Ember> _embers = [];
  final Random _rng = Random(42);

  // Repaint notifier — triggers CustomPaint repaint without widget rebuild
  final _RepaintSignal _repaintSignal = _RepaintSignal();

  // Cached screen size to avoid MediaQuery in tick loop
  Size _cachedSize = Size.zero;

  // Time-based spawn accumulator (seconds owed)
  double _spawnAccum = 0.0;

  static const _accent = Color(0xFFFF6B35);
  static const _maxParts = 250, _dustN = 40, _emberN = 30;
  // Spawn interval: 1 particle every 25ms => 40 particles/sec
  static const _spawnInterval = 0.025;

  // Rich forge palette: deep embers, warm golds, molten oranges, white-hot cores
  static const _colors = [
    // Deep embers (0-3)
    Color(0xFF1A0A04),
    Color(0xFF2A1208),
    Color(0xFF3A1C0C),
    Color(0xFF4A2810),
    // Warm clay (4-7)
    Color(0xFF6B3A1E),
    Color(0xFF7A4828),
    Color(0xFF8B5A32),
    Color(0xFF9E6B3A),
    // Amber/gold (8-11)
    Color(0xFFB8860B),
    Color(0xFFD4A040),
    Color(0xFFE8B84A),
    Color(0xFFF0C860),
    // Molten/fire (12-15)
    Color(0xFFFF6B35),
    Color(0xFFFF8C42),
    Color(0xFFFFAA55),
    Color(0xFFFFCC80),
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..forward();
    _exitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _tapBtnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _sw.start();
    _ticker = createTicker(_onTick)..start();
    _sub = widget.progressStream?.listen((e) {
      if (!mounted) return;
      final newProgress = GenesisPipeline.overallProgress(e.$1, e.$2);
      final newReady = e.$1 == GenesisPhase.worldReady && e.$2 >= 1.0;
      final phaseChanged = e.$1 != _currentPhase;
      // Only rebuild UI when progress text, phase, or ready state actually changes
      if ((newProgress * 100).round() != (_progress * 100).round() ||
          newReady != _worldReady ||
          phaseChanged) {
        setState(() {
          _progress = newProgress;
          _currentPhase = e.$1;
          if (newReady && !_worldReady) {
            _worldReady = true;
            _tapBtnCtrl.forward();
          }
        });
      } else {
        _progress = newProgress;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    _sw.stop();
    _repaintSignal.dispose();
    _pulseCtrl.dispose();
    _enterCtrl.dispose();
    _exitCtrl.dispose();
    _tapBtnCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!_worldReady || _exiting) return;
    setState(() => _exiting = true);
    _exitCtrl.forward().then((_) {
      if (mounted) widget.onComplete();
    });
  }

  // -- Physics tick driven by Ticker + Stopwatch for stable dt --------------

  void _onTick(Duration _) {
    final now = _sw.elapsedMicroseconds;
    var dt = (now - _lastMicros) / 1e6;
    _lastMicros = now;
    if (dt <= 0 || dt > 0.05) dt = 0.016;

    final w = _cachedSize.width;
    final h = _cachedSize.height;
    if (w <= 0 || h <= 0) return;

    final elapsed = now / 1e6;

    if (_dust.isEmpty) _initDust(w, h);
    if (_embers.isEmpty) _initEmbers(w, h);

    // Spawn particles — time-based accumulator for stutter-proof rate
    _spawnAccum += dt;
    while (_spawnAccum >= _spawnInterval && _particles.length < _maxParts) {
      _spawnAccum -= _spawnInterval;
      _particles.add(_spawn(w, h));
    }
    // Clamp accumulator to avoid burst after long stalls
    if (_spawnAccum > _spawnInterval * 4) _spawnAccum = _spawnInterval * 2;

    const grav = 180.0, bounce = 0.25, fadeT = 2.5;

    // Remove dead particles (iterate backwards)
    for (int i = _particles.length - 1; i >= 0; i--) {
      if (_particles[i].alpha <= 0) _particles.removeAt(i);
    }

    for (final p in _particles) {
      p.life += dt;
      if (p.settled) {
        p.settleT += dt;
        if (p.settleT >= 0.5) {
          p.alpha = (1.0 - ((p.settleT - 0.5) / fadeT)).clamp(0.0, 1.0);
        }
        continue;
      }
      p.vy += grav * p.gravScale * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      // Air drag (frame-rate independent)
      final drag = pow(0.98, dt / 0.016).toDouble();
      p.vx *= drag;

      // Rising particles (negative gravScale) fade out at top
      if (p.gravScale < 0) {
        if (p.y < -30) {
          p.alpha = 0; // mark for removal
        } else if (p.life > 1.5) {
          p.alpha = (1.0 - (p.life - 1.5) / 2.0).clamp(0.0, 1.0);
        }
        continue;
      }

      if (p.y + p.r > h) {
        p.y = h - p.r;
        p.vy = -p.vy * bounce;
        p.vx *= 0.85;
        if (p.vy.abs() < 4) {
          p.vy = 0;
          p.settled = true;
        }
      }
      if (p.x - p.r < 0) {
        p.x = p.r;
        p.vx = p.vx.abs() * bounce;
      } else if (p.x + p.r > w) {
        p.x = w - p.r;
        p.vx = -p.vx.abs() * bounce;
      }
      if (p.vy.abs() < 2 && p.vx.abs() < 2 && p.y + p.r >= h - 2) {
        p.settled = true;
        p.vy = 0;
      }
    }

    for (final d in _dust) {
      d.x += d.vx * dt + cos(elapsed * d.freq * 0.7 + d.phase) * 0.1;
      d.y += d.vy * dt + sin(elapsed * d.freq + d.phase) * 0.15;
      d.alpha = (0.05 + sin(elapsed * d.freq * 0.3 + d.phase) * 0.06)
          .clamp(0.02, 0.15);
      if (d.x < -10) d.x = w + 10;
      if (d.x > w + 10) d.x = -10;
      if (d.y < -10) d.y = h + 10;
      if (d.y > h + 10) d.y = -10;
    }

    // Embers: slow rising glow particles with swirl and breathing
    for (final e in _embers) {
      e.life += dt;
      // Gentle horizontal swirl
      e.x += sin(elapsed * e.freq + e.phase) * 0.6
           + cos(elapsed * e.freq * 0.7 + e.phase * 1.3) * 0.3;
      e.y -= e.speed * dt;
      // Breathing alpha with pulse
      e.alpha = (sin(e.life * e.pulseSpeed) * 0.5 + 0.5).clamp(0.0, 1.0) * e.maxAlpha;
      if (e.y < -30) {
        e.y = h + _rng.nextDouble() * 30;
        e.x = _rng.nextDouble() * w;
        e.life = 0;
      }
    }

    // Signal repaint without rebuilding widget tree
    _repaintSignal.notify();
  }

  _Particle _spawn(double w, double h) {
    final r = _rng.nextDouble();
    // Weighted color selection: more dark particles, fewer bright
    final i = r < 0.3
        ? _rng.nextInt(4) // deep embers
        : r < 0.55
            ? 4 + _rng.nextInt(4) // warm clay
            : r < 0.8
                ? 8 + _rng.nextInt(4) // amber/gold
                : 12 + _rng.nextInt(4); // molten/fire
    // Size variety: mostly small with occasional large glowing chunks
    final sizeR = _rng.nextDouble();
    final radius = sizeR < 0.4
        ? 1.5 + _rng.nextDouble() * 2.0 // small dust
        : sizeR < 0.7
            ? 3.0 + _rng.nextDouble() * 3.0 // medium gravel
            : sizeR < 0.9
                ? 5.0 + _rng.nextDouble() * 4.0 // large rocks
                : 9.0 + _rng.nextDouble() * 5.0; // boulders
    // Depth layer: larger particles fall faster
    final gravScale = 0.6 + (radius / 14.0) * 0.8;

    // 30% of particles spawn near the bottom 30% (progress bar area) for density
    final spawnNearBottom = _rng.nextDouble() < 0.3;
    final spawnY = spawnNearBottom
        ? h * 0.6 + _rng.nextDouble() * h * 0.1
        : -5.0 - _rng.nextDouble() * 50;
    // Particles near bottom start with upward velocity (embers rising from bar)
    final vy = spawnNearBottom
        ? -(_rng.nextDouble() * 30 + 10)
        : _rng.nextDouble() * 40 + 10;
    // Breathing pulse phase
    final pulsePhase = _rng.nextDouble() * pi * 2;
    final pulseSpeed = 1.5 + _rng.nextDouble() * 2.5;

    return _Particle(
      x: _rng.nextDouble() * w,
      y: spawnY,
      vx: (_rng.nextDouble() - 0.5) * 20,
      vy: vy,
      r: radius,
      color: _colors[i.clamp(0, _colors.length - 1)],
      gravScale: spawnNearBottom ? -0.3 : gravScale, // negative = floats up
      pulsePhase: pulsePhase,
      pulseSpeed: pulseSpeed,
    );
  }

  void _initDust(double w, double h) {
    for (int i = 0; i < _dustN; i++) {
      _dust.add(_DustMote(
        x: _rng.nextDouble() * w,
        y: _rng.nextDouble() * h,
        vx: (_rng.nextDouble() - 0.5) * 6,
        vy: (_rng.nextDouble() - 0.5) * 3,
        r: 0.4 + _rng.nextDouble() * 1.5,
        alpha: 0.03 + _rng.nextDouble() * 0.08,
        freq: 0.2 + _rng.nextDouble() * 1.2,
        phase: _rng.nextDouble() * pi * 2,
      ));
    }
  }

  void _initEmbers(double w, double h) {
    for (int i = 0; i < _emberN; i++) {
      // Half the embers spawn from bottom third (forge-like)
      final fromBottom = i < _emberN ~/ 2;
      _embers.add(_Ember(
        x: _rng.nextDouble() * w,
        y: fromBottom ? h * 0.7 + _rng.nextDouble() * h * 0.3 : _rng.nextDouble() * h,
        r: 1.5 + _rng.nextDouble() * 3.0,
        speed: 10 + _rng.nextDouble() * 25,
        freq: 0.3 + _rng.nextDouble() * 2.5,
        phase: _rng.nextDouble() * pi * 2,
        maxAlpha: 0.2 + _rng.nextDouble() * 0.35,
        pulseSpeed: 1.0 + _rng.nextDouble() * 2.0,
      ));
    }
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _cachedSize = MediaQuery.sizeOf(context);

    return FadeTransition(
      opacity: CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut),
      child: GestureDetector(
        onTap: _onTap,
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0).animate(
              CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(fit: StackFit.expand, children: [
              // Particle canvas
              RepaintBoundary(
                child: CustomPaint(
                  painter:
                      _PPainter(_particles, _dust, _embers, _repaintSignal),
                  size: _cachedSize,
                ),
              ),
              // UI overlay
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(children: [
                    const SizedBox(height: 60),
                    // Title
                    _title(),
                    const Spacer(),
                    // Progress section
                    _progressSection(),
                    const SizedBox(height: 32),
                    // Tap button or spacer
                    _worldReady ? _tapBtn() : const SizedBox(height: 56),
                    const SizedBox(height: 48),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _title() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (ctx, child) {
        final pulse = _pulseCtrl.value;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'MOTHERLODE',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 16,
                    decoration: TextDecoration.none,
                    shadows: [
                      Shadow(
                        color: _accent.withValues(alpha: 0.4 + 0.3 * pulse),
                        blurRadius: 20 + 10 * pulse,
                      ),
                      Shadow(
                        color: _accent.withValues(alpha: 0.15 + 0.1 * pulse),
                        blurRadius: 40 + 20 * pulse,
                      ),
                      Shadow(
                        color: Colors.white.withValues(alpha: 0.08),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'DIG DEEPER.  MINE RICHER.  SURVIVE LONGER.',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25 + 0.05 * pulse),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 4,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _progressSection() {
    final pct = (_progress * 100).round();
    final label = GenesisPipeline.phaseLabel(_currentPhase);
    return Column(children: [
      // Progress bar — wider and more substantial
      SizedBox(
        width: double.infinity,
        height: 6,
        child: CustomPaint(
          painter:
              _BarPainter(_progress.clamp(0.0, 1.0), _accent, _pulseCtrl.value),
        ),
      ),
      const SizedBox(height: 12),
      // Phase label
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: Text(
          _worldReady ? 'World Ready' : '$label...',
          key: ValueKey(_currentPhase),
          style: TextStyle(
            color: _worldReady
                ? _accent.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.4),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
            decoration: TextDecoration.none,
          ),
        ),
      ),
      const SizedBox(height: 6),
      // Percentage
      Text(
        '$pct%',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.2),
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 2,
          decoration: TextDecoration.none,
        ),
      ),
    ]);
  }

  Widget _tapBtn() {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _tapBtnCtrl,
        curve: Curves.easeOut,
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _tapBtnCtrl,
          curve: Curves.elasticOut,
        )),
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (ctx, child) {
            final p = _pulseCtrl.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(
                border:
                    Border.all(color: _accent.withValues(alpha: 0.3 + 0.4 * p)),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.08 + 0.12 * p),
                    blurRadius: 24,
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.04 * p),
                    blurRadius: 50,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Opacity(
                opacity: 0.5 + 0.5 * p,
                child: child,
              ),
            );
          },
          child: const Text(
            'TAP TO BEGIN',
            style: TextStyle(
              color: _accent,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 8,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

// -- Repaint signal (lightweight ChangeNotifier) ----------------------------

class _RepaintSignal extends ChangeNotifier {
  void notify() => notifyListeners();
}

// -- Data classes -----------------------------------------------------------

class _Particle {
  double x, y, vx, vy, r, life = 0, settleT = 0, alpha = 1.0, gravScale;
  double pulsePhase, pulseSpeed;
  Color color;
  bool settled = false;
  _Particle({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.r = 3.0,
    this.color = const Color(0xFF3A2A1A),
    this.gravScale = 1.0,
    this.pulsePhase = 0.0,
    this.pulseSpeed = 2.0,
  });
}

class _DustMote {
  double x, y, vx, vy, r, alpha, freq, phase;
  _DustMote({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.alpha,
    required this.freq,
    required this.phase,
  });
}

class _Ember {
  double x, y, r, speed, freq, phase, maxAlpha, alpha = 0, life = 0;
  double pulseSpeed;
  _Ember({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.freq,
    required this.phase,
    required this.maxAlpha,
    this.pulseSpeed = 1.5,
  });
}

// -- Painters ---------------------------------------------------------------

class _PPainter extends CustomPainter {
  final List<_Particle> parts;
  final List<_DustMote> dust;
  final List<_Ember> embers;
  final Paint _solidP = Paint()..style = PaintingStyle.fill;
  final Paint _glowP = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final Paint _outerGlowP = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

  _PPainter(this.parts, this.dust, this.embers, _RepaintSignal repaint)
      : super(repaint: repaint);

  @override
  void paint(Canvas c, Size size) {
    // Dust motes (background layer — subtle warmth)
    for (final d in dust) {
      _solidP.color = const Color(0xFFFFDDCC).withValues(alpha: d.alpha);
      c.drawCircle(Offset(d.x, d.y), d.r, _solidP);
    }

    // Embers (mid layer — rising forge glow with layered halos)
    for (final e in embers) {
      if (e.alpha <= 0.01) continue;
      final pos = Offset(e.x, e.y);
      // Outer soft glow halo
      _outerGlowP.color = const Color(0xFFFF6B35).withValues(alpha: e.alpha * 0.12);
      c.drawCircle(pos, e.r * 5.0, _outerGlowP);
      // Inner glow
      _glowP.color = const Color(0xFFFFAA55).withValues(alpha: e.alpha * 0.35);
      c.drawCircle(pos, e.r * 2.5, _glowP);
      // Hot core
      _solidP.color = const Color(0xFFFFCC80).withValues(alpha: e.alpha);
      c.drawCircle(pos, e.r, _solidP);
      // White-hot center for brightest embers
      if (e.alpha > 0.3) {
        _solidP.color = Colors.white.withValues(alpha: (e.alpha - 0.3) * 0.5);
        c.drawCircle(pos, e.r * 0.4, _solidP);
      }
    }

    // Falling/rising particles (foreground layer with breathing size)
    for (final p in parts) {
      if (p.alpha <= 0) continue;
      // Breathing size pulse: +-15% of base radius
      final pulse = sin(p.life * p.pulseSpeed + p.pulsePhase) * 0.15 + 1.0;
      final drawR = p.r * pulse;
      final pos = Offset(p.x, p.y);
      // Soft outer glow for larger particles
      if (drawR > 3.0) {
        _outerGlowP.color = p.color.withValues(alpha: 0.08 * p.alpha);
        c.drawCircle(pos, drawR * 2.5, _outerGlowP);
      }
      // Inner glow
      _glowP.color = p.color.withValues(alpha: 0.15 * p.alpha);
      c.drawCircle(pos, drawR * 1.6, _glowP);
      // Solid core
      _solidP.color = p.color.withValues(alpha: p.alpha);
      c.drawCircle(pos, drawR, _solidP);
      // Hot center highlight for bright-colored particles
      if (drawR > 4.0 && p.alpha > 0.5) {
        _solidP.color = Colors.white.withValues(alpha: 0.15 * p.alpha);
        c.drawCircle(pos, drawR * 0.3, _solidP);
      }
    }
  }

  @override
  bool shouldRepaint(_PPainter old) => true;
}

class _BarPainter extends CustomPainter {
  final double progress, glow;
  final Color color;
  _BarPainter(this.progress, this.color, this.glow);

  @override
  void paint(Canvas c, Size size) {
    final h = size.height, r = h / 2;
    // Track background
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, h), Radius.circular(r)),
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
    if (progress <= 0) return;
    final fw = size.width * progress;
    // Glow behind bar
    if (glow > 0) {
      c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, -3, fw, h + 6), Radius.circular(r + 3)),
        Paint()
          ..color = color.withValues(alpha: 0.12 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    // Filled portion
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fw, h), Radius.circular(r)),
      Paint()..color = color,
    );
    // Leading dot
    if (fw > r) {
      c.drawCircle(
        Offset(fw - r, h / 2),
        r * 0.5,
        Paint()..color = Colors.white.withValues(alpha: 0.4),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress || old.color != color || old.glow != glow;
}
