import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:motherlode/world/genesis_pipeline.dart';

/// Genesis Screen — Continuous particle rain loading animation.
class GenesisScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final Stream<(GenesisPhase, double)>? progressStream;
  const GenesisScreen({super.key, required this.onComplete, this.progressStream});
  @override
  State<GenesisScreen> createState() => _GenesisScreenState();
}

class _GenesisScreenState extends State<GenesisScreen>
    with TickerProviderStateMixin {
  StreamSubscription<(GenesisPhase, double)>? _sub;
  double _progress = 0.0;
  bool _worldReady = false, _exiting = false;

  late final AnimationController _pulseCtrl, _enterCtrl, _exitCtrl;
  late final Ticker _ticker;
  final Stopwatch _sw = Stopwatch();
  int _lastMicros = 0;

  final List<_Particle> _particles = [];
  final List<_DustMote> _dust = [];
  final Random _rng = Random(42);
  final Paint _solidP = Paint()..style = PaintingStyle.fill;
  final Paint _glowP = Paint()..style = PaintingStyle.fill;

  static const _accent = Color(0xFFFF6B35);
  static const _maxParts = 150, _dustN = 20;
  static const _colors = [
    Color(0xFF1A0E08), Color(0xFF2A1A0E), Color(0xFF3A2816), Color(0xFF5A3A1E),
    Color(0xFF6B4226), Color(0xFF8B4513), Color(0xFF9E6B3A), Color(0xFFB8860B),
    Color(0xFFFF6B35),
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _exitCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _sw.start();
    _ticker = createTicker(_onTick)..start();
    _sub = widget.progressStream?.listen((e) {
      if (!mounted) return;
      setState(() {
        _progress = GenesisPipeline.overallProgress(e.$1, e.$2);
        if (e.$1 == GenesisPhase.worldReady && e.$2 >= 1.0) _worldReady = true;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    _sw.stop();
    _pulseCtrl.dispose();
    _enterCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!_worldReady || _exiting) return;
    setState(() => _exiting = true);
    _exitCtrl.forward().then((_) { if (mounted) widget.onComplete(); });
  }

  // -- Physics tick driven by Ticker + Stopwatch for stable dt --------------

  void _onTick(Duration _) {
    final now = _sw.elapsedMicroseconds;
    var dt = (now - _lastMicros) / 1e6;
    _lastMicros = now;
    if (dt <= 0 || dt > 0.05) dt = 0.016;

    final sz = MediaQuery.of(context).size;
    final w = sz.width, h = sz.height;
    final elapsed = now / 1e6;

    if (_dust.isEmpty && w > 0) _initDust(w, h);

    // Spawn 2 per frame
    if (_particles.length < _maxParts) {
      for (int i = 0; i < 2; i++) {
        _particles.add(_spawn(w));
      }
    }

    const grav = 180.0, bounce = 0.25, fadeT = 2.5;
    _particles.removeWhere((p) => p.alpha <= 0);

    for (final p in _particles) {
      p.life += dt;
      if (p.settled) {
        p.settleT += dt;
        if (p.settleT >= 0.5) {
          p.alpha = (1.0 - ((p.settleT - 0.5) / fadeT)).clamp(0.0, 1.0);
        }
        continue;
      }
      p.vy += grav * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.98;
      if (p.y + p.r > h) {
        p.y = h - p.r;
        p.vy = -p.vy * bounce;
        p.vx *= 0.85;
        if (p.vy.abs() < 4) { p.vy = 0; p.settled = true; }
      }
      if (p.x - p.r < 0) { p.x = p.r; p.vx = p.vx.abs() * bounce; }
      else if (p.x + p.r > w) { p.x = w - p.r; p.vx = -p.vx.abs() * bounce; }
      if (p.vy.abs() < 2 && p.vx.abs() < 2 && p.y + p.r >= h - 2) {
        p.settled = true; p.vy = 0;
      }
    }

    for (final d in _dust) {
      d.x += d.vx * dt + cos(elapsed * d.freq * 0.7 + d.phase) * 0.1;
      d.y += d.vy * dt + sin(elapsed * d.freq + d.phase) * 0.15;
      if (d.x < -10) d.x = w + 10; if (d.x > w + 10) d.x = -10;
      if (d.y < -10) d.y = h + 10; if (d.y > h + 10) d.y = -10;
    }
    setState(() {});
  }

  _Particle _spawn(double w) {
    final r = _rng.nextDouble();
    final i = r < 0.6 ? _rng.nextInt(4) : r < 0.9 ? 4 + _rng.nextInt(3) : 7 + _rng.nextInt(2);
    return _Particle(
      x: _rng.nextDouble() * w, y: -5 - _rng.nextDouble() * 30,
      vx: (_rng.nextDouble() - 0.5) * 20, vy: _rng.nextDouble() * 40 + 10,
      r: 1.5 + _rng.nextDouble() * 2.5, color: _colors[i],
    );
  }

  void _initDust(double w, double h) {
    for (int i = 0; i < _dustN; i++) {
      _dust.add(_DustMote(
        x: _rng.nextDouble() * w, y: _rng.nextDouble() * h,
        vx: (_rng.nextDouble() - 0.5) * 8, vy: (_rng.nextDouble() - 0.5) * 4,
        r: 0.5 + _rng.nextDouble(), alpha: 0.08 + _rng.nextDouble() * 0.12,
        freq: 0.5 + _rng.nextDouble() * 1.5, phase: _rng.nextDouble() * pi * 2,
      ));
    }
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
              CustomPaint(
                painter: _PPainter(_particles, _dust, _solidP, _glowP),
                size: MediaQuery.of(context).size,
              ),
              SafeArea(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(children: [
                  const Spacer(),
                  _bar(),
                  const SizedBox(height: 28),
                  _worldReady ? _tapBtn() : const SizedBox(height: 47),
                  const SizedBox(height: 48),
                ]),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bar() {
    final pct = (_progress * 100).round();
    return Column(children: [
      SizedBox(width: 260, height: 4, child: CustomPaint(
        painter: _BarPainter(_progress.clamp(0.0, 1.0), _accent, _pulseCtrl.value),
      )),
      const SizedBox(height: 10),
      Text('$pct%', style: TextStyle(
        color: Colors.white.withValues(alpha: 0.25), fontSize: 12,
        fontWeight: FontWeight.w400, letterSpacing: 2, decoration: TextDecoration.none,
      )),
    ]);
  }

  Widget _tapBtn() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (ctx, child) {
        final p = _pulseCtrl.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: _accent.withValues(alpha: 0.3 + 0.3 * p)),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(
              color: _accent.withValues(alpha: 0.1 * p), blurRadius: 20, spreadRadius: -4,
            )],
          ),
          child: Opacity(opacity: 0.5 + 0.5 * p, child: child),
        );
      },
      child: const Text('TAP TO BEGIN', style: TextStyle(
        color: _accent, fontSize: 15, fontWeight: FontWeight.w600,
        letterSpacing: 6, decoration: TextDecoration.none,
      )),
    );
  }
}

