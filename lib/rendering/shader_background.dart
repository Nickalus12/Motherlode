import 'dart:ui' as ui;

import 'package:flame/components.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/utils/debug_log.dart';

/// GPU-accelerated procedural background using a fullscreen fragment shader.
///
/// Replaces the old CPU-drawn ParallaxBackground with a single shader pass that
/// renders sky, clouds, cave walls, atmospheric effects, volumetric lighting,
/// and depth-reactive zone transitions — all procedurally on the GPU.
class ShaderBackground extends Component with HasGameReference<MotherlodeGame> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  double _time = 0;
  bool _shaderReady = false;
  String? shaderError;
  int compilationTimeMs = 0;

  /// Whether the GPU shader compiled successfully.
  bool get shaderReady => _shaderReady;

  /// Render behind everything else (matches ParallaxBackground CPU fallback).
  @override
  int get priority => -10;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final sw = Stopwatch()..start();
    try {
      DebugLog.info('ShaderBG', 'Loading background shader...');
      _program = await ui.FragmentProgram.fromAsset('shaders/background.frag');
      _shader = _program!.fragmentShader();
      _shaderReady = true;
      sw.stop();
      compilationTimeMs = sw.elapsedMilliseconds;
      DebugLog.info('ShaderBG', 'Shader compiled OK in ${compilationTimeMs}ms');
    } catch (e, st) {
      sw.stop();
      compilationTimeMs = sw.elapsedMilliseconds;
      shaderError = e.toString();
      DebugLog.error(
          'ShaderBG', 'Shader FAILED after ${compilationTimeMs}ms: $e');
      DebugLog.error('ShaderBG', 'Stack trace: $st');
      _shaderReady = false;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  // Pre-allocated Paint to avoid per-frame allocation
  final ui.Paint _bgPaint = ui.Paint();

  @override
  void render(ui.Canvas canvas) {
    if (!_shaderReady || _shader == null) return;
    // Guard: robot must be mounted before we can read its position
    if (!game.pod.isMounted) return;

    final shader = _shader!;
    final viewport = game.camera.visibleWorldRect;
    final viewWidth = viewport.width;
    final viewHeight = viewport.height;
    if (viewWidth <= 0 || viewHeight <= 0) return;
    final cameraX = viewport.left + viewWidth / 2;
    final cameraY = viewport.top + viewHeight / 2;
    final depthFeet = game.currentDepthFeet;

    final pod = game.pod;
    final lightRadius =
        GameConstants.podLightBaseRadius / GameConstants.pixelsPerMeter +
            game.drillLevel *
                GameConstants.podLightPerLevel /
                GameConstants.pixelsPerMeter;

    // Set float uniforms by index:
    // 0,1: uSize (vec2) — drawn rect dimensions (world units, matching
    //       FlutterFragCoord() range for the drawRect call below)
    shader.setFloat(0, viewWidth);
    shader.setFloat(1, viewHeight);
    // 2,3: uCameraPos (vec2) — camera center in world tiles
    shader.setFloat(2, cameraX);
    shader.setFloat(3, cameraY);
    // 4: uDepthFeet
    shader.setFloat(4, depthFeet);
    // 5: uTime
    shader.setFloat(5, _time);
    // 6,7: uPodPos (vec2)
    shader.setFloat(6, pod.position.x);
    shader.setFloat(7, pod.position.y);
    // 8: uPodLightRadius
    shader.setFloat(8, lightRadius);

    // Draw fullscreen quad covering the visible world rect.
    // Use translate + origin-based rect so FlutterFragCoord() starts at (0,0).
    canvas.save();
    canvas.translate(viewport.left, viewport.top);
    _bgPaint.shader = shader;
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, viewWidth, viewHeight),
      _bgPaint,
    );
    canvas.restore();
  }

  @override
  void onRemove() {
    _shader?.dispose();
    super.onRemove();
  }
}
