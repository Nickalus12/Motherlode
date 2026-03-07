# Motherlode

A physics-driven procedural mining game built with Flutter and the Flame game engine. Inspired by the classic **Motherload** (XGen Studios, 2004), reimagined with modern procedural generation, real-time physics, GPU shaders, and a deep upgrade system.

**Dig deeper. Mine richer. Survive longer.**

## Screenshots

*Coming soon*

## Features

- **SDF-Based World Generation** — 9-phase Genesis pipeline using signed distance fields, stratigraphy with 9 geological layers, hydraulic erosion (6 parallel isolates), and reaction-diffusion ore patterns
- **Real-Time Physics** — Forge2D rigid body simulation with SDF-native terrain collision for smooth, sub-cell response
- **GPU Fragment Shaders** — Dual rendering pipeline (GPU primary, CPU fallback) for terrain texturing, dynamic lighting, fog of war, and procedural backgrounds
- **Humanoid Robot Character** — Frame-based sprite animations (idle, drill, fly, walk, death, hover, pickup) with physics-aligned rendering
- **Chunk Streaming** — Dynamic chunk loading/unloading with LRU caching, throttled rebuilds, and pre-computed boundary checks
- **6-Tier Upgrade System** — Drill, hull, engine, fuel tank, radiator, and cargo bay upgrades with visual progression
- **Consumable Items** — Dynamite, plastic explosives, reserve fuel, nanobots, teleporters, and transmitters
- **Creature Encounters** — Cave worms, rock crabs, gas spores, lava eels, and the Natas boss lurking in the deep
- **Dynamic Lighting & Fog of War** — 3-zone fog system (bright core, gradual mid falloff, dim ambient outer) with self-illuminating materials and volumetric headlight scattering
- **Particle Effects** — Object-pooled particles for drill sparks, exhaust, debris, ore sparkles, and ambient cave dust
- **Parallax Cave Backgrounds** — 4-layer parallax silhouettes with biome-specific color palettes, water drips, volcanic effects, and hellfire columns
- **Depth Biome Zones** — Sand (0-200ft), Topsoil (200-1000ft), Rock (1000-3000ft), Volcanic (3000-5000ft), Hell (5000ft+)
- **Mobile Touch Controls** — Analog joystick with dead zone detection for precise movement and drilling
- **Save/Load System** — Hive-based persistence with multiple save slots
- **Cinematic Genesis Screen** — Animated world generation loading screen with particle systems and narrative text

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.x |
| Game Engine | Flame 1.18+ |
| Physics | Forge2D (flame_forge2d 0.19) |
| Terrain | SDF fields + marching squares (2x subdivided) |
| Shaders | Flutter FragmentProgram (GLSL ES) |
| World Gen | Simplex noise, cellular automata, Gray-Scott R-D, hydraulic erosion |
| Persistence | Hive |
| State | Riverpod |
| Audio | flame_audio |

## Architecture

```
lib/
  motherlode_game.dart        # Root Forge2DGame class
  main.dart                   # App entry point + navigation
  entities/
    pod/                      # Player pod, controller, drill, cargo systems
    creatures/                # Cave worm, rock crab, gas spore, lava eel, natas boss
  world/
    genesis_pipeline.dart     # 9-phase SDF world generator orchestrator
    stratigraphy.dart         # 9 geological layers with fault lines
    hydraulic_erosion.dart    # Parallel isolate erosion simulation
    reaction_diffusion.dart   # Gray-Scott model for ore patterns
    world_generator.dart      # Legacy procedural terrain (fallback)
    chunk_manager.dart        # Chunk streaming, SDF drilling, LRU cache
    chunk.dart                # Individual chunk (BodyComponent + collision)
    marching_squares.dart     # 2x subdivided terrain mesh generation
    sdf_primitives.dart       # SDF shapes and boolean operations
    ore_registry.dart         # Ore type definitions and distribution
    terrain_cell.dart         # Per-cell SDF + material data
  rendering/
    shader_terrain_renderer.dart  # GPU terrain shader renderer
    shader_background.dart        # GPU background shader renderer
    terrain_renderer.dart         # CPU fallback terrain renderer
    pod_renderer.dart             # Frame-based robot sprite animations
    parallax_background.dart      # CPU fallback parallax background
    lighting_system.dart          # Viewport lighting overlay
    particle_system.dart          # Object-pooled particle effects
    particle_pool.dart            # Zero-allocation particle pool
    sdf_texture.dart              # SDF chunk texture encoding/cache
    item_sprite_manager.dart      # Ore/item sprite management
  physics/
    sdf_collision.dart        # SDF-native terrain collision system
    pod_body.dart             # Pod physics body + fixtures
    debris_body.dart          # Debris particle physics
    explosion_system.dart     # Explosive item physics
  systems/
    depth_system.dart         # Depth tracking + biome transitions
    fuel_system.dart          # Fuel consumption + refueling
    hull_system.dart          # Hull damage + repair
    earthquake_system.dart    # Seismic event generation
  ui/
    genesis_screen.dart       # Cinematic world generation screen
    main_menu.dart            # Title screen with animated particles
    hud.dart                  # In-game HUD (fuel, hull, depth, cash)
    shop_overlay.dart         # Surface shop (upgrades, fuel, repairs)
    upgrade_tree.dart         # Upgrade tier visualization
    inventory_panel.dart      # Consumable item management
    death_screen.dart         # Game over screen
  data/
    special_items.dart        # Consumable item definitions
  utils/
    constants.dart            # Game constants (physics, sizes, balancing)
    math_utils.dart           # Math helpers
    color_utils.dart          # Color manipulation
    perf_monitor.dart         # FPS and performance overlay
shaders/
  terrain.frag               # GPU terrain: SDF rendering, lighting, fog of war
  background.frag            # GPU background: sky, caves, particles, effects
```

## Getting Started

### Prerequisites

- Flutter SDK 3.x+
- Android SDK (for mobile builds)
- A device or emulator

### Build & Run

```bash
# Clone the repo
git clone https://github.com/Nickalus12/Motherlode.git
cd Motherlode

# Get dependencies
flutter pub get

# Run on connected device
flutter run

# Build release APK
flutter build apk --release

# Run tests
flutter test

# Static analysis
flutter analyze
```

## Contributing

Contributions are welcome! This is an open-source project and we'd love your help making Motherlode even better.

### How to Contribute

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/awesome-feature`)
3. **Commit** your changes (`git commit -m 'feat: add awesome feature'`)
4. **Push** to the branch (`git push origin feature/awesome-feature`)
5. **Open** a Pull Request

### Ideas for Contributions

- New ore types and biomes
- Additional creatures and boss encounters
- Sound effects and music
- New upgrade tiers or consumable items
- UI/UX improvements
- Performance optimizations
- iOS support and testing
- Desktop (Windows/macOS/Linux) support

## Inspiration

This game is a love letter to **Motherload** by XGen Studios (2004) — the classic Flash mining game where you pilot a drilling pod deep underground, collecting minerals and upgrading your rig. Motherlode reimagines that experience with modern procedural generation, physics simulation, GPU shaders, and mobile-first design.

## License

This project is open source. See [LICENSE](LICENSE) for details.

---

*Built with Flutter, Flame, and a whole lot of digging.*
