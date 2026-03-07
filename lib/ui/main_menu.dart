import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dramatic AAA-quality title screen with industrial mining theme.
///
/// Features:
/// - Metallic gradient title with animated glow (responsive sizing)
/// - Pulsing tagline with staggered word reveal
/// - Ember particle system + geological strata background
/// - Industrial beveled buttons with haptic feedback
/// - Staggered entrance animations (replay on each mount)
/// - Settings gear icon, version info, credits
class MainMenu extends StatefulWidget {
  final VoidCallback onNewGame;
  final VoidCallback onLoadGame;

  const MainMenu({
    super.key,
    required this.onNewGame,
    required this.onLoadGame,
  });

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> with TickerProviderStateMixin {
  late final AnimationController _particleController;
  late final AnimationController _titleGlowController;
  late final AnimationController _entranceController;
  late final AnimationController _taglinePulseController;

  // Staggered entrance animations
  late final Animation<double> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<double> _accentLineFade;
  late final Animation<double> _taglineFade;
  late final Animation<double> _taglineSlide;
  late final Animation<double> _button1Fade;
  late final Animation<double> _button1Slide;
  late final Animation<double> _button2Fade;
  late final Animation<double> _button2Slide;
  late final Animation<double> _button3Fade;
  late final Animation<double> _button3Slide;
  late final Animation<double> _footerFade;

  @override
  void initState() {
    super.initState();

    _particleController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat();

    _titleGlowController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat(reverse: true);

    _taglinePulseController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat(reverse: true);

    // Master entrance controller for staggered reveal
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    );

    _setupEntranceAnimations();
    _playEntrance();
  }

