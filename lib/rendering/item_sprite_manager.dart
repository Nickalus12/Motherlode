import 'dart:ui' as ui;

import 'package:flame/flame.dart';

/// Manages loading and frame extraction for 4x4 item sprite sheets.
class ItemSpriteManager {
  ItemSpriteManager._();

  static final ItemSpriteManager instance = ItemSpriteManager._();

  static const int columns = 4;
  static const int rows = 4;
  static const int totalFrames = columns * rows;

  final Map<String, ui.Image> _cache = {};

  /// Load a sprite sheet image and cache it. Returns the loaded image.
  Future<ui.Image> load(String spritePath) async {
    final cached = _cache[spritePath];
    if (cached != null) return cached;

    final image = await Flame.images.load(spritePath);
    _cache[spritePath] = image;
    return image;
  }

  /// Get the cached image for a sprite path. Returns null if not yet loaded.
  ui.Image? getImage(String spritePath) => _cache[spritePath];

  /// Whether a cached sprite is a single-frame image (not a 4x4 sheet).
  /// Single-frame sprites are square images smaller than 64px or non-square.
  bool isSingleFrame(String spritePath) {
    final image = _cache[spritePath];
    if (image == null) return true;
    // A 4x4 sheet should be at least 64x64 (16px per frame minimum)
    // and width should equal height. Single frames are typically 32x32.
    return image.width < 64 || image.height < 64 || image.width != image.height;
  }

  /// Get the source [Rect] for a specific frame index.
  /// Handles both 4x4 sprite sheets and single-frame images.
  ui.Rect getFrame(String spritePath, int frameIndex) {
    final image = _cache[spritePath];
    if (image == null) {
      return ui.Rect.zero;
    }

    // Single-frame image — return full rect
    if (isSingleFrame(spritePath)) {
      return ui.Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble(),
      );
    }

    final clampedIndex = frameIndex.clamp(0, totalFrames - 1);
    final col = clampedIndex % columns;
    final row = clampedIndex ~/ columns;
    final frameWidth = image.width / columns;
    final frameHeight = image.height / rows;

    return ui.Rect.fromLTWH(
      col * frameWidth,
      row * frameHeight,
      frameWidth,
      frameHeight,
    );
  }

  /// Get the animated frame index based on elapsed time and desired FPS.
  int getAnimatedFrame(double time, double fps) {
    return ((time * fps) % totalFrames).floor();
  }

  /// Preload multiple sprite paths in parallel.
  Future<void> preloadAll(Iterable<String> spritePaths) async {
    await Future.wait(spritePaths.map(load));
  }

  /// Clear all cached images.
  void dispose() {
    _cache.clear();
  }
}
