# Genesis System Research Document

## Executive Summary

This document covers the technical research for overhauling Motherlode's terrain generation from the current noise+cellular-automata pipeline to a Genesis System using SDF terrain, hydraulic erosion, reaction-diffusion ore placement, and geological stratigraphy. The target platform is Flutter/Flame on Android.

---

## 1. Current Architecture Analysis

### Current Pipeline (WorldGenerator)
1. Multi-octave Simplex noise density map (4 octaves, freq 0.02)
2. Biome-based solid/empty threshold
3. Cellular automata smoothing (4 passes)
4. Biome classification (sand/dirt/rock/obsidian by depth)
5. Micro-noise density variation for marching squares edge quality
6. Drunk-walk ore veins (4-8 cells common, 1-3 ultra rare)
7. Hazard placement (lava, gas via noise thresholds)
8. Creature spawn marking
9. Surface zone flattening
10. Boss arena protection

### Current Data Model
- **TerrainCell**: `CellType` enum, `double density` (0-1), optional `OreType`, `isDirty`, `hasCreatureSpawn`
- **Chunk**: 32x32 grid of TerrainCells, `BodyComponent` with Forge2D collision
- **MarchingSquares**: 4-bit index (0-15), density-interpolated edge crossings, generates visual `Path` polygons + collision edge segments
- **ChunkManager**: Load radius 3, unload radius 5, border data exchange between chunks

### Key Constraint: Chunk Boundaries
Marching squares already handles cross-chunk boundaries via `ChunkBorderData` (top/bottom/left/right rows/columns from neighbors). The SDF system must preserve this seamless boundary mechanism.

### Existing Isolate Support
`chunk_generator_isolate.dart` uses `compute()` for single-shot isolate chunk generation with `ChunkData` as a serializable transfer object. This is the foundation we'll expand for parallel erosion.

---

## 2. SDF Terrain Implementation Strategy

### 2.1 Core SDF Concept

A Signed Distance Field stores the shortest distance from each point to the nearest surface:
- **Positive values** = air/empty space
- **Negative values** = solid terrain
- **Zero** = the exact surface boundary

This is a natural fit for the existing density field. Currently, `density` ranges 0.0-1.0 where 0.0=empty and >threshold=solid. We remap to SDF where:
- `sdfValue = threshold - density` (or use a continuous SDF)
- Negative = inside solid, positive = outside

### 2.2 SDF Data Model

```dart
/// Replace density with SDF value in TerrainCell
class TerrainCell {
  CellType type;
  double sdf;        // Signed distance: negative=solid, positive=air, 0=surface
  double hardness;   // Material hardness (from stratigraphy)
  OreType? oreType;
  double oreConcentration; // 0.0-1.0 from reaction-diffusion
  StratumType stratum;     // Geological layer this cell belongs to
  bool hasCreatureSpawn;
}
```

### 2.3 SDF Primitives for Dart

All SDF primitives return a signed distance from a point to a shape:

```dart
// Sphere/Circle SDF (2D)
double sdfCircle(double px, double py, double cx, double cy, double r) {
  final dx = px - cx;
  final dy = py - cy;
  return sqrt(dx * dx + dy * dy) - r;
}

// Box SDF (axis-aligned)
double sdfBox(double px, double py, double cx, double cy, double hw, double hh) {
  final dx = (px - cx).abs() - hw;
  final dy = (py - cy).abs() - hh;
  return sqrt(max(dx, 0) * max(dx, 0) + max(dy, 0) * max(dy, 0)) + min(max(dx, dy), 0);
}

// Capsule SDF (for tunnels/veins)
double sdfCapsule(double px, double py, double ax, double ay, double bx, double by, double r) {
  final pax = px - ax, pay = py - ay;
  final bax = bx - ax, bay = by - ay;
  final h = ((pax * bax + pay * bay) / (bax * bax + bay * bay)).clamp(0.0, 1.0);
  final dx = pax - bax * h, dy = pay - bay * h;
  return sqrt(dx * dx + dy * dy) - r;
}
```

### 2.4 SDF Boolean Operations

