import 'dart:async';

import 'package:flutter/material.dart';
import 'package:motherlode/world/genesis_pipeline.dart';

// ---------------------------------------------------------------------------
// Phase display data
// ---------------------------------------------------------------------------

const _phaseInfo = <GenesisPhase, (String, String, String)>{
  // (title, description, year)
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

// Phase accent colors
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
    with SingleTickerProviderStateMixin {
  StreamSubscription<(GenesisPhase, double)>? _progressSubscription;

  GenesisPhase _currentPhase = GenesisPhase.tectonicFormation;
  double _phaseProgress = 0.0;
  double _overallProgress = 0.0;
  bool _worldReady = false;
  bool _exiting = false;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

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
            // Subtle animated gradient background
            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Color.lerp(Colors.black, accent, 0.08)!,
                    Colors.black,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
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
                          color: accent.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Phase title
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        title,
                        key: ValueKey(title),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      child: Text(
                        description,
                        key: ValueKey(description),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Phase progress bar
                    _buildPhaseProgress(accent),

                    const Spacer(flex: 2),

                    // Overall progress
                    _buildOverallProgress(accent),

                    const SizedBox(height: 24),

                    // Tap to begin
                    if (_worldReady)
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: 0.4 + _pulseController.value * 0.6,
                            child: child,
                          );
                        },
                        child: Text(
                          'TAP TO BEGIN',
                          style: TextStyle(
                            color: accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 6,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 22), // placeholder height

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
            color: accent.withValues(alpha: 0.7),
            fontSize: 32,
            fontWeight: FontWeight.w200,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 12),
        // Thin progress bar for current phase
        SizedBox(
          width: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _phaseProgress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation(
                accent.withValues(alpha: 0.8),
              ),
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
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isCurrent ? 10 : 6,
              height: isCurrent ? 10 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? accent.withValues(alpha: 0.6)
                    : isCurrent
                        ? accent
                        : Colors.white.withValues(alpha: 0.12),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Overall progress bar
        SizedBox(
          width: 280,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: _overallProgress.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation(
                Colors.white.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Overall percentage
        Text(
          '${(_overallProgress * 100).round()}% complete',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.2),
            fontSize: 11,
            fontWeight: FontWeight.w400,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
