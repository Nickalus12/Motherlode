import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:motherlode/motherlode_game.dart';

/// A placed support beam that prevents collapse in a column.
class PlacedBeam {
  final int gridX;
  final int gridY;
  final double placedAt; // game time when placed

  const PlacedBeam({
    required this.gridX,
    required this.gridY,
    required this.placedAt,
  });

  Map<String, dynamic> toMap() => {
        'gridX': gridX,
        'gridY': gridY,
        'placedAt': placedAt,
      };

  factory PlacedBeam.fromMap(Map<String, dynamic> map) => PlacedBeam(
        gridX: map['gridX'] as int,
        gridY: map['gridY'] as int,
        placedAt: (map['placedAt'] as num).toDouble(),
      );
}

/// An active flare that reveals terrain in a radius.
class ActiveFlare {
  final Vector2 position;
  double remainingSeconds;

  ActiveFlare({required this.position, required this.remainingSeconds});
}

/// Manages deployable tactical items: C4, telepad, support beams, flares.
///
/// C4 and teleporters already exist as consumables — this system adds
/// support beams (collapse prevention) and flares (terrain reveal).
class DeployableSystem extends Component {
  final MotherlodeGame game;

  static const double flareRadius = 10.0; // tiles
  static const double flareDuration = 15.0; // seconds
  static const int beamReinforceCells = 3; // cells above beam

  final List<PlacedBeam> _beams = [];
  final List<ActiveFlare> _activeFlares = [];
  double _gameTime = 0;

  DeployableSystem({required this.game});

  /// All currently placed beams (for rendering and collapse checks).
  List<PlacedBeam> get beams => List.unmodifiable(_beams);

  /// All active flares (for lighting/fog reveal).
  List<ActiveFlare> get activeFlares => List.unmodifiable(_activeFlares);

  /// Place a support beam at the robot's current grid position.
  /// Returns true if successfully placed.
  bool placeBeam() {
    if (game.supportBeamCount <= 0) return false;

    final gridX = game.pod.position.x.round();
    final gridY = game.pod.position.y.round();

    // Don't place duplicate beams at same position
    for (final beam in _beams) {
      if (beam.gridX == gridX && beam.gridY == gridY) return false;
    }

    game.supportBeamCount--;
    _beams.add(PlacedBeam(gridX: gridX, gridY: gridY, placedAt: _gameTime));

    // Audio and haptic feedback
    game.audioManager.playLanding();
    HapticFeedback.mediumImpact();

    // Celebration particles
    game.particleSystem.emitOreSparkle(
      game.pod.position,
      Colors.brown,
    );

    return true;
  }

  /// Launch a flare from the robot's position in its facing direction.
  bool launchFlare() {
    if (game.flareCount <= 0) return false;

    game.flareCount--;

    // Place flare slightly ahead of the robot
    final rng = Random();
    final offset = Vector2(
      (rng.nextDouble() - 0.5) * 4.0,
      game.pod.position.y + 3.0 + rng.nextDouble() * 4.0,
    );
    final flarePos = Vector2(game.pod.position.x + offset.x, offset.y);

    _activeFlares.add(ActiveFlare(
      position: flarePos,
      remainingSeconds: flareDuration,
    ));

    // Visual feedback
    game.audioManager.playExplosion();
    HapticFeedback.lightImpact();
    game.particleSystem.emitOreSparkle(flarePos, Colors.yellow);

    return true;
  }

  /// Check if a grid cell is reinforced by a support beam.
  bool isCellReinforced(int gridX, int gridY) {
    for (final beam in _beams) {
      if (beam.gridX == gridX &&
          gridY >= beam.gridY - beamReinforceCells &&
          gridY <= beam.gridY) {
        return true;
      }
    }
    return false;
  }

  /// Get the nearest flare position and its remaining radius multiplier
  /// for fog/lighting reveal (returns null if no flares active nearby).
  ({Vector2 position, double intensity})? getNearestFlare(Vector2 worldPos) {
    if (_activeFlares.isEmpty) return null;

    double bestDist = double.infinity;
    ActiveFlare? best;
    for (final flare in _activeFlares) {
      final dist = flare.position.distanceTo(worldPos);
      if (dist < flareRadius && dist < bestDist) {
        bestDist = dist;
        best = flare;
      }
    }
    if (best == null) return null;

    // Fade out in last 3 seconds
    final fade = (best.remainingSeconds / 3.0).clamp(0.0, 1.0);
    return (position: best.position, intensity: fade);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _gameTime += dt;

    // Update active flares
    _activeFlares.removeWhere((flare) {
      flare.remainingSeconds -= dt;
      return flare.remainingSeconds <= 0;
    });
  }

  /// Serialize for save.
  Map<String, dynamic> toMap() {
    return {
      'beams': _beams.map((b) => b.toMap()).toList(),
      'gameTime': _gameTime,
    };
  }

  /// Restore from save data.
  void loadFromMap(Map<String, dynamic> map) {
    _beams.clear();
    _activeFlares.clear();
    final savedBeams = map['beams'] as List<dynamic>?;
    if (savedBeams != null) {
      for (final b in savedBeams) {
        _beams.add(PlacedBeam.fromMap(b as Map<String, dynamic>));
      }
    }
    _gameTime = (map['gameTime'] as num?)?.toDouble() ?? 0;
  }
}