```dart
// Union: combine two shapes (take closer surface)
double sdfUnion(double d1, double d2) => min(d1, d2);

// Subtraction: carve shape2 from shape1
double sdfSubtract(double d1, double d2) => max(d1, -d2);

// Smooth union: blend shapes with smoothing factor k
double sdfSmoothUnion(double d1, double d2, double k) {
  final h = (0.5 + 0.5 * (d2 - d1) / k).clamp(0.0, 1.0);
  return d2 * (1.0 - h) + d1 * h - k * h * (1.0 - h);
}

// Smooth subtraction
double sdfSmoothSubtract(double d1, double d2, double k) {
  final h = (0.5 - 0.5 * (d2 + d1) / k).clamp(0.0, 1.0);
  return d2 * (1.0 - h) + (-d1) * h + k * h * (1.0 - h);
}
```

### 2.5 Drilling as SDF Subtraction

Current drilling removes individual cells. With SDF, drilling subtracts a sphere from the SDF field, creating smooth circular holes:

```dart
void drillAt(double worldX, double worldY, double radius) {
  // For each cell in the affected radius + margin:
  for (int dy = -ceil(radius) - 1; dy <= ceil(radius) + 1; dy++) {
    for (int dx = -ceil(radius) - 1; dx <= ceil(radius) + 1; dx++) {
      final cell = getCell(worldX.round() + dx, worldY.round() + dy);
      if (cell == null) continue;

      final drillSdf = sdfCircle(
        cell.worldX, cell.worldY,
        worldX, worldY, radius,
      );

      // Smooth subtraction: carve the drill hole
      cell.sdf = sdfSmoothSubtract(cell.sdf, drillSdf, 0.3);
    }
  }
  // Mark affected chunks dirty for rebuild
}
```

This gives **smooth, round drill holes** instead of blocky single-cell removal. The drill radius can scale with upgrades.

### 2.6 Surface Extraction (Marching Squares on SDF)

The existing marching squares implementation already works with density values and a threshold. For SDF:
- **Threshold = 0.0** (the zero-crossing of the SDF is the surface)
- **`isSolid` = `sdf < 0`** (negative = inside solid)
- **Edge interpolation** uses SDF values directly (already interpolating between cell corners)

The change to `MarchingSquares` is minimal:
```dart
// Current: if (tl.isSolid) index |= 8;  // where isSolid checks density > threshold
// New:     if (tl.sdf < 0) index |= 8;   // SDF negative = solid

// Edge interpolation already works:
// _interpolateEdge uses density values to find the zero-crossing
// Just use sdf values instead (threshold becomes 0.0)
```

### 2.7 SDF Generation Pipeline

Replace the current noise+threshold+CA pipeline with:

```
1. Base SDF from noise (continuous field, not thresholded)
2. Apply geological stratigraphy (layer boundaries as SDF ops)
3. Cave carving via SDF subtraction of noise-positioned spheres/capsules
4. Hydraulic erosion modifies SDF values
5. Reaction-diffusion determines ore placement within solid regions
6. Surface features, boss arena, hazards applied as SDF operations
```

### 2.8 Collision from SDF

Current collision uses `ChainShape` and `EdgeShape` from marching squares edge segments. This remains identical -- marching squares extracts the same edge geometry from SDF values. No change needed in the Forge2D collision pipeline.

---

## 3. Hydraulic Erosion Algorithm

### 3.1 Particle-Based Erosion (Beyer Algorithm)

Each water droplet is simulated as a particle that flows across the SDF terrain:

```
ALGORITHM: Hydraulic Erosion (per droplet)
==========================================
1. SPAWN droplet at random position on terrain surface
   - position = (x, y) on surface
   - direction = (0, 0)
   - speed = 0
   - water = 1.0
   - sediment = 0.0

2. FOR each step (max ~30-64 steps):
   a. Calculate terrain GRADIENT at (x, y) using SDF neighbors:
      gradX = sdf(x+1, y) - sdf(x-1, y)
      gradY = sdf(x, y+1) - sdf(x, y-1)

   b. Update DIRECTION (with inertia):
      newDirX = dirX * inertia - gradX * (1 - inertia)
      newDirY = dirY * inertia - gradY * (1 - inertia)
      normalize(newDir)

   c. Move to new position:
      newX = x + newDirX
      newY = y + newDirY

   d. Calculate height DIFFERENCE:
      deltaHeight = sdf(newX, newY) - sdf(x, y)

   e. Calculate SEDIMENT CAPACITY:
      capacity = max(-deltaHeight, minSlope) * speed * water * capacityFactor

   f. If sediment > capacity OR going uphill:
      DEPOSIT: amount = (sediment - capacity) * depositionRate
      Increase SDF at (x, y) by -amount (make more solid)
      sediment -= amount

   g. Else:
      ERODE: amount = min((capacity - sediment) * erosionRate, -deltaHeight)
      Decrease SDF at (x, y) by amount (make less solid / more air)
      sediment += amount

   h. Update speed: speed = sqrt(speed^2 + deltaHeight * gravity)
   i. Update water: water *= (1 - evaporationRate)

   j. If water < threshold: STOP

3. Erosion is applied using a brush kernel (radius ~3-4 cells)
   to spread the effect smoothly across neighboring cells.
```

### 3.2 Key Parameters

| Parameter | Typical Value | Effect |
|-----------|--------------|--------|
| inertia | 0.05 | How much previous direction influences flow (low = follows gradient closely) |
| sedimentCapacityFactor | 4.0 | Base capacity multiplier |
| minSlope | 0.01 | Minimum slope for capacity calculation |
| erosionRate | 0.3 | How fast terrain erodes |
| depositionRate | 0.3 | How fast sediment is deposited |
| evaporationRate | 0.01 | Water loss per step |
| gravity | 4.0 | Speed gain from height drop |
| maxDropletLifetime | 30-64 | Maximum steps before droplet dies |
| erosionRadius | 3 | Brush radius for distributing erosion |
| initialWater | 1.0 | Starting water volume |
| initialSpeed | 1.0 | Starting speed |

### 3.3 Erosion Applied to SDF

Unlike height-map erosion, our terrain is a 2D SDF grid. Adaptations:
- **Gradient** is computed from SDF values (already continuous)
- **Erosion** increases SDF (moves surface outward = removes material)
- **Deposition** decreases SDF (moves surface inward = adds material)
- **Depth weighting**: erosion is stronger near the SDF zero-crossing and diminishes deeper into solid regions

### 3.4 Parallelization with Dart Isolates

**Target: 6 Isolates**

The world is divided into vertical strips (columns of chunks). Each isolate processes erosion for its strip independently.

```
World Layout (chunk columns):
  Strip 0    Strip 1    Strip 2    Strip 3    Strip 4    Strip 5
[cx -3...-1] [cx 0...2] [cx 3...5] [cx 6...8] [cx 9..11] [cx 12..14]
  Isolate 0   Isolate 1  Isolate 2  Isolate 3  Isolate 4  Isolate 5
```

**Overlap Zone Handling:**

Each strip includes a 2-cell overlap border with adjacent strips. After all isolates complete, the main isolate blends the overlap zones:

```dart
// Phase 1: Parallel erosion (6 isolates)
final futures = <Future<ErosionResult>>[];
for (int i = 0; i < 6; i++) {
  final strip = extractStrip(worldSdf, i, overlapCells: 2);
  futures.add(Isolate.run(() => runErosion(strip, params)));
}
final results = await Future.wait(futures);

// Phase 2: Merge overlap zones (main isolate)
for (int i = 0; i < 5; i++) {
  blendOverlapZone(results[i], results[i + 1], overlapCells: 2);
}

// Phase 3: Write back to world SDF
for (int i = 0; i < 6; i++) {
  writeStripToWorld(worldSdf, results[i], i);
}
```

**Blending Overlap Zones:**
```dart
void blendOverlapZone(ErosionResult left, ErosionResult right, int overlap) {
  for (int y = 0; y < height; y++) {
    for (int ox = 0; ox < overlap; ox++) {
      final t = ox / overlap; // 0.0 at left edge, 1.0 at right edge
      final leftVal = left.sdf[y][left.width - overlap + ox];
      final rightVal = right.sdf[y][ox];
      final blended = leftVal * (1.0 - t) + rightVal * t;
      left.sdf[y][left.width - overlap + ox] = blended;
      right.sdf[y][ox] = blended;
    }
  }
}
```

### 3.5 Isolate Communication Pattern

Using long-lived isolates (not `compute()`) for the erosion pool:

