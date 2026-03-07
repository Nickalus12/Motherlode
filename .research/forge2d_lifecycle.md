# Forge2D BodyComponent Lifecycle Research

## Key Finding: Root Cause of Pod Falling Through Terrain

### The Problem
The pod (dynamic BodyComponent) falls through terrain chunks (static BodyComponents) as if no collision geometry exists.

### Root Cause Analysis

There are **three interacting issues**:

---

## Issue 1: CRITICAL - Collision Segment Coordinate Space Mismatch

**File:** `lib/world/marching_squares.dart` lines 105-115, and `lib/world/chunk.dart` lines 129-155

The marching squares algorithm generates collision segments in **chunk-local tile coordinates** (e.g., `x=0..31, y=0..31`). These offsets represent tile positions within the chunk.

In `Chunk.createBody()` (chunk.dart:101-115), the body is created at `worldPositionMeters` which is:
```dart
Vector2(chunkX * chunkSize, chunkY * chunkSize)  // e.g., (0, 0), (32, 0), etc.
```

The collision segments from marching squares use local tile offsets (0..31). Since the body position is already at the chunk's world origin, these local offsets are correctly **relative to the body position**. This part is actually fine.

However, there's a **unit mismatch** to investigate. The `worldPositionMeters` uses `chunkSize` (32) directly as "meters", and the collision vertices also use raw tile indices (0..31). Meanwhile, `pixelsPerMeter` is 10.0 and `tileSize` is 64.0. The Forge2D world zoom is set to `pixelsPerMeter` (10.0).

**The collision geometry vertices span 0-31 tile units in body-local space, but the pod is only 1.8m x 2.2m.** If the terrain body is at position (0, 0) in Forge2D meters and collision edges span 0-31 "meters", a chunk covers 32 meters. The pod at position (0, -2) would need to fall onto collision edges around y=0 to y=31. This seems like it *should* work geometrically, but the scale is enormous relative to the pod.

---

## Issue 2: CRITICAL - Async Lifecycle Race Condition

**File:** `lib/motherlode_game.dart` lines 108-119

```dart
world.add(parallaxBackground);
await world.add(chunkManager);          // ChunkManager is a plain Component, not BodyComponent
world.add(terrainRenderer);

chunkManager.forceLoadAroundSpawn();     // Calls _loadChunk -> world.add(chunk)

await Future<void>.delayed(Duration.zero);  // Microtask yield

await world.add(pod);                    // Pod is a BodyComponent
```

### BodyComponent Lifecycle (from Flame source & docs):
1. `world.add(component)` queues the component for processing
2. During the next game tick, the component's `onLoad()` is called
3. For `BodyComponent`, `createBody()` is called **inside `onLoad()`** (before `super.onLoad()` returns or as part of it)
4. After `onLoad()` completes, `onMount()` is called
5. The component's `loaded` future completes

### The Race:
- `chunkManager.forceLoadAroundSpawn()` calls `_game.world.add(chunk)` for each chunk
- These `world.add()` calls are **non-awaited** (fire-and-forget in `_loadChunk`)
- `Future<void>.delayed(Duration.zero)` only yields one microtask - this is NOT sufficient to ensure all chunk bodies are created
- Flame processes component additions in batches during `processLifecycleEvents()`, which happens at the **start of the next update tick**
- `await world.add(pod)` - the pod's body IS awaited, but it may be processed in the SAME tick as the chunks, meaning chunk bodies might not exist yet when the pod body is created

**The `Duration.zero` delay is insufficient.** It yields a single microtask, but Flame's component lifecycle processing happens during `update()`, not during microtask resolution. The chunks' `createBody()` methods may not have been called yet when the pod's `createBody()` runs.

---

## Issue 3: POTENTIAL - Empty Collision Segments

**File:** `lib/world/marching_squares.dart` line 184-187

For case 15 (all 4 corners solid - fully interior cells), `edgeVerts` is empty:
```dart
case 15: // All solid - full square
  polyVerts = [tlPos, trPos, brPos, blPos];
  edgeVerts = [];
  break;
```

This is correct for marching squares (no boundary edge for fully-solid interior), but it means that large solid regions only have collision edges at their **boundaries**. If the chunk is mostly solid, only the surface cells at the air/solid boundary will have collision geometry. This is actually correct behavior - the pod should collide with the surface edges.