  void _setupEntranceAnimations() {
    // Title: 0.0 - 0.35 (scale up + fade in from above)
    _titleSlide = Tween<double>(begin: -40.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
      ),
    );
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.30, curve: Curves.easeOut),
      ),
    );

    // Accent line: 0.25 - 0.45
    _accentLineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.25, 0.45, curve: Curves.easeOut),
      ),
    );

    // Tagline: 0.30 - 0.55
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.30, 0.55, curve: Curves.easeOut),
      ),
    );
    _taglineSlide = Tween<double>(begin: 15.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.30, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    // Button 1 (New Game): 0.45 - 0.65
    _button1Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.45, 0.65, curve: Curves.easeOut),
      ),
    );
    _button1Slide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.45, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    // Button 2 (Continue): 0.55 - 0.75
    _button2Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.55, 0.75, curve: Curves.easeOut),
      ),
    );
    _button2Slide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.55, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    // Button 3 (Leaderboard): 0.65 - 0.85
    _button3Fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.65, 0.85, curve: Curves.easeOut),
      ),
    );
    _button3Slide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.65, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    // Footer: 0.80 - 1.0
    _footerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.80, 1.0, curve: Curves.easeOut),
      ),
    );
  }

  /// Reset and replay entrance animation. Handles both first mount
  /// and subsequent returns to the menu after gameplay.
  void _playEntrance() {
    _entranceController.reset();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _entranceController.forward();
    });
  }

  /// Re-trigger entrance animation when this State is re-inserted into the
  /// tree (e.g. returning to the menu after gameplay). Without this,
  /// button labels can stay invisible if the State object was deactivated
  /// rather than fully disposed.
  @override
  void activate() {
    super.activate();
    _playEntrance();
  }

  @override
  void dispose() {
    _particleController.dispose();
    _titleGlowController.dispose();
    _entranceController.dispose();
    _taglinePulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Layer 1: Deep underground gradient background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _titleGlowController,
              builder: (context, _) {
                final glow = _titleGlowController.value;
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF000000),
                        Color.lerp(
                          const Color(0xFF060304),
                          const Color(0xFF0E0600),
                          glow * 0.4,
                        )!,
                        Color.lerp(
                          const Color(0xFF140A04),
                          const Color(0xFF221000),
                          glow * 0.5,
                        )!,
                        Color.lerp(
                          const Color(0xFF1A0D05),
                          const Color(0xFF2E1400),
                          glow * 0.6,
                        )!,
                        const Color(0xFF0A0403),
                        const Color(0xFF030101),
                      ],
                      stops: const [0.0, 0.15, 0.35, 0.55, 0.8, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),

          // Layer 2: Geological strata lines
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _GeologicalLinesPainter(
                    phase: _particleController.value,
                  ),
                );
              },
            ),
          ),

          // Layer 3: Ember particles rising from below
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (context, _) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _MenuParticleOverlay(
                    phase: _particleController.value,
                  ),
                );
              },
            ),
          ),

          // Layer 4: Radial vignette for cinematic depth
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.2),
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.2, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // Layer 5: Bottom lava glow
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _titleGlowController,
              builder: (context, _) {
                final glow = _titleGlowController.value;
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: const Alignment(0.0, 0.2),
                      colors: [
                        Color.lerp(
                          const Color(0x18FF4400),
                          const Color(0x30FF6600),
                          glow,
                        )!,
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Main content
          AnimatedBuilder(
            animation: _entranceController,
            builder: (context, _) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),

                    // Title block
                    _buildTitle(),

                    const SizedBox(height: 16),

                    // Tagline
                    _buildTagline(),

                    const Spacer(flex: 1),

                    // Buttons
                    _buildButtons(),

                    const Spacer(flex: 2),

                    // Footer
                    _buildFooter(),

                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),

          // Settings gear icon (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: AnimatedBuilder(
              animation: _entranceController,
              builder: (context, _) {
                return Opacity(
                  opacity: _footerFade.value,
                  child: IconButton(
                    icon: Icon(
                      Icons.settings,
                      color: Colors.white.withValues(alpha: 0.25),
                      size: 22,
                    ),
                    onPressed: () => _showSettings(context),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return AnimatedBuilder(
      animation: Listenable.merge([_titleGlowController, _particleController]),
      builder: (context, _) {
        final glow = _titleGlowController.value;
        final shimmer = sin(_particleController.value * 2 * pi * 2) * 0.3;

        return Transform.translate(
          offset: Offset(0, _titleSlide.value + shimmer),
          child: Opacity(
            opacity: _titleFade.value,
            child: Column(
              children: [
                // Main title with metallic gradient effect
                // Wrapped in FittedBox to prevent wrapping on narrow screens
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: const [
                            Color(0xFFFFD700),
                            Color(0xFFFF8C00),
                            Color(0xFFFFB347),
                            Color(0xFFFF6B00),
                          ],
                          stops: [
                            0.0,
                            0.4 + glow * 0.1,
                            0.7,
                            1.0,
                          ],
                        ).createShader(bounds);
                      },
                      child: Text(
                        'MOTHERLODE',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 10,
                          height: 1.0,
                          shadows: [
                            Shadow(
                              color: const Color(0xFFFF4400)
                                  .withValues(alpha: 0.6 + 0.3 * glow),
                              blurRadius: 25 + 20 * glow,
                            ),
                            Shadow(
                              color: const Color(0xFFFF8800)
                                  .withValues(alpha: 0.3 + 0.2 * glow),
                              blurRadius: 60 + 30 * glow,
                            ),
                            // Subtle upward shadow for depth
                            Shadow(
                              color: const Color(0xFF000000)
                                  .withValues(alpha: 0.8),
                              offset: const Offset(0, 3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // Animated accent line beneath title
                Opacity(
                  opacity: _accentLineFade.value,
                  child: Container(
                    width: 200 + 50 * glow,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFFFF8800)
                              .withValues(alpha: 0.5 + 0.4 * glow),
                          const Color(0xFFFFAA00)
                              .withValues(alpha: 0.6 + 0.3 * glow),
                          const Color(0xFFFF8800)
                              .withValues(alpha: 0.5 + 0.4 * glow),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6600)
                              .withValues(alpha: 0.3 + 0.3 * glow),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagline() {
    return AnimatedBuilder(
      animation: _taglinePulseController,
      builder: (context, _) {
        final pulse = _taglinePulseController.value;
        return Transform.translate(
          offset: Offset(0, _taglineSlide.value),
          child: Opacity(
            opacity: _taglineFade.value,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'DIG DEEPER.  MINE RICHER.  SURVIVE LONGER.',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.30 + 0.12 * pulse),
                    fontSize: 11,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w400,
                    shadows: [
                      Shadow(
                        color: const Color(0xFFFF8800)
                            .withValues(alpha: 0.08 + 0.06 * pulse),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
        // NEW GAME button
        Transform.translate(
          offset: Offset(0, _button1Slide.value),
          child: Opacity(
            opacity: _button1Fade.value,
            child: _IndustrialButton(
              label: 'NEW GAME',
              icon: Icons.play_arrow_rounded,
              color: const Color(0xFFFFAA00),
              isPrimary: true,
              onTap: widget.onNewGame,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // CONTINUE button
        Transform.translate(
          offset: Offset(0, _button2Slide.value),
          child: Opacity(
            opacity: _button2Fade.value,
            child: _IndustrialButton(
              label: 'CONTINUE',
              icon: Icons.save_outlined,
              color: const Color(0xFF44AADD),
              onTap: widget.onLoadGame,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // LEADERBOARD button
        Transform.translate(
          offset: Offset(0, _button3Slide.value),
          child: Opacity(
            opacity: _button3Fade.value,
            child: _IndustrialButton(
              label: 'LEADERBOARD',
              icon: Icons.emoji_events_outlined,
              color: const Color(0xFF44BB66),
              onTap: () => _showLeaderboard(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Opacity(
      opacity: _footerFade.value,
      child: Column(
        children: [
          // Separator line
          Container(
            width: 100,
            height: 1,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.white.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Version
          Text(
            'v1.0.0',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.18),
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Inspired by Motherload (XGen Studios, 2004)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.10),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF0E0E14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SETTINGS',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                width: 60,
                height: 1,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              Icon(
                Icons.construction_outlined,
                size: 36,
                color: Colors.white.withValues(alpha: 0.10),
              ),
              const SizedBox(height: 12),
              Text(
                'Settings coming soon.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              _DialogCloseButton(),
            ],
          ),
        ),
      ),
    );
  }

  void _showLeaderboard(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF0E0E14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.amber.withValues(alpha: 0.10)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LEADERBOARD',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  shadows: [
                    Shadow(
                      color: Colors.amber.withValues(alpha: 0.25),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                width: 80,
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.amber.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Icon(
                Icons.emoji_events_outlined,
                size: 40,
                color: Colors.white.withValues(alpha: 0.10),
              ),
              const SizedBox(height: 12),
              Text(
                'No records yet.\nStart mining!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _DialogCloseButton(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Industrial-style beveled button with metallic gradient and haptic feedback
// ---------------------------------------------------------------------------
class _IndustrialButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isPrimary;

  const _IndustrialButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  State<_IndustrialButton> createState() => _IndustrialButtonState();
}

class _IndustrialButtonState extends State<_IndustrialButton>
    with SingleTickerProviderStateMixin {
  bool _pressing = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    );
    if (widget.isPrimary) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttonWidth = widget.isPrimary ? 280.0 : 260.0;
    final verticalPad = widget.isPrimary ? 16.0 : 14.0;
    final fontSize = widget.isPrimary ? 15.0 : 13.0;
    final iconSize = widget.isPrimary ? 22.0 : 18.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = widget.isPrimary ? _pulseController.value : 0.0;

        return GestureDetector(
          onTapDown: (_) => setState(() => _pressing = true),
          onTapUp: (_) {
            setState(() => _pressing = false);
            HapticFeedback.mediumImpact();
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressing = false),
          child: AnimatedScale(
            scale: _pressing ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOut,
            child: Container(
              width: buttonWidth,
              padding: EdgeInsets.symmetric(
                vertical: verticalPad,
                horizontal: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.color.withOpacity(0.22 + pulse * 0.08),
                    widget.color.withOpacity(0.14 + pulse * 0.04),
                    widget.color.withOpacity(0.18 + pulse * 0.06),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(12),
                // Uniform border (required for borderRadius compatibility)
                border: Border.all(
                  color: widget.color.withOpacity(0.40 + pulse * 0.15),
                  width: widget.isPrimary ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.15 + pulse * 0.10),
                    blurRadius: 20 + pulse * 10,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    color: Colors.white.withOpacity(0.95),
                    size: iconSize,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: fontSize,
                      fontWeight: widget.isPrimary
                          ? FontWeight.w700
                          : FontWeight.w600,
                      letterSpacing: 3,
                      shadows: [
                        Shadow(
                          color: widget.color.withOpacity(0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable dialog close button
// ---------------------------------------------------------------------------
class _DialogCloseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(
          'CLOSE',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating ember particles overlay
// ---------------------------------------------------------------------------
class _MenuParticleOverlay extends CustomPainter {
  final double phase;

  _MenuParticleOverlay({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    // Embers rising from below (45 particles)
    for (int i = 0; i < 45; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.2 + random.nextDouble() * 1.0;
      final pSize = 0.6 + random.nextDouble() * 2.5;

      // Sinusoidal horizontal drift
      final x = baseX + sin(phase * 2 * pi * speed + i * 1.7) * 25;
      // Rise upward
      final y = (baseY - phase * size.height * speed * 0.15) % size.height;

      // Fade based on vertical position (brighter at bottom)
      final vertFade = (y / size.height).clamp(0.0, 1.0);
      final alpha =
          (0.08 + 0.45 * vertFade * sin(phase * 2 * pi + i * 0.4).abs())
              .clamp(0.0, 1.0);

      // Warm ember colors
      final g = 0.25 + random.nextDouble() * 0.30;
      paint.color = Color.from(
        alpha: alpha,
        red: 1.0,
        green: g,
        blue: 0.0,
      );

      canvas.drawCircle(Offset(x, y), pSize, paint);

      // Glow halo around larger particles
      if (pSize > 1.5) {
        paint.color = Color.from(
          alpha: alpha * 0.10,
          red: 1.0,
          green: 0.40,
          blue: 0.05,
        );
        canvas.drawCircle(Offset(x, y), pSize * 6, paint);
      }
    }

    // Subtle dust motes (smaller, cooler, slower)
    for (int i = 0; i < 20; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final speed = 0.05 + random.nextDouble() * 0.3;

      final x = baseX + sin(phase * 2 * pi * speed + i * 2.1) * 15;
      final y = (baseY + phase * size.height * speed * 0.05) % size.height;

      final alpha = (0.03 + 0.08 * sin(phase * 2 * pi * 0.5 + i * 0.7).abs())
          .clamp(0.0, 1.0);

      paint.color = Color.from(
        alpha: alpha,
        red: 0.8,
        green: 0.7,
        blue: 0.5,
      );
      canvas.drawCircle(Offset(x, y), 0.5 + random.nextDouble() * 0.8, paint);
    }
  }

  @override
  bool shouldRepaint(_MenuParticleOverlay oldDelegate) =>
      oldDelegate.phase != phase;
}

// ---------------------------------------------------------------------------
// Geological strata lines with subtle animation
// ---------------------------------------------------------------------------
class _GeologicalLinesPainter extends CustomPainter {
  final double phase;

  _GeologicalLinesPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Geological layer colors: sand -> rock -> volcanic -> hell
    const layerColors = [
      Color(0xFF8B6B3D), // sandy tan
      Color(0xFF7A5E35),
      Color(0xFF6A5A40), // brown
      Color(0xFF5C4A38), // grey-brown
      Color(0xFF4A3530),
      Color(0xFF4A3028), // dark
      Color(0xFF3A1818), // dark red-brown
      Color(0xFF3A1515),
      Color(0xFF2A0808), // deep hell
    ];

    for (int i = 0; i < layerColors.length; i++) {
      final y = size.height * (0.12 + i * 0.09);
      final yOffset = sin(phase * pi * 2 + i * 1.3) * 8;
      final alpha =
          (0.03 + 0.025 * sin(phase * pi * 2 + i * 0.8)).clamp(0.0, 0.07);

      paint.color = layerColors[i].withValues(alpha: alpha);

      final path = Path();
      path.moveTo(0, y + yOffset);
      for (double x = 0; x <= size.width; x += 12) {
        final localY =
            y + yOffset + sin(x * 0.005 + phase * pi * 2 + i * 0.5) * 5;
        path.lineTo(x, localY);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_GeologicalLinesPainter old) => true;
}