```dart
class ErosionWorkerPool {
  final List<SendPort> _workerPorts = [];
  final int workerCount;

  Future<void> initialize(int count) async {
    for (int i = 0; i < count; i++) {
      final receivePort = ReceivePort();
      await Isolate.spawn(_erosionWorkerEntry, receivePort.sendPort);
      final workerSendPort = await receivePort.first as SendPort;
      _workerPorts.add(workerSendPort);
    }
  }

  Future<List<ErosionResult>> runErosion(List<SdfStrip> strips) async {
    final completers = <Completer<ErosionResult>>[];
    for (int i = 0; i < strips.length; i++) {
      final c = Completer<ErosionResult>();
      completers.add(c);
      _workerPorts[i].send(ErosionCommand(strip: strips[i], completer: c));
    }
    return Future.wait(completers.map((c) => c.future));
  }

  static void _erosionWorkerEntry(SendPort mainPort) {
    final workerReceive = ReceivePort();
    mainPort.send(workerReceive.sendPort);
    workerReceive.listen((message) {
      final cmd = message as ErosionCommand;
      final result = _processErosion(cmd.strip);
      cmd.replyPort.send(result);
    });
  }
}
```

### 3.6 Performance Estimate

- World size: ~60 chunks wide x 16 chunks deep = ~960 chunks = 983,040 cells
- Droplets: 50,000-100,000 for good erosion
- Per droplet: ~30 steps x ~20 ops = ~600 ops
- Total: ~60M ops, split across 6 isolates = ~10M ops/isolate
- Estimated time on modern mobile: 2-4 seconds (acceptable for load screen)

---

## 4. Reaction-Diffusion Ore Chemistry (Gray-Scott Model)

### 4.1 Gray-Scott Equations

The Gray-Scott model simulates two chemicals (U and V) that react and diffuse:

```
dU/dt = Du * nabla^2(U) - U*V^2 + f*(1 - U)
dV/dt = Dv * nabla^2(V) + U*V^2 - (f + k)*V
```

Where:
- **U** = substrate chemical (starts at 1.0 everywhere)
- **V** = catalyst/activator (seeded at specific points)
- **Du** = diffusion rate of U (typically 1.0)
- **Dv** = diffusion rate of V (typically 0.5)
- **f** = feed rate (replenishment of U)
- **k** = kill rate (removal of V)
- **nabla^2** = Laplacian (diffusion operator)

### 4.2 Pattern Parameters by f/k Values

| Pattern | f | k | Visual | Ore Application |
|---------|---|---|--------|-----------------|
| Spots | 0.035 | 0.065 | Isolated dots | Rare ores (Diamond, Ruby) |
| Stripes/Worms | 0.060 | 0.062 | Winding lines | Vein-like ores (Gold, Platinum) |
| Coral/Maze | 0.040 | 0.060 | Branching networks | Common ore networks (Iron, Bronze) |
| Mitosis | 0.035 | 0.058 | Splitting blobs | Cluster ores (Emerald, Amazonite) |
| Holes | 0.035 | 0.060 | Holes in field | Gas/lava pocket placement |

### 4.3 Laplacian Computation (2D discrete)

```dart
double laplacian(List<List<double>> grid, int x, int y) {
  // 3x3 kernel weights (center = -1, orthogonal = 0.2, diagonal = 0.05)
  return grid[y-1][x] * 0.2 +
         grid[y+1][x] * 0.2 +
         grid[y][x-1] * 0.2 +
         grid[y][x+1] * 0.2 +
         grid[y-1][x-1] * 0.05 +
         grid[y-1][x+1] * 0.05 +
         grid[y+1][x-1] * 0.05 +
         grid[y+1][x+1] * 0.05 +
         grid[y][x] * -1.0;
}
```

### 4.4 CPU Implementation (Dart)

