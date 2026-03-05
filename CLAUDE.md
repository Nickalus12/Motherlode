# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Motherlode is a physics-driven procedural mining game built with **Flutter** and **Flame/Forge2D**. The player pilots a mining pod underground, collecting ores and upgrading their rig. Inspired by the classic Motherload (XGen Studios, 2004).

## Build & Run Commands

```bash
flutter pub get          # Install dependencies
flutter run              # Run on connected device/emulator
flutter build apk --release  # Build release APK
flutter test             # Run all tests
flutter test test/world/chunk_test.dart  # Run a single test file
flutter analyze          # Static analysis (uses flutter_lints)
```

## Architecture

### Game Engine Stack
- **Forge2DGame** (physics-enabled Flame game) is the root class (`MotherlodeGame`)
- Physics uses Forge2D (Box2D port) with meters-based coordinates; `pixelsPerMeter = 24.0`
- State management: Flutter Riverpod (via `flame_riverpod`)
- Persistence: Hive (local storage)

### Core Loop (MotherlodeGame.onLoad)
1. `WorldGenerator` creates procedural terrain via multi-octave Simplex noise + cellular automata
2. `ChunkManager` streams chunks in/out based on pod position (load radius 3, unload radius 5)
3. `Pod` (BodyComponent) is the player entity with physics body, drill system, cargo system
4. Camera follows the pod; viewport overlays handle lighting, fog, and perf monitoring

### Key Subsystems

| System | Role |
|--------|------|
| `WorldGenerator` | Procedural terrain: noise density -> threshold -> cellular automata -> biome classification -> ore/cave placement |
| `ChunkManager` | Chunk lifecycle keyed by `"chunkX,chunkY"` strings; caches unloaded chunk data for fast reload |
| `Pod` + `PodController` | Player entity; `PodBody` handles physics, `DrillSystem` handles mining, `CargoSystem` tracks collected ores |
| `TerrainRenderer` | Renders terrain using marching squares visual mesh |
| `Chunk` | Individual chunk as a BodyComponent with Forge2D collision geometry |

### Coordinate Systems
- **World tiles**: integer grid, 1 tile = 1 Forge2D meter in the world
- **Chunk coords**: `chunkX/Y = floor(tilePos / chunkSize)` where `chunkSize = 32`
- **Depth in feet**: `tileY * feetPerTile` (15 ft per tile), max depth 7500 ft
- **Biome layers**: Sand (0-200ft) -> Topsoil (200-1000ft) -> Rock (1000-3000ft) -> Volcanic (3000-5000ft) -> Hell (5000ft+)

### Entity Pattern
All game entities extend Flame's `Component` or Forge2D's `BodyComponent`. Systems are added as children of the game world or camera viewport. The `MotherlodeGame` class holds references to all major systems and player state (cash, upgrade levels, inventory counts).

### Rendering Architecture
- `TerrainRenderer` and `ParallaxBackground` are world-space components
- `LightingSystem`, `DepthFog`, `PerfMonitor` are camera viewport overlays
- `PodRenderer` is a child of the `Pod` component
- UI overlays (`HudOverlay`, `ShopOverlay`, `UpgradeTree`) are Flutter widgets stacked on top of `GameWidget`

## Important Constants

All game-balance constants live in `lib/utils/constants.dart` (`GameConstants` class). When tuning gameplay, modify values there rather than hardcoding in subsystems.

## Testing

Tests are in `test/` mirroring the `lib/` structure. Tests cover chunk generation, world generation, terrain rendering, particle pooling, and debris physics. No integration or widget tests for UI overlays yet.
