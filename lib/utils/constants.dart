import 'dart:ui';

/// Core game constants for Hellbore
class GameConstants {
  GameConstants._();

  // World dimensions
  static const double tileSize = 64.0;
  static const int chunkSize = 32;
  static const double chunkPixelSize = tileSize * chunkSize;

  // Physics (Forge2D uses meters, 1 meter = tileSize pixels)
  static const double pixelsPerMeter = 10.0;
  static const double gravity = 9.8;
  static const double podBaseMass = 500.0;
  static const double podLinearDamping = 0.8;
  static const double podAngularDamping = 5.0;

  // Depth system (in feet)
  static const double maxDepth = 7500.0;
  static const double surfaceDepth = 0.0;
  static const double sandLayerEnd = 200.0;
  static const double topsoilEnd = 1000.0;
  static const double rockEnd = 3000.0;
  static const double volcanicEnd = 5000.0;
  static const double hellStart = 5000.0;
  static const double bossDepth = 7187.0;
  static const double feetPerTile = 15.0;

  // Chunk loading
  static const int chunkLoadRadius = 3;
  static const int chunkUnloadRadius = 5;

  // Rendering
  static const double podLightBaseRadius = 180.0;
  static const double podLightPerLevel = 10.0;
  static const double maxDarknessOpacity = 0.92;
  static const double terrainStrokeWidth = 2.0;

  // Drilling
  static const double baseDrillSpeed = 50.0; // ft/s
  static const double drillParticleCount = 10.0;

  // Fuel
  static const double baseFuelCapacity = 10.0; // liters
  static const double fuelCostPerLiter = 10.0;
  static const double fuelConsumptionIdle = 0.01;
  static const double fuelConsumptionThrust = 0.05;
  static const double fuelConsumptionDrill = 0.03;
  static const double lowFuelThreshold = 0.15;
  static const double reducedThrustThreshold = 0.20;

  // Hull
  static const double baseHullHP = 10.0;
  static const double lowHullThreshold = 0.20;
  static const double lavaDamagePerSecond = 5.0;
  static const double gasDamagePerSecond = 2.0;

  // Cargo
  static const double baseCargoCapacity = 50.0; // kg

  // Explosions
  static const int dynamiteRadius = 3;
  static const int plasticExplosiveRadius = 5;
  static const double dynamiteForce = 5000.0;
  static const double plasticExplosiveForce = 10000.0;
  static const double dynamiteCameraTrauma = 0.8;
  static const double plasticCameraTrauma = 1.0;

  // Collapse
  static const int collapseCheckRadius = 5;
  static const int collapseMinSupportNeighbors = 3;
  static const double debrisSettleTime = 3.0;
  static const double debrisDamageMultiplier = 0.1;

  // Creatures
  static const double creatureChaseRange = 200.0;
  static const double gasSporeChainRadius = 3.0;

  // Biome colors
  static const Color surfaceTerrainColor = Color(0xFF8B6914);
  static const Color surfaceAccentColor = Color(0xFFA0784A);
  static const Color shallowTerrainColor = Color(0xFF5A3A1A);
  static const Color shallowAccentColor = Color(0xFF3D2810);
  static const Color deepTerrainColor = Color(0xFF2A1A0A);
  static const Color deepAccentColor = Color(0xFF1A0D05);
  static const Color volcanicTerrainColor = Color(0xFF3A0A0A);
  static const Color volcanicAccentColor = Color(0xFFFF3300);
  static const Color hellTerrainColor = Color(0xFF1A0000);
  static const Color hellAccentColor = Color(0xFFFF0000);

  // Ambient light levels by depth
  static const double surfaceAmbientLight = 1.0;
  static const double shallowAmbientLight = 0.8;
  static const double deepAmbientLight = 0.5;
  static const double volcanicAmbientLight = 0.25;
  static const double hellAmbientLight = 0.1;

  // Particle system
  static const int drillParticlesMin = 8;
  static const int drillParticlesMax = 12;
  static const int oreSparkleParticles = 16;
  static const int explosionParticlesMin = 40;
  static const int explosionParticlesMax = 80;
  static const int lavaSplashParticles = 20;
  static const int caveDustParticlesMin = 30;
  static const int caveDustParticlesMax = 50;

  // Economy
  static const double startingCash = 0.0;
  static const double reserveFuelAmount = 25.0;
  static const double nanobotHealAmount = 30.0;
}
