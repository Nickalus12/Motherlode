import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:motherlode/motherlode_game.dart';

/// Lightweight first-launch tutorial overlay.
///
/// Shows 3 tip cards with animated transitions. Auto-dismisses after 30 seconds
/// or when the player completes their first drill. Persists a Hive flag so it
/// only shows once.
class TutorialOverlay extends StatefulWidget {
  final MotherlodeGame game;
  final VoidCallback onDismiss;

  const TutorialOverlay({
    super.key,
    required this.game,
    required this.onDismiss,
  });

  /// Returns true if the tutorial has already been completed.
  static Future<bool> hasCompleted() async {
    final box = await Hive.openBox('motherlode_prefs');
    return box.get('tutorial_done', defaultValue: false) as bool;
  }

  /// Mark the tutorial as completed so it won't show again.
  static Future<void> markCompleted() async {
    final box = await Hive.openBox('motherlode_prefs');
    await box.put('tutorial_done', true);
  }

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _currentTip = 0;
  double _opacity = 0;
  Timer? _autoDismissTimer;
  Timer? _drillCheckTimer;

  static const _tips = [
    _TutorialTip(
      icon: Icons.swipe,
      title: 'DRAG TO MOVE',
      description:
          'Drag anywhere to fly your robot.\nDrag down into terrain to drill.',
    ),
    _TutorialTip(
      icon: Icons.local_gas_station,
      title: 'WATCH YOUR FUEL',
      description:
          'Fuel drains while moving and drilling.\nReturn to the surface before it runs out!',
    ),
    _TutorialTip(
      icon: Icons.store,
      title: 'SELL & UPGRADE',
      description:
          'Land on the surface pad to open the shop.\nSell ores and upgrade your robot.',
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Fade in
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _opacity = 1.0);
    });

    // Auto-dismiss after 30 seconds
    _autoDismissTimer = Timer(const Duration(seconds: 30), _dismiss);

    // Check if player starts drilling (dismiss early)
    _drillCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (widget.game.isLoaded &&
          widget.game.pod.isMounted &&
          widget.game.pod.drillSystem.isDrilling) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _drillCheckTimer?.cancel();
    super.dispose();
  }

  void _nextTip() {
    if (_currentTip < _tips.length - 1) {
      setState(() => _currentTip++);
    } else {
      _dismiss();
    }
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _drillCheckTimer?.cancel();
    TutorialOverlay.markCompleted();
    setState(() => _opacity = 0);
    Future.delayed(const Duration(milliseconds: 400), () {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tip = _tips[_currentTip];
    final safeTop = MediaQuery.of(context).padding.top;

    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.black54,
        child: Stack(
          children: [
            // Skip button (top right)
            Positioned(
              top: safeTop + 12,
              right: 16,
              child: GestureDetector(
                onTap: _dismiss,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    'SKIP',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // Tip card (centered)
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildTipCard(tip),
              ),
            ),

            // Progress dots + tap to continue (bottom)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Progress dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_tips.length, (i) {
                      final active = i == _currentTip;
                      return Container(
                        width: active ? 24 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.amber
                              : Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  // Tap to continue
                  GestureDetector(
                    onTap: _nextTip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.amber.shade800,
                            Colors.amber.shade700,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.3),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Text(
                        _currentTip < _tips.length - 1
                            ? 'NEXT'
                            : 'START MINING',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipCard(_TutorialTip tip) {
    return Container(
      key: ValueKey(tip.title),
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.1),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tip.icon,
            size: 48,
            color: Colors.amber,
          ),
          const SizedBox(height: 16),
          Text(
            tip.title,
            style: TextStyle(
              color: Colors.amber,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              shadows: [
                Shadow(
                  color: Colors.amber.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tip.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialTip {
  final IconData icon;
  final String title;
  final String description;

  const _TutorialTip({
    required this.icon,
    required this.title,
    required this.description,
  });
}
