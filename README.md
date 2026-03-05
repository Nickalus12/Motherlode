# Motherlode

A physics-driven procedural mining game built with Flutter and the Flame game engine. Inspired by the classic **Motherload** (XGen Studios, 2004), reimagined with modern procedural generation, real-time physics, and a deep upgrade system.

**Dig deeper. Mine richer. Survive longer.**

## Screenshots

*Coming soon*

## Features

- **Procedural World Generation** - Infinite depth with biome transitions (sand, rock, crystal, magma, void), Perlin noise terrain, and seeded randomness for consistent worlds
- **Real-Time Physics** - Forge2D-powered rigid body simulation with terrain collision via marching squares
- **Chunk Streaming** - Dynamic chunk loading/unloading based on player position for unlimited world size
- **6-Tier Upgrade System** - Drill, hull, engine, fuel tank, radiator, and cargo bay upgrades with visual progression
- **Consumable Items** - Dynamite, plastic explosives, reserve fuel, nanobots, teleporters, and transmitters
- **Creature Encounters** - Cave worms, rock crabs, gas spores, lava eels, and the Natas boss lurking in the deep
- **Dynamic Lighting & Fog** - Depth-based fog and lighting that intensifies as you descend
- **Particle Effects** - Drill sparks, exhaust flames, debris, and ambient particles
- **Earthquake System** - Environmental hazards that increase with depth
- **Parallax Backgrounds** - Multi-layer scrolling backgrounds for visual depth
- **Pixel Art Sprites** - Custom hull, drill tier, building, and background artwork
- **Mobile Touch Controls** - Drag-based input with zone detection for movement and drilling
- **Save/Load System** - Hive-based persistence with multiple save slots
- **Leaderboard** - Track your deepest dives and highest scores

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.x |
| Game Engine | Flame 1.18+ |
| Physics | Forge2D (flame_forge2d 0.19) |
| Terrain | Perlin noise (fast_noise) + marching squares collision |
| Persistence | Hive |
| State | Riverpod |
| Audio | flame_audio |

## Architecture

```
lib/
  motherlode_game.dart        # Root Forge2DGame class
  main.dart                   # App entry point + navigation
  entities/
    pod/                      # Player pod, controller, drill, cargo
    creatures/                # Cave worm, rock crab, gas spore, lava eel, natas boss
  world/
    world_generator.dart      # Procedural terrain generation (biomes, ores, caves)
    chunk_manager.dart        # Chunk streaming + lifecycle
    chunk.dart                # Individual chunk (BodyComponent + collision)
    marching_squares.dart     # Terrain collision mesh generation
    ore_registry.dart         # Ore type definitions and distribution
    biome.dart                # Biome configuration per depth
  rendering/
    terrain_renderer.dart     # Marching squares visual mesh
    pod_renderer.dart         # Pod sprite + procedural effects
    parallax_background.dart  # Multi-layer scrolling background
    lighting_system.dart      # Depth-based lighting overlay
    depth_fog.dart            # Progressive fog effect
    particle_system.dart      # Particle effects (sparks, flames, debris)
  physics/
    pod_body.dart             # Pod physics body + fixtures
    terrain_body.dart         # Terrain collision body
    debris_body.dart          # Debris particle physics
    collapse_detector.dart    # Cave collapse detection
    explosion_system.dart     # Explosive item physics
  systems/
    depth_system.dart         # Depth tracking + biome transitions
    fuel_system.dart          # Fuel consumption + refueling
    hull_system.dart          # Hull damage + repair
    drilling_system.dart      # Drill mechanics + ore extraction
    earthquake_system.dart    # Seismic event generation
  ui/
    main_menu.dart            # Title screen with animated particles
    hud.dart                  # In-game HUD (fuel, hull, depth, cash)
    shop_overlay.dart         # Surface shop (upgrades, fuel, repairs)
    upgrade_tree.dart         # Upgrade tier visualization
    inventory_panel.dart      # Consumable item management
    death_screen.dart         # Game over screen
  data/
    ore_types.dart            # Ore value/rarity definitions
    upgrade_definitions.dart  # Upgrade costs and stats
    creature_definitions.dart # Creature stats and behavior
    special_items.dart        # Consumable item definitions
  persistence/
    save_manager.dart         # Save/load with Hive
    game_state.dart           # Serializable game state
    leaderboard.dart          # High score tracking
  utils/
    constants.dart            # Game constants (physics, sizes, balancing)
    math_utils.dart           # Math helpers
    color_utils.dart          # Color manipulation
    noise_utils.dart          # Noise generation utilities
    perf_monitor.dart         # FPS and performance overlay
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

This game is a love letter to **Motherload** by XGen Studios (2004) - the classic Flash mining game where you pilot a drilling pod deep underground, collecting minerals and upgrading your rig. Motherlode reimagines that experience with modern procedural generation, physics simulation, and mobile-first design.

## License

This project is open source. See [LICENSE](LICENSE) for details.

---

*Built with Flutter, Flame, and a whole lot of digging.*