```dart
class GrayScottSimulation {
  late List<List<double>> u, v, nextU, nextV;
  final int width, height;
  final double du, dv, f, k;
  final double dt;

  GrayScottSimulation({
    required this.width,
    required this.height,
    this.du = 1.0,
    this.dv = 0.5,
    required this.f,
    required this.k,
    this.dt = 1.0,
  }) {
    u = List.generate(height, (_) => List.filled(width, 1.0));
    v = List.generate(height, (_) => List.filled(width, 0.0));
    nextU = List.generate(height, (_) => List.filled(width, 0.0));
    nextV = List.generate(height, (_) => List.filled(width, 0.0));
  }

  void seedPoint(int x, int y, int radius) {
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (dx*dx + dy*dy <= radius*radius) {
          final px = (x + dx).clamp(0, width - 1);
          final py = (y + dy).clamp(0, height - 1);
          v[py][px] = 1.0;
          u[py][px] = 0.5;
        }
      }
    }
  }

  void step() {
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final uVal = u[y][x];
        final vVal = v[y][x];
        final uvv = uVal * vVal * vVal;
        final lapU = laplacian(u, x, y);
        final lapV = laplacian(v, x, y);

        nextU[y][x] = uVal + (du * lapU - uvv + f * (1.0 - uVal)) * dt;
        nextV[y][x] = vVal + (dv * lapV + uvv - (f + k) * vVal) * dt;
      }
    }
    // Swap buffers
    final tmpU = u; u = nextU; nextU = tmpU;
    final tmpV = v; v = nextV; nextV = tmpV;
  }

  void run(int iterations) {
    for (int i = 0; i < iterations; i++) step();
  }
}
```

### 4.5 GPU Feasibility (Flutter Fragment Shaders)

**Can Flutter fragment shaders run reaction-diffusion on GPU?**

**YES, with limitations:**

Flutter supports GLSL fragment shaders via `FragmentProgram.fromAsset()`. The shader runs per-pixel on the GPU. For reaction-diffusion:

```glsl
#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // Grid dimensions
uniform float uDt;         // Time step
uniform float uF;          // Feed rate
uniform float uK;          // Kill rate
uniform float uDu;         // U diffusion
uniform float uDv;         // V diffusion
uniform sampler2D uState;  // Previous state (R=U, G=V)

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 texel = 1.0 / uSize;

  vec4 c = texture(uState, uv);
  float U = c.r;
  float V = c.g;

  // Laplacian via neighbor sampling
  float lapU = 0.0, lapV = 0.0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec4 n = texture(uState, uv + vec2(dx, dy) * texel);
      float w = (dx == 0 && dy == 0) ? -1.0 :
                (dx == 0 || dy == 0) ? 0.2 : 0.05;
      lapU += n.r * w;
      lapV += n.g * w;
    }
  }

  float uvv = U * V * V;
  float newU = U + (uDu * lapU - uvv + uF * (1.0 - U)) * uDt;
  float newV = V + (uDv * lapV + uvv - (uF + uK) * V) * uDt;

  fragColor = vec4(clamp(newU, 0.0, 1.0), clamp(newV, 0.0, 1.0), 0.0, 1.0);
}
```

**Ping-pong rendering technique:**
1. Render to texture A using state from texture B
2. Next frame: render to texture B using state from texture A
3. Repeat for N iterations

**Flutter implementation:**
```dart
class ReactionDiffusionGPU {
  late FragmentProgram _program;
  late FragmentShader _shader;
  Image? _stateA, _stateB;
  bool _useA = true;

  Future<void> init() async {
    _program = await FragmentProgram.fromAsset('shaders/reaction_diffusion.frag');
    _shader = _program.fragmentShader();
    // Initialize state textures with seed points
  }

  Image stepOnGPU(Size size) {
    final input = _useA ? _stateA! : _stateB!;

    _shader.setFloat(0, size.width);    // uSize.x
    _shader.setFloat(1, size.height);   // uSize.y
    _shader.setFloat(2, 1.0);           // uDt
    _shader.setFloat(3, 0.035);         // uF
    _shader.setFloat(4, 0.065);         // uK
    _shader.setFloat(5, 1.0);           // uDu
    _shader.setFloat(6, 0.5);           // uDv
    _shader.setImageSampler(0, input);  // uState

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = _shader,
    );
    final picture = recorder.endRecording();
    final output = picture.toImageSync(size.width.toInt(), size.height.toInt());

    if (_useA) _stateB = output; else _stateA = output;
    _useA = !_useA;

    return output;
  }
}
```

