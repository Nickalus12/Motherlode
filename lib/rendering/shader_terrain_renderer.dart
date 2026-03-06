import 'dart:ui' as ui;

import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/rendering/sdf_texture.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/utils/debug_log.dart';
import 'package:motherlode/world/chunk.dart';

/// GPU-accelerated terrain renderer using SDF fragment shader.
///
/// Replaces the old polygon-based TerrainRenderer with per-pixel SDF evaluation
/// on the GPU. Each visible chunk's SDF data is packed into a 32×32 RGBA texture,
/// and the fragment shader handles smooth edges, procedural texturing, lighting,
/// ambient occlusion, grass, and animated effects — all per-pixel.
class ShaderTerrainRenderer extends Component
    with HasGameReference<MotherlodeGame> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  final SdfTextureCache _textureCache = SdfTextureCache();
  double _time = 0;
  bool _shaderReady = false;
  String? shaderError;
  int compilationTimeMs = 0;

  /// Whether the GPU shader compiled successfully.
  bool get shaderReady => _shaderReady;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final sw = Stopwatch()..start();
    try {
      DebugLog.info('ShaderTerrain', 'Loading terrain shader...');
      _program = await ui.FragmentProgram.fromAsset('shaders/terrain.frag');
      _shader = _program!.fragmentShader();
      _shaderReady = true;
      sw.stop();
      compilationTimeMs = sw.elapsedMilliseconds;
      DebugLog.info(
          'ShaderTerrain', 'Shader compiled OK in ${compilationTimeMs}ms');
    } catch (e, st) {
      sw.stop();
      compilationTimeMs = sw.elapsedMilliseconds;
      shaderError = e.toString();
      DebugLog.error(
          'ShaderTerrain', 'Shader FAILED after ${compilationTimeMs}ms: $e');
      DebugLog.error('ShaderTerrain', 'Stack trace: $st');
      _shaderReady = false;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(ui.Canvas canvas) {
    if (!_shaderReady || _shader == null) return;

    final visibleChunks = _getVisibleChunks();
    final pod = game.pod;
    final depthFeet = game.currentDepthFeet;
    final lightRadius =
        GameConstants.podLightBaseRadius / GameConstants.pixelsPerMeter +
            game.drillLevel *
                GameConstants.podLightPerLevel /
                GameConstants.pixelsPerMeter;

    for (final chunk in visibleChunks) {
      _renderChunk(canvas, chunk, pod.position, lightRadius, depthFeet);
    }
  }

  void _renderChunk(
    ui.Canvas canvas,
    Chunk chunk,
    Vector2 podPos,
    double lightRadius,
    double depthFeet,
  ) {
    final shader = _shader!;
    final chunkWorldX = chunk.chunkX * GameConstants.chunkSize.toDouble();
    final chunkWorldY = chunk.chunkY * GameConstants.chunkSize.toDouble();
    final chunkSizePx = GameConstants.chunkSize.toDouble();

    // Get or create the SDF texture for this chunk
    final sdfTexture = _textureCache.getTextureSync(chunk);
    if (sdfTexture == null) return;

    // Set float uniforms by index:
    // 0,1: uSize (vec2) — output rect size in pixels (chunk size in world units)
    shader.setFloat(0, chunkSizePx);
    shader.setFloat(1, chunkSizePx);
    // 2,3: uChunkWorldPos (vec2) — chunk origin in world tiles
    shader.setFloat(2, chunkWorldX);
    shader.setFloat(3, chunkWorldY);
    // 4: uTime
    shader.setFloat(4, _time);
    // 5,6: uPodPos (vec2) — pod world position in tiles
    shader.setFloat(5, podPos.x);
    shader.setFloat(6, podPos.y);
    // 7: uPodLightRadius
    shader.setFloat(7, lightRadius);
    // 8: uDepthFeet
    shader.setFloat(8, depthFeet);
    // 9: uChunkSize
    shader.setFloat(9, chunkSizePx);

    // Set sampler 0: SDF texture
    shader.setImageSampler(0, sdfTexture);

    // Draw the chunk rect in world space
    canvas.save();
    canvas.translate(chunkWorldX, chunkWorldY);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, chunkSizePx, chunkSizePx),
      ui.Paint()..shader = shader,
    );
    canvas.restore();
  }

  List<Chunk> _getVisibleChunks() {
    final viewport = game.camera.visibleWorldRect;
    final chunkTileSize = GameConstants.chunkSize.toDouble();

    final minChunkX = (viewport.left / chunkTileSize).floor() - 1;
    final maxChunkX = (viewport.right / chunkTileSize).ceil() + 1;
    final minChunkY = (viewport.top / chunkTileSize).floor() - 1;
    final maxChunkY = (viewport.bottom / chunkTileSize).ceil() + 1;

    final visible = <Chunk>[];
    for (int x = minChunkX; x <= maxChunkX; x++) {
      for (int y = minChunkY; y <= maxChunkY; y++) {
        final chunk = game.chunkManager.getLoadedChunk(x, y);
        if (chunk != null) visible.add(chunk);
      }
    }
    return visible;
  }

  @override
  void onRemove() {
    _textureCache.dispose();
    _shader?.dispose();
    super.onRemove();
  }
}