// -- Data classes -----------------------------------------------------------

class _Particle {
  double x, y, vx, vy, r, life = 0, settleT = 0, alpha = 1.0;
  Color color;
  bool settled = false;
  _Particle({required this.x, required this.y, this.vx = 0, this.vy = 0,
    this.r = 3.0, this.color = const Color(0xFF3A2A1A)});
}

class _DustMote {
  double x, y, vx, vy, r, alpha, freq, phase;
  _DustMote({required this.x, required this.y, required this.vx, required this.vy,
    required this.r, required this.alpha, required this.freq, required this.phase});
}

// -- Painters ---------------------------------------------------------------

class _PPainter extends CustomPainter {
  final List<_Particle> parts;
  final List<_DustMote> dust;
  final Paint sp, gp;
  _PPainter(this.parts, this.dust, this.sp, this.gp);

  @override
  void paint(Canvas c, Size size) {
    for (final d in dust) {
      sp.color = Colors.white.withValues(alpha: d.alpha);
      c.drawCircle(Offset(d.x, d.y), d.r, sp);
    }
    for (final p in parts) {
      if (p.alpha <= 0) continue;
      gp.color = p.color.withValues(alpha: 0.06 * p.alpha);
      c.drawCircle(Offset(p.x, p.y), p.r * 2.5, gp);
      sp.color = p.color.withValues(alpha: p.alpha);
      c.drawCircle(Offset(p.x, p.y), p.r, sp);
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
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, h), Radius.circular(r)),
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );
    if (progress <= 0) return;
    final fw = size.width * progress;
    if (glow > 0) {
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, -2, fw, h + 4), Radius.circular(r + 2)),
        Paint()..color = color.withValues(alpha: 0.15 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fw, h), Radius.circular(r)),
      Paint()..color = color,
    );
    c.drawCircle(Offset(fw - r, h / 2), r * 0.6,
      Paint()..color = Colors.white.withValues(alpha: 0.4));
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress || old.color != color || old.glow != glow;
}
