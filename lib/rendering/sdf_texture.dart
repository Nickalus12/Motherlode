import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:motherlode/world/chunk.dart';
import 'package:motherlode/world/ore_registry.dart';
import 'package:motherlode/world/terrain_cell.dart';
import 'package:motherlode/utils/constants.dart';

/// Encodes chunk terrain data into RGBA textures for GPU shader consumption.
///
/// Channel layout:
///   R = SDF value mapped from [-2.0, +2.0] to [0, 255]. 128 = surface (sdf 0.0).
///   G = Material ID byte (stratum index 0-8, ore=9, lava=10, empty=0).
///   B = Sub-type: ore index for ores, hardness byte for terrain.
///   A = Bit-packed flags (is_ore, is_lava, is_bedrock, is_gas).
class SdfTextureEncoder {
  SdfTextureEncoder._();

  static const int _chunkSize = GameConstants.chunkSize; // 32

  /// Encode a chunk's terrain cells into an RGBA [ui.Image].
  static Future<ui.Image> encodeChunk(Chunk chunk) async {
    final pixels = Uint8List(_chunkSize * _chunkSize * 4);

    for (int y = 0; y < _chunkSize; y++) {
      for (int x = 0; x < _chunkSize; x++) {
        final i = (y * _chunkSize + x) * 4;
        final cell = chunk.cells[y][x];
        pixels[i + 0] = _encodeR(cell);
        pixels[i + 1] = _encodeG(cell);
        pixels[i + 2] = _encodeB(cell);
        pixels[i + 3] = _encodeA(cell);
      }
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: _chunkSize,
      height: _chunkSize,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final image = frame.image;

    codec.dispose();
    descriptor.dispose();
    buffer.dispose();

    return image;
  }

  /// R channel: SDF value mapped from [-2.0, +2.0] to [0, 255].
  static int _encodeR(TerrainCell cell) {
    return ((cell.sdf + 2.0) / 4.0 * 255.0).round().clamp(0, 255);
  }

  /// G channel: Material ID byte.
  static int _encodeG(TerrainCell cell) {
    if (cell.type == CellType.empty) return 0;
    if (cell.type == CellType.lava) return 10;
    if (cell.type == CellType.ore) return 9;
    // Use stratum index if available (0-8), otherwise fall back to 0
    return cell.stratum?.index ?? 0;
  }

  /// B channel: Sub-type byte.
  static int _encodeB(TerrainCell cell) {
    if (cell.type == CellType.ore && cell.oreType != null) {
      return _oreIndex(cell.oreType!);
    }
    // Terrain hardness encoded as byte
    final h = cell.hardness;
    if (h == double.infinity) return 255;
    return (h * 25.0).round().clamp(0, 255);
  }

  /// A channel: Bit-packed flags.
  static int _encodeA(TerrainCell cell) {
    int flags = 0;
    if (cell.type == CellType.ore) flags |= 1;
    if (cell.type == CellType.lava) flags |= 2;
    if (cell.type == CellType.bedrock) flags |= 4;
    if (cell.type == CellType.gas) flags |= 8;
    return flags;
  }

  /// Map an [OreType] to its index in [OreRegistry.allOres].
  static int _oreIndex(OreType ore) {
    final idx = OreRegistry.allOres.indexOf(ore);
    return idx >= 0 ? idx : 0;
  }

  /// Decode an SDF byte back to a float value (for verification/debugging).
  static double decodeSdf(int byte) => (byte / 255.0) * 4.0 - 2.0;
}

/// LRU cache of encoded SDF textures keyed by chunk coordinate string.
///
/// Uses [LinkedHashMap] with access-order semantics to evict least-recently-used
/// textures when the cache exceeds [_maxSize]. GPU textures are disposed on eviction.
class SdfTextureCache {
  static const int _maxSize = 120;

  final LinkedHashMap<String, ui.Image> _cache =
      LinkedHashMap<String, ui.Image>();

  /// Chunks that need async texture generation queued.
  final Set<String> _pending = {};

  /// Get (or create) the SDF texture for a chunk.
  /// Re-encodes if the chunk is dirty or not yet cached.
  Future<ui.Image> getTexture(Chunk chunk) async {
    final key = '${chunk.chunkX},${chunk.chunkY}';
    if (chunk.isDirty || !_cache.containsKey(key)) {
      _cache.remove(key)?.dispose();
      final image = await SdfTextureEncoder.encodeChunk(chunk);
      _cache[key] = image;
      _evict();
    } else {
      _touch(key);
    }
    return _cache[key]!;
  }

  /// Synchronous texture getter for use in render().
  /// Returns cached texture if available, or queues async generation.
  /// Returns null if texture isn't ready yet.
  ui.Image? getTextureSync(Chunk chunk) {
    final key = '${chunk.chunkX},${chunk.chunkY}';
    if (chunk.isDirty || !_cache.containsKey(key)) {
      if (!_pending.contains(key)) {
        _pending.add(key);
        _cache.remove(key)?.dispose();
        // Queue async encode
        SdfTextureEncoder.encodeChunk(chunk).then((image) {
          _cache[key] = image;
          _pending.remove(key);
          _evict();
        });
      }
      return _cache[key]; // May be null on first frame
    }
    _touch(key);
    return _cache[key];
  }

  /// Move entry to end (most recently used).
  void _touch(String key) {
    final image = _cache.remove(key);
    if (image != null) {
      _cache[key] = image;
    }
  }

  /// Evict oldest entries until at or below capacity, disposing GPU textures.
  void _evict() {
    while (_cache.length > _maxSize) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)?.dispose();
      _pending.remove(oldest);
    }
  }

  /// Invalidate a cached texture by chunk key (e.g. "3,-5").
  void invalidate(String key) {
    _cache.remove(key)?.dispose();
    _pending.remove(key);
  }

  /// Dispose all cached textures.
  void dispose() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
    _pending.clear();
  }
}
