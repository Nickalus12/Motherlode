import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';

/// Depth-reactive audio system managing background music crossfades and SFX.
///
/// Music transitions smoothly between depth zones. SFX play on game events.
/// All audio calls are fire-and-forget with try/catch — missing audio files
/// are silently ignored so the game runs fine without assets.
class AudioManager extends Component with HasGameReference<MotherlodeGame> {
  // Volume settings (0.0 - 1.0)
  double _musicVolume = 0.6;
  double _sfxVolume = 0.8;
  bool _muted = false;

  // Current music state
  _MusicZone _currentZone = _MusicZone.surface;
  bool _musicPlaying = false;

  double get musicVolume => _musicVolume;
  double get sfxVolume => _sfxVolume;
  bool get muted => _muted;

  // --- Music track paths (relative to assets/audio/) ---
  static const _musicTracks = <_MusicZone, String>{
    _MusicZone.surface: 'music/surface.ogg',
    _MusicZone.shallow: 'music/shallow.ogg',
    _MusicZone.deep: 'music/deep.ogg',
    _MusicZone.volcanic: 'music/volcanic.ogg',
    _MusicZone.hell: 'music/hell.ogg',
  };

  // --- SFX paths ---
  static const sfxDrill = 'sfx/drill.ogg';
  static const sfxExplosion = 'sfx/explosion.ogg';
  static const sfxOrePickup = 'sfx/ore_pickup.ogg';
  static const sfxEngineThrust = 'sfx/engine_thrust.ogg';
  static const sfxFuelWarning = 'sfx/fuel_warning.ogg';
  static const sfxHullDamage = 'sfx/hull_damage.ogg';
  static const sfxPurchase = 'sfx/purchase.ogg';
  static const sfxSell = 'sfx/sell.ogg';
  static const sfxLavaBurn = 'sfx/lava_burn.ogg';
  static const sfxLanding = 'sfx/landing.ogg';

  // Throttle timers to prevent SFX spam
  final Map<String, double> _sfxCooldowns = {};
  static const double _sfxMinInterval = 0.1; // seconds

  @override
  void update(double dt) {
    super.update(dt);

    // Decay SFX cooldowns
    final expired = <String>[];
    _sfxCooldowns.forEach((key, remaining) {
      _sfxCooldowns[key] = remaining - dt;
      if (remaining - dt <= 0) expired.add(key);
    });
    for (final key in expired) {
      _sfxCooldowns.remove(key);
    }

    // Update music zone based on depth
    if (!_muted) {
      _updateMusicZone();
    }
  }

  // ---------------------------------------------------------------------------
  // Music
  // ---------------------------------------------------------------------------

  void _updateMusicZone() {
    final depth = game.currentDepthFeet;
    final newZone = _zoneForDepth(depth);

    if (newZone != _currentZone || !_musicPlaying) {
      _currentZone = newZone;
      _playMusic(newZone);
    }
  }

  _MusicZone _zoneForDepth(double depth) {
    if (depth < GameConstants.sandLayerEnd) return _MusicZone.surface;
    if (depth < GameConstants.topsoilEnd) return _MusicZone.shallow;
    if (depth < GameConstants.rockEnd) return _MusicZone.deep;
    if (depth < GameConstants.volcanicEnd) return _MusicZone.volcanic;
    return _MusicZone.hell;
  }

  Future<void> _playMusic(_MusicZone zone) async {
    final track = _musicTracks[zone];
    if (track == null) return;

    try {
      await FlameAudio.bgm.stop();
      await FlameAudio.bgm.play(track, volume: _effectiveMusicVolume);
      _musicPlaying = true;
    } catch (_) {
      // Audio file missing or playback error — continue silently
      _musicPlaying = false;
    }
  }

  double get _effectiveMusicVolume => _muted ? 0.0 : _musicVolume;
  double get _effectiveSfxVolume => _muted ? 0.0 : _sfxVolume;

  // ---------------------------------------------------------------------------
  // SFX
  // ---------------------------------------------------------------------------

  /// Play a sound effect. Throttled to prevent spam.
  void playSfx(String path, {double volume = 1.0}) {
    if (_muted || _effectiveSfxVolume <= 0) return;

    // Throttle check
    if (_sfxCooldowns.containsKey(path)) return;
    _sfxCooldowns[path] = _sfxMinInterval;

    try {
      FlameAudio.play(path, volume: volume * _effectiveSfxVolume);
    } catch (_) {
      // Missing audio file — continue silently
    }
  }

  // Convenience methods for common SFX
  void playDrill() => playSfx(sfxDrill, volume: 0.5);
  void playExplosion() => playSfx(sfxExplosion);
  void playOrePickup() => playSfx(sfxOrePickup, volume: 0.7);
  void playEngineThrust() => playSfx(sfxEngineThrust, volume: 0.3);
  void playFuelWarning() => playSfx(sfxFuelWarning);
  void playHullDamage() => playSfx(sfxHullDamage, volume: 0.8);
  void playPurchase() => playSfx(sfxPurchase, volume: 0.6);
  void playSell() => playSfx(sfxSell, volume: 0.6);
  void playLavaBurn() => playSfx(sfxLavaBurn, volume: 0.7);
  void playLanding() => playSfx(sfxLanding, volume: 0.5);

  // ---------------------------------------------------------------------------
  // Volume Controls
  // ---------------------------------------------------------------------------

  void setMusicVolume(double volume) {
    _musicVolume = volume.clamp(0.0, 1.0);
    // Update currently playing music volume
    try {
      FlameAudio.bgm.audioPlayer.setVolume(_effectiveMusicVolume);
    } catch (_) {}
  }

  void setSfxVolume(double volume) {
    _sfxVolume = volume.clamp(0.0, 1.0);
  }

  void toggleMute() {
    _muted = !_muted;
    if (_muted) {
      try {
        FlameAudio.bgm.audioPlayer.setVolume(0);
      } catch (_) {}
    } else {
      try {
        FlameAudio.bgm.audioPlayer.setVolume(_effectiveMusicVolume);
      } catch (_) {}
    }
  }

  void setMuted(bool value) {
    if (_muted == value) return;
    toggleMute();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void pauseAll() {
    try {
      FlameAudio.bgm.pause();
    } catch (_) {}
  }

  void resumeAll() {
    if (!_muted) {
      try {
        FlameAudio.bgm.resume();
      } catch (_) {}
    }
  }

  @override
  void onRemove() {
    try {
      FlameAudio.bgm.stop();
    } catch (_) {}
    super.onRemove();
  }
}

enum _MusicZone { surface, shallow, deep, volcanic, hell }