**Limitations:**
- Flutter fragment shaders **cannot write to storage buffers** -- output is always a rendered image
- Ping-pong requires `toImageSync()` per iteration (has overhead)
- No compute shaders in Flutter (only fragment shaders)
- Maximum texture size varies by device (typically 4096x4096 or 8192x8192)

**Recommendation:** Use GPU for reaction-diffusion during the Genesis load screen where visual feedback is desired. Fall back to CPU (Dart isolate) for production data generation where we need exact numeric values for ore placement. Run ~200-500 iterations on a 256x256 grid per biome layer.

### 4.6 CPU Fallback Performance

- Grid: 256x256 = 65,536 cells
- Per step: 65,536 cells x 9 neighbor reads + 4 math ops = ~650K ops
- 500 iterations = 325M ops
- Dart on mobile: ~100-200M ops/sec for float math
- Estimated: 2-3 seconds per pattern
- Can run in isolate to avoid UI jank

### 4.7 Ore Placement from Reaction-Diffusion

After running Gray-Scott, the V field contains the pattern. Ore placement:

```dart
void placeOresFromRD(List<List<double>> vField, List<List<TerrainCell>> cells) {
  for (int y = 0; y < cells.length; y++) {
    for (int x = 0; x < cells[0].length; x++) {
      if (!cells[y][x].isSolid) continue;

      final concentration = vField[y][x];
      if (concentration > oreThreshold) {
        cells[y][x].type = CellType.ore;
        cells[y][x].oreConcentration = concentration;
        cells[y][x].oreType = selectOreByBiomeAndConcentration(
          cells[y][x].stratum,
          concentration,
        );
      }
    }
  }
}
```

Different f/k parameters per biome depth create naturally varied ore distribution patterns.

---

## 5. Geological Stratigraphy Data Model

### 5.1 Concept

Replace the current simple biome bands (topsoil/rock/volcanic/hell) with a proper geological column where layers fold, fault, and vary in thickness.

### 5.2 Stratum Definition

```dart
enum StratumType {
  topsoil,      // 0-200ft    - loose, sandy
  sandstone,    // 100-400ft  - compressed sand
  limestone,    // 300-800ft  - calcium-rich, fossils
  shale,        // 600-1200ft - layered, oil-bearing
  granite,      // 1000-2500ft - hard igneous
  basalt,       // 2000-4000ft - volcanic, dense
  obsidianFlow, // 3500-5500ft - volcanic glass
  mantleRock,   // 5000-7000ft - extreme pressure
  hellstone,    // 6500-7500ft - supernatural
}

class Stratum {
  final StratumType type;
  final double baseDepth;       // Nominal depth (feet)
  final double thickness;        // Nominal thickness (feet)
  final double hardness;         // Drilling resistance
  final double porosity;         // Affects erosion susceptibility
  final CellType cellType;       // Visual representation
  final Color primaryColor;
  final List<OreType> nativeOres; // Ores found in this stratum
  final double foldAmplitude;    // How much this layer folds (0 = flat)
  final double foldFrequency;    // Spatial frequency of folds
}
```

### 5.3 Layer Boundary Generation

Strata boundaries are not flat lines -- they fold using noise:

```dart
double getStratumBoundary(StratumType stratum, double worldX, int seed) {
  final base = stratum.baseDepth;

  // Large-scale folds (geological folding)
  final fold = NoiseUtils.sampleMultiOctave(
    seed: seed + stratum.index * 1000,
    x: worldX,
    y: 0.0,
    octaves: 3,
    frequency: 0.005,  // Very low frequency = broad folds
    gain: 0.5,
  );

  // Small-scale variation
  final detail = NoiseUtils.sampleMultiOctave(
    seed: seed + stratum.index * 2000,
    x: worldX,
    y: 0.0,
    octaves: 2,
    frequency: 0.02,
    gain: 0.3,
  );

  return base + fold * stratum.foldAmplitude + detail * 30.0;
}
```

### 5.4 Integration with SDF

The stratigraphy system provides **material properties** to the SDF terrain. The SDF determines shape (solid/air), and stratigraphy determines what material occupies each solid cell:

```dart
TerrainCell generateCell(int worldX, int worldY, double sdf) {
  if (sdf >= 0) return TerrainCell(type: CellType.empty, sdf: sdf);

  final depthFeet = worldY * feetPerTile;
  final stratum = getStratumAtPosition(worldX, depthFeet);

  return TerrainCell(
    type: stratum.cellType,
    sdf: sdf,
    hardness: stratum.hardness,
    stratum: stratum.type,
  );
}
```

### 5.5 Fault Lines

Geological faults shift strata vertically along a line:

```dart
double applyFault(double depthFeet, double worldX, FaultLine fault) {
  // Distance from fault line
  final distToFault = worldX - fault.worldX;

  // Fault displacement (one side shifts up, other shifts down)
  if (distToFault > 0) {
    return depthFeet - fault.displacement * smoothstep(0, fault.width, distToFault);
  } else {
    return depthFeet + fault.displacement * smoothstep(0, fault.width, -distToFault);
  }
}
```

---

## 6. Key Risks and Mitigations

### Risk 1: Performance on Mobile
- **Risk**: SDF evaluation + erosion + reaction-diffusion may be too slow for mobile
- **Mitigation**:
  - Pre-compute during Genesis load screen (2-5 second budget)
  - Use isolates for parallel work (6 isolates for erosion)
  - Cache results aggressively (SDF grid stored per chunk, not re-evaluated)
  - Reduce grid resolution if needed (64x64 reaction-diffusion scaled to 256x256)

### Risk 2: Isolate Data Transfer Overhead
- **Risk**: Sending large SDF grids between isolates is expensive (deep copy)
- **Mitigation**:
  - Use `TransferableTypedData` for Float64List buffers (zero-copy transfer)
  - Send strip regions, not full world data
  - Use `Isolate.exit()` with result to avoid copy on return

### Risk 3: Fragment Shader Compatibility
- **Risk**: Flutter GLSL shaders may not work on all Android devices
- **Mitigation**:
  - Always implement CPU fallback
  - GPU path is optional enhancement for load screen visualization
  - Test on minimum spec devices early

### Risk 4: Marching Squares Compatibility
- **Risk**: Switching from density (0-1) to SDF (negative-positive) may break edge cases
- **Mitigation**:
  - SDF is a superset of density -- just remap the threshold
  - `isSolid` becomes `sdf < 0` instead of `density > threshold`
  - Edge interpolation uses SDF values with threshold 0.0
  - Incremental migration: first convert density to SDF representation, verify rendering, then add new features

### Risk 5: Erosion Artifacts at Chunk Boundaries
- **Risk**: Erosion particles crossing chunk boundaries may create visible seams
- **Mitigation**:
  - Run erosion on the full world SDF (not per-chunk)
  - Then partition into chunks for storage
  - Overlap zones in isolate parallelization handle strip boundaries

### Risk 6: Memory Usage
- **Risk**: Full world SDF + reaction-diffusion grids may exceed mobile memory
- **Mitigation**:
  - Only active chunks hold full TerrainCell data
  - Reaction-diffusion uses temporary 256x256 grids (512KB), freed after ore placement
  - Erosion processes strips sequentially within isolates

---

## 7. Recommended Implementation Order

### Phase 1: SDF Foundation (Task #2)
1. Add `sdf` field to `TerrainCell`, keep `density` as alias for backward compat
2. Implement SDF primitives library (`sdf_primitives.dart`)
3. Convert `WorldGenerator` to output SDF values instead of density
4. Update `MarchingSquares` to use `sdf < 0` for solid check and `sdf` for interpolation
5. Update `DrillSystem` to use SDF sphere subtraction
6. **Verify**: Existing gameplay works identically with SDF values

### Phase 2: Geological Stratigraphy (Task #5)
1. Define `Stratum` and `StratumType` data model
2. Implement noise-based layer boundary generation
3. Replace simple biome classification with stratigraphy lookup
4. Add fault line generation
5. Update terrain colors to use stratum-based palette
6. **Verify**: Visual terrain shows geological layers with folding

### Phase 3: Hydraulic Erosion (Task #3)
1. Implement single-threaded erosion algorithm on SDF grid
2. Test erosion quality and tune parameters
3. Implement `ErosionWorkerPool` with 6 long-lived isolates
4. Implement strip-based parallelization with overlap blending
5. Integrate into world generation pipeline (runs during Genesis)
6. **Verify**: Terrain shows natural erosion features (river channels, overhangs)

