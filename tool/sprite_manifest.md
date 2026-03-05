# Sprite Manifest - Pod Overhaul

## Directory Structure After Generation

```
assets/images/
├── pod/
│   ├── hull_basic/
│   │   ├── base.png          # Reference frame
│   │   ├── idle_0..3.png     # 4-frame idle animation
│   │   ├── thrust_0..3.png   # 4-frame thrust animation
│   │   └── damage_0..3.png   # 4-frame damage animation
│   ├── hull_reinforced/      # Same structure
│   ├── hull_armored/
│   ├── hull_titanium/
│   ├── hull_quantum/
│   └── hull_legendary/
├── drills/
│   ├── drill_basic/
│   │   ├── base.png          # Reference/idle frame
│   │   └── spin_0..3.png     # 4-frame drilling animation
│   ├── drill_silver/         # Same structure
│   ├── drill_gold/
│   ├── drill_emerald/
│   ├── drill_magma/
│   └── drill_diamond/
```

## API Calls Per Tier (7 calls)

| # | Endpoint | Purpose | Size | Frames |
|---|----------|---------|------|--------|
| 1 | generate-image-pixflux | Base hull | 64×64 | 1 |
| 2 | animate-with-text | Hull idle | 64×64 | 4 |
| 3 | animate-with-text | Hull thrust | 64×64 | 4 |
| 4 | animate-with-text | Hull damage | 64×64 | 4 |
| 5 | generate-image-pixflux | Base drill | 32×64 | 1 |
| 6 | animate-with-text | Drill spin | 64×64 | 4 |

**Total: 6 tiers × 7 calls = 42 API calls**
**Estimated cost: ~42 × $0.01-0.03 = $0.50-1.50**

## Animation Frame Rates

| State | Frames | FPS | Loop |
|-------|--------|-----|------|
| Idle | 4 | 4 | ping-pong |
| Thrust | 4 | 8 | loop |
| Drilling | 4 | 10 | loop |
| Damage | 4 | 12 | play-once |

## Tier Visual Identity

| Tier | Hull Style | Drill Style | Accent Color |
|------|-----------|-------------|-------------|
| 0 Basic | Rusty green metal | Gray steel | #4A6741 |
| 1 Reinforced | Silver riveted plates | Chrome silver | #A8A8B8 |
| 2 Armored | Orange industrial | Gold plated | #D4890A |
| 3 Titanium | Blue-tinted sleek | Emerald crystal | #4488CC |
| 4 Quantum | Red magma core glow | Molten orange | #FF4400 |
| 5 Legendary | Golden diamond | Prismatic crystal | #FFD700 |

## Usage in generate_sprites.sh

```bash
# Generate all tiers:
bash tool/generate_sprites.sh

# Generate only tier 0 (for testing):
bash tool/generate_sprites.sh 0
```