**However**, if there's a bug causing zero collision segments to be generated (e.g., all cells are empty in spawn chunks), the pod would have nothing to collide with.

---

## Issue 4: ChunkManager._loadChunk Does Not Await

**File:** `lib/world/chunk_manager.dart` line 105

```dart
_game.world.add(chunk);  // Not awaited!
```

The `_loadChunk` method is `void`, not `Future<void>`. It cannot await the chunk being added. This means `forceLoadAroundSpawn()` fires off multiple `world.add()` calls that are all pending, and none are guaranteed to have their `createBody()` called before the pod is added.

---

## Recommended Fixes

### Fix 1: Make forceLoadAroundSpawn async and await chunk loading

```dart
// chunk_manager.dart
Future<void> forceLoadAroundSpawn() async {
  final futures = <Future<void>>[];
  for (int dy = -GameConstants.chunkLoadRadius;
      dy <= GameConstants.chunkLoadRadius;
      dy++) {
    for (int dx = -GameConstants.chunkLoadRadius;
        dx <= GameConstants.chunkLoadRadius;
        dx++) {
      final key = _chunkKey(dx, dy);
      if (!_activeChunks.containsKey(key)) {
        futures.add(_loadChunkAsync(key));
      }
    }
  }
  await Future.wait(futures);
}

Future<void> _loadChunkAsync(String key) async {
  final parts = key.split(',');
  final cx = int.parse(parts[0]);
  final cy = int.parse(parts[1]);

  List<List<TerrainCell>> cellData;
  if (_chunkDataCache.containsKey(key)) {
    cellData = _chunkDataCache.remove(key)!;
  } else {
    cellData = worldGenerator.generateChunk(cx, cy);
  }

  final chunk = Chunk(chunkX: cx, chunkY: cy, cells: cellData);
  _activeChunks[key] = chunk;
  await _game.world.add(chunk);
  // Ensure chunk body is created
  await chunk.loaded;
}
```

### Fix 2: Update motherlode_game.dart to properly await

```dart
// motherlode_game.dart - in onLoad()
world.add(parallaxBackground);
await world.add(chunkManager);
world.add(terrainRenderer);

// Force-load terrain chunks and AWAIT their body creation
await chunkManager.forceLoadAroundSpawn();

// Now chunks are guaranteed to have physics bodies
await world.add(pod);
world.add(podController);
```

### Fix 3: Remove the insufficient Duration.zero delay

The `await Future<void>.delayed(Duration.zero)` hack should be removed entirely, replaced by proper awaiting of chunk loading.

---

## Secondary Concern: Dual Body Creation

**File:** `lib/entities/pod/pod.dart` lines 54-87 and `lib/physics/pod_body.dart` lines 29-65

The `Pod` class extends `BodyComponent` and has its own `createBody()`. It also creates a `PodBody` instance (another `BodyComponent`) inside its `createBody()`:

```dart
@override
Body createBody() {
  podBody = PodBody(game: _game);  // Creates PodBody but never adds it to world!
  // ... creates its own body ...
}
```

The `PodBody` is instantiated but **never added to the Flame world**. Its `createBody()` is never called. The `Pod.createBody()` creates its own body directly. So `PodBody` is used only as a data holder for `isGrounded` tracking. But since `PodBody` extends `BodyComponent` and has `ContactCallbacks`, those callbacks will **never fire** because the PodBody is not mounted in the world.

This means `podBody.isGrounded` will **always be false**, which affects `_updateState()` in Pod (lines 131, 141). The pod will never enter `PodState.drilling` or `PodState.grounded` states.

**Fix:** Either:
1. Add PodBody to the world and remove Pod's createBody, or
2. Move the ContactCallbacks mixin to Pod itself and remove PodBody entirely, or
3. Add ContactCallbacks to Pod and wire up ground detection there

---

## Summary of Root Causes (Priority Order)

1. **Race condition**: Chunks' `createBody()` not guaranteed to execute before pod's `createBody()` due to non-awaited `world.add()` calls
2. **PodBody never mounted**: Ground detection callbacks never fire, `isGrounded` always false
3. **Possible**: Coordinate/scale issues in collision geometry (needs runtime verification)