### Phase 4: Reaction-Diffusion Ore Placement (Task #4)
1. Implement `GrayScottSimulation` CPU class
2. Define f/k parameter sets per stratum type
3. Implement ore placement from V-field concentrations
4. (Optional) Implement GPU shader for load screen visualization
5. Replace drunk-walk ore veins with R-D generated patterns
6. **Verify**: Ore distribution shows organic, varied patterns

### Phase 5: Genesis Load Screen (Task #6)
1. Design load screen UI with progress stages
2. Add real-time visualization of stratigraphy forming
3. Add erosion visualization (particles flowing)
4. Add reaction-diffusion visualization (patterns emerging)
5. Wire up actual generation pipeline to visualization

### Phase 6: Integration (Task #7)
1. Full pipeline: Strata -> SDF -> Erosion -> R-D -> Chunks
2. Performance profiling and optimization
3. Tune all parameters for gameplay balance
4. Update save/load system for new data model
5. Regression testing of drilling, collisions, creatures

---

## 8. Technical Reference: Flutter/Dart APIs

### FragmentShader API
- `FragmentProgram.fromAsset('shaders/my.frag')` - loads compiled shader
- `program.fragmentShader()` - creates shader instance
- `shader.setFloat(index, value)` - set uniform float
- `shader.setImageSampler(index, image)` - set texture input
- Shaders must be listed in `pubspec.yaml` under `flutter: > shaders:`
- GLSL version 460 core with `#include <flutter/runtime_effect.glsl>`
- Output is `fragColor` (vec4), input position via `FlutterFragCoord()`

### Dart Isolate API
- `Isolate.run(function)` - one-shot isolate (simplest)
- `Isolate.spawn(entryPoint, message)` - long-lived isolate
- `SendPort.send(message)` - send data (deep copied unless TransferableTypedData)
- `ReceivePort` / `RawReceivePort` - receive messages
- `TransferableTypedData.fromList([bytes])` - zero-copy typed data transfer
- `Isolate.exit(sendPort, result)` - exit with result (avoids copy)

### Flame Engine
- `BodyComponent` with Forge2D for physics bodies
- `Component` tree for game objects
- Custom `render(Canvas)` for drawing
- `PostProcessComponent` with `PostProcess` for shader effects
- `FragmentProgram` integration for custom shaders in rendering pipeline

---

## 9. File Impact Assessment

### Files to Modify
| File | Change |
|------|--------|
| `lib/world/terrain_cell.dart` | Add `sdf`, `stratum`, `oreConcentration` fields; update `isSolid` |
| `lib/world/world_generator.dart` | Replace noise+CA pipeline with SDF generation |
| `lib/world/marching_squares.dart` | Use `sdf < 0` for solid, `sdf` values for interpolation |
| `lib/world/chunk.dart` | Update to use SDF-based TerrainCell |
| `lib/world/chunk_manager.dart` | Support new generation pipeline |
| `lib/world/biome.dart` | Replace with stratigraphy system |
| `lib/world/chunk_data.dart` | Add SDF and stratum fields to serialization |
| `lib/world/chunk_generator_isolate.dart` | Expand for erosion worker pool |
| `lib/entities/pod/drill_system.dart` | SDF sphere subtraction for drilling |
| `lib/rendering/terrain_renderer.dart` | Stratum-based coloring |
| `lib/utils/constants.dart` | Add SDF/erosion/R-D constants |
| `pubspec.yaml` | Add shader assets if using GPU R-D |

### New Files to Create
| File | Purpose |
|------|---------|
| `lib/world/sdf_primitives.dart` | SDF shape functions and boolean ops |
| `lib/world/stratigraphy.dart` | Geological layer system |
| `lib/world/hydraulic_erosion.dart` | Erosion simulation |
| `lib/world/erosion_worker_pool.dart` | Isolate pool for parallel erosion |
| `lib/world/reaction_diffusion.dart` | Gray-Scott simulation |
| `lib/world/genesis_pipeline.dart` | Orchestrates full generation |
| `lib/ui/genesis_screen.dart` | Load screen with visualization |
| `shaders/reaction_diffusion.frag` | GPU R-D shader (optional) |
