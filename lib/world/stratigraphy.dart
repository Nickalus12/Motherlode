import 'dart:math';
import 'dart:ui';

import 'package:motherlode/utils/noise_utils.dart';
import 'package:motherlode/world/ore_registry.dart';
import 'package:motherlode/world/terrain_cell.dart';

// ---------------------------------------------------------------------------
// Part 1: Geological strata (world-scale layer classification)
// ---------------------------------------------------------------------------

/// Geological layer types ordered by increasing depth.
enum StratumType {
  topsoil,      // 0-200ft    — loose, sandy, easy drilling
  sandstone,    // 100-400ft  — compressed sand
  limestone,    // 300-800ft  — calcium-rich, fossils
  shale,        // 600-1200ft — layered, oil-bearing
  granite,      // 1000-2500ft — hard igneous
  basalt,       // 2000-4000ft — volcanic, dense
  obsidianFlow, // 3500-5500ft — volcanic glass
  mantleRock,   // 5000-7000ft — extreme pressure
  hellstone,    // 6500-7500ft — supernatural
}

/// A geological fault line that vertically displaces strata.
class FaultLine {
  final double worldX;
  final double displacement;
  final double width;

  const FaultLine({
    required this.worldX,
    required this.displacement,
    required this.width,
  });
}

/// Definition of a single geological stratum (world-scale layer).
class Stratum {
  final StratumType type;
  final double baseDepth;
  final double thickness;
  final double hardness;
  final double porosity;
  final CellType cellType;
  final Color primaryColor;
  final List<OreType> nativeOres;
  final double foldAmplitude;
  final double foldFrequency;

  /// Base temperature at the top of this stratum (Celsius).
  final double baseTemperature;

  /// Temperature gradient within this stratum (C per foot of depth).
  final double temperatureGradient;

  /// Erosion rate multiplier for hydraulic simulation.
  final double erosionRate;

  /// Default bedrock material for cells in this stratum.
  final MaterialType bedrockMaterial;

  /// Default sediment material (nullable — deep layers have none).
  final MaterialType? sedimentMaterial;

  const Stratum({
    required this.type,
    required this.baseDepth,
    required this.thickness,
    required this.hardness,
    required this.porosity,
    required this.cellType,
    required this.primaryColor,
    required this.nativeOres,
    required this.foldAmplitude,
    required this.foldFrequency,
    required this.baseTemperature,
    required this.temperatureGradient,
    required this.erosionRate,
    required this.bedrockMaterial,
    this.sedimentMaterial,
  });
}

// ---------------------------------------------------------------------------
// Part 2: Per-cell multi-layer model (bedrock / sediment / fluid / void)
// ---------------------------------------------------------------------------

/// Material types that can occupy bedrock or sediment layers.
enum MaterialType {
  // Surface (0-500ft)
  topsoil,
  clay,
  sandstone,
  // Mid (500-2000ft)
  limestone,
  granite,
  basalt,
  // Deep (2000-5000ft)
  obsidian,
  magma,
  // Abyss (5000ft+)
  crystalline,
  hellrock,
}

/// Fluid types that can occupy the fluid layer of a cell.
enum FluidType {
  none,
  water,
  oil,
  lava,
  gas,
}

/// Physical properties for a material, used by simulation systems.
class MaterialProperties {
  final double hardness;
  final double density;
  final double erosionResistance;
  final double thermalConductivity;

  /// Temperature at which this material transforms (0 = no transform).
  final double transformTemperature;

  /// What this material becomes when heated past transformTemperature.
  final MaterialType? heatedProduct;

  const MaterialProperties({
    required this.hardness,
    required this.density,
    required this.erosionResistance,
    required this.thermalConductivity,
    this.transformTemperature = 0,
    this.heatedProduct,
  });
}

/// Static lookup of physical properties per material type.
class MaterialRegistry {
  MaterialRegistry._();

  static const Map<MaterialType, MaterialProperties> properties = {
    MaterialType.topsoil: MaterialProperties(
      hardness: 0.3,
      density: 1.2,
      erosionResistance: 0.15,
      thermalConductivity: 0.3,
    ),
    MaterialType.clay: MaterialProperties(
      hardness: 0.5,
      density: 1.6,
      erosionResistance: 0.25,
      thermalConductivity: 0.4,
      transformTemperature: 900,
      heatedProduct: MaterialType.sandstone,
    ),
    MaterialType.sandstone: MaterialProperties(
      hardness: 0.8,
      density: 2.0,
      erosionResistance: 0.35,
      thermalConductivity: 0.5,
    ),
    MaterialType.limestone: MaterialProperties(
      hardness: 1.2,
      density: 2.3,
      erosionResistance: 0.30,
      thermalConductivity: 0.6,
    ),
    MaterialType.granite: MaterialProperties(
      hardness: 2.5,
      density: 2.7,
      erosionResistance: 0.80,
      thermalConductivity: 0.8,
    ),
    MaterialType.basalt: MaterialProperties(
      hardness: 3.0,
      density: 2.9,
      erosionResistance: 0.85,
      thermalConductivity: 0.9,
      transformTemperature: 1200,
      heatedProduct: MaterialType.magma,
    ),
    MaterialType.obsidian: MaterialProperties(
      hardness: 4.5,
      density: 2.4,
      erosionResistance: 0.90,
      thermalConductivity: 0.7,
    ),
    MaterialType.magma: MaterialProperties(
      hardness: 0.1,
      density: 2.8,
      erosionResistance: 0.0,
      thermalConductivity: 1.5,
    ),
    MaterialType.crystalline: MaterialProperties(
      hardness: 6.0,
      density: 3.2,
      erosionResistance: 0.95,
      thermalConductivity: 1.2,
    ),
    MaterialType.hellrock: MaterialProperties(
      hardness: 8.0,
      density: 3.5,
      erosionResistance: 0.98,
      thermalConductivity: 1.8,
    ),
  };

  static MaterialProperties get(MaterialType type) => properties[type]!;
}

/// The four sub-layers within a single terrain cell.
///
/// Each cell is composed of up to four layers stacked vertically:
///   bedrock  — the solid rock foundation
///   sediment — loose material on top of bedrock (eroded deposits, soil)
///   fluid    — liquid or gas filling void space
///   void     — empty space (fraction of cell that is open air/cave)
///
/// Layer fractions always sum to 1.0.
class CellLayers {
  // -- Bedrock layer --
  MaterialType bedrockMaterial;
  double bedrockFraction;
  double bedrockHardness;

  // -- Sediment layer --
  MaterialType? sedimentMaterial;
  double sedimentFraction;
  double sedimentDensity;

  // -- Fluid layer --
  FluidType fluidType;
  double fluidFraction;

  // -- Void layer --
  double voidFraction;

  // -- Thermal state --
  double temperature;

  CellLayers({
    required this.bedrockMaterial,
    this.bedrockFraction = 0.9,
    this.bedrockHardness = 1.0,
    this.sedimentMaterial,
    this.sedimentFraction = 0.0,
    this.sedimentDensity = 0.0,
    this.fluidType = FluidType.none,
    this.fluidFraction = 0.0,
    this.voidFraction = 0.1,
    this.temperature = 20.0,
  });

  /// Whether this cell is effectively solid (bedrock + sediment > 50%).
  bool get isSolid => (bedrockFraction + sedimentFraction) > 0.5;

  /// Effective hardness accounting for sediment softening.
  double get effectiveHardness {
    if (sedimentFraction <= 0) return bedrockHardness;
    final sedProps = sedimentMaterial != null
        ? MaterialRegistry.get(sedimentMaterial!)
        : null;
    final sedHardness = sedProps?.hardness ?? 0.0;
    final solidTotal = bedrockFraction + sedimentFraction;
    if (solidTotal <= 0) return 0.0;
    return (bedrockHardness * bedrockFraction +
            sedHardness * sedimentFraction) /
        solidTotal;
  }

  /// Effective erosion resistance (0-1). Lower = erodes faster.
  double get erosionResistance {
    final bedProps = MaterialRegistry.get(bedrockMaterial);
    if (sedimentFraction <= 0) return bedProps.erosionResistance;
    final sedProps = sedimentMaterial != null
        ? MaterialRegistry.get(sedimentMaterial!)
        : null;
    final sedResist = sedProps?.erosionResistance ?? 0.0;
    final solidTotal = bedrockFraction + sedimentFraction;
    if (solidTotal <= 0) return 0.0;
    return (bedProps.erosionResistance * bedrockFraction +
            sedResist * sedimentFraction) /
        solidTotal;
  }

  /// Apply erosion: removes sediment first, then bedrock.
  /// Returns the amount of material actually eroded.
  double erode(double amount) {
    double eroded = 0.0;

    // Erode sediment first (softer)
    if (sedimentFraction > 0 && amount > 0) {
      final sedErode = min(amount, sedimentFraction);
      sedimentFraction -= sedErode;
      voidFraction += sedErode;
      eroded += sedErode;
      amount -= sedErode;
    }

    // Then erode bedrock (harder, reduced by resistance)
    if (bedrockFraction > 0 && amount > 0) {
      final bedProps = MaterialRegistry.get(bedrockMaterial);
      final effective = amount * (1.0 - bedProps.erosionResistance);
      final bedErode = min(effective, bedrockFraction);
      bedrockFraction -= bedErode;
      voidFraction += bedErode;
      eroded += bedErode;
    }

    return eroded;
  }

  /// Deposit sediment into the cell (fills void space).
  void deposit(double amount, MaterialType material) {
    final deposited = min(amount, voidFraction);
    if (deposited <= 0) return;
    sedimentMaterial = material;
    sedimentFraction += deposited;
    voidFraction -= deposited;
  }

  /// Apply thermal transformation if temperature exceeds threshold.
  /// Returns true if a transformation occurred.
  bool applyHeatTransform() {
    final bedProps = MaterialRegistry.get(bedrockMaterial);
    if (bedProps.transformTemperature > 0 &&
        temperature >= bedProps.transformTemperature &&
        bedProps.heatedProduct != null) {
      bedrockMaterial = bedProps.heatedProduct!;
      bedrockHardness = MaterialRegistry.get(bedrockMaterial).hardness;
      return true;
    }

    if (sedimentMaterial != null) {
      final sedProps = MaterialRegistry.get(sedimentMaterial!);
      if (sedProps.transformTemperature > 0 &&
          temperature >= sedProps.transformTemperature &&
          sedProps.heatedProduct != null) {
        sedimentMaterial = sedProps.heatedProduct!;
        return true;
      }
    }

    return false;
  }

  /// Fill fluid into void space.
  void fillFluid(FluidType type, double amount) {
    if (type == FluidType.none) return;
    final filled = min(amount, voidFraction);
    if (filled <= 0) return;
    fluidType = type;
    fluidFraction += filled;
    voidFraction -= filled;
  }

  /// Normalize fractions to sum to 1.0.
  void normalize() {
    final total =
        bedrockFraction + sedimentFraction + fluidFraction + voidFraction;
    if (total <= 0) {
      voidFraction = 1.0;
      return;
    }
    bedrockFraction /= total;
    sedimentFraction /= total;
    fluidFraction /= total;
    voidFraction /= total;
  }
}

// ---------------------------------------------------------------------------
// Part 3: Stratigraphy system (world-scale + per-cell generation)
// ---------------------------------------------------------------------------

/// The geological stratigraphy system.
///
/// Provides:
/// 1. Noise-folded layer boundaries and fault-line displacements to classify
///    which stratum exists at any (worldX, depthFeet) position.
/// 2. Per-cell multi-layer generation (bedrock/sediment/fluid/void) based on
///    the stratum at that position plus local noise variation.
class Stratigraphy {
  final int seed;

  late final List<FaultLine> _faults;

  static const List<Stratum> strata = [
    Stratum(
      type: StratumType.topsoil,
      baseDepth: 0,
      thickness: 200,
      hardness: 0.5,
      porosity: 0.8,
      cellType: CellType.sand,
      primaryColor: Color(0xFFD4A96A),
      nativeOres: [OreRegistry.ironium, OreRegistry.bronzium],
      foldAmplitude: 20,
      foldFrequency: 0.006,
      baseTemperature: 15.0,
      temperatureGradient: 0.02,
      erosionRate: 1.0,
      bedrockMaterial: MaterialType.sandstone,
      sedimentMaterial: MaterialType.topsoil,
    ),
    Stratum(
      type: StratumType.sandstone,
      baseDepth: 100,
      thickness: 300,
      hardness: 0.8,
      porosity: 0.6,
      cellType: CellType.sand,
      primaryColor: Color(0xFFC4943A),
      nativeOres: [
        OreRegistry.ironium,
        OreRegistry.bronzium,
        OreRegistry.silverium,
      ],
      foldAmplitude: 40,
      foldFrequency: 0.005,
      baseTemperature: 20.0,
      temperatureGradient: 0.025,
      erosionRate: 0.8,
      bedrockMaterial: MaterialType.sandstone,
      sedimentMaterial: MaterialType.clay,
    ),
    Stratum(
      type: StratumType.limestone,
      baseDepth: 300,
      thickness: 500,
      hardness: 1.2,
      porosity: 0.5,
      cellType: CellType.dirt,
      primaryColor: Color(0xFF9E8E6E),
      nativeOres: [OreRegistry.silverium, OreRegistry.goldium],
      foldAmplitude: 60,
      foldFrequency: 0.005,
      baseTemperature: 30.0,
      temperatureGradient: 0.03,
      erosionRate: 0.7,
      bedrockMaterial: MaterialType.limestone,
      sedimentMaterial: MaterialType.clay,
    ),
    Stratum(
      type: StratumType.shale,
      baseDepth: 600,
      thickness: 600,
      hardness: 1.0,
      porosity: 0.3,
      cellType: CellType.dirt,
      primaryColor: Color(0xFF5A4A3A),
      nativeOres: [OreRegistry.goldium, OreRegistry.platinium],
      foldAmplitude: 50,
      foldFrequency: 0.004,
      baseTemperature: 45.0,
      temperatureGradient: 0.03,
      erosionRate: 0.6,
      bedrockMaterial: MaterialType.limestone,
      sedimentMaterial: MaterialType.clay,
    ),
    Stratum(
      type: StratumType.granite,
      baseDepth: 1000,
      thickness: 1500,
      hardness: 2.5,
      porosity: 0.15,
      cellType: CellType.rock,
      primaryColor: Color(0xFF6B6B6B),
      nativeOres: [
        OreRegistry.platinium,
        OreRegistry.einsteinium,
        OreRegistry.emerald,
      ],
      foldAmplitude: 80,
      foldFrequency: 0.004,
      baseTemperature: 60.0,
      temperatureGradient: 0.035,
      erosionRate: 0.3,
      bedrockMaterial: MaterialType.granite,
    ),
    Stratum(
      type: StratumType.basalt,
      baseDepth: 2000,
      thickness: 2000,
      hardness: 3.0,
      porosity: 0.1,
      cellType: CellType.rock,
      primaryColor: Color(0xFF3A3A3A),
      nativeOres: [
        OreRegistry.emerald,
        OreRegistry.ruby,
        OreRegistry.diamond,
      ],
      foldAmplitude: 100,
      foldFrequency: 0.003,
      baseTemperature: 100.0,
      temperatureGradient: 0.04,
      erosionRate: 0.2,
      bedrockMaterial: MaterialType.basalt,
    ),
    Stratum(
      type: StratumType.obsidianFlow,
      baseDepth: 3500,
      thickness: 2000,
      hardness: 4.5,
      porosity: 0.05,
      cellType: CellType.obsidian,
      primaryColor: Color(0xFF1A1A2E),
      nativeOres: [
        OreRegistry.ruby,
        OreRegistry.diamond,
        OreRegistry.amazonite,
      ],
      foldAmplitude: 120,
      foldFrequency: 0.003,
      baseTemperature: 200.0,
      temperatureGradient: 0.06,
      erosionRate: 0.1,
      bedrockMaterial: MaterialType.obsidian,
    ),
    Stratum(
      type: StratumType.mantleRock,
      baseDepth: 5000,
      thickness: 2000,
      hardness: 6.0,
      porosity: 0.02,
      cellType: CellType.obsidian,
      primaryColor: Color(0xFF2A0A0A),
      nativeOres: [OreRegistry.amazonite, OreRegistry.hellstone],
      foldAmplitude: 150,
      foldFrequency: 0.002,
      baseTemperature: 400.0,
      temperatureGradient: 0.08,
      erosionRate: 0.05,
      bedrockMaterial: MaterialType.crystalline,
    ),
    Stratum(
      type: StratumType.hellstone,
      baseDepth: 6500,
      thickness: 1000,
      hardness: 8.0,
      porosity: 0.01,
      cellType: CellType.obsidian,
      primaryColor: Color(0xFF1A0000),
      nativeOres: [OreRegistry.hellstone, OreRegistry.soulCrystal],
      foldAmplitude: 80,
      foldFrequency: 0.002,
      baseTemperature: 800.0,
      temperatureGradient: 0.12,
      erosionRate: 0.02,
      bedrockMaterial: MaterialType.hellrock,
    ),
  ];

  Stratigraphy({required this.seed}) {
    _faults = _generateFaults();
  }

  // -------------------------------------------------------------------------
  // Fault generation
  // -------------------------------------------------------------------------

  List<FaultLine> _generateFaults() {
    final rng = Random(seed ^ 0xFAE17);
    final count = 1 + rng.nextInt(3);
    final faults = <FaultLine>[];
    for (int i = 0; i < count; i++) {
      faults.add(FaultLine(
        worldX: (rng.nextDouble() * 600 - 300).roundToDouble(),
        displacement: 100.0 + rng.nextDouble() * 400.0,
        width: 20.0 + rng.nextDouble() * 60.0,
      ));
    }
    return faults;
  }

  List<FaultLine> get faults => List.unmodifiable(_faults);

  // -------------------------------------------------------------------------
  // Stratum boundary & lookup
  // -------------------------------------------------------------------------

  double getStratumBoundary(Stratum stratum, double worldX) {
    final base = stratum.baseDepth;
    final fold = NoiseUtils.sampleMultiOctave(
      seed: seed + stratum.type.index * 1000,
      x: worldX,
      y: 0.0,
      octaves: 3,
      frequency: stratum.foldFrequency,
      gain: 0.5,
    );
    final detail = NoiseUtils.sampleMultiOctave(
      seed: seed + stratum.type.index * 2000,
      x: worldX,
      y: 0.0,
      octaves: 2,
      frequency: 0.02,
      gain: 0.3,
    );
    return base +
        (fold - 0.5) * 2.0 * stratum.foldAmplitude +
        (detail - 0.5) * 2.0 * 30.0;
  }

  double _applyFaults(double depthFeet, double worldX) {
    double adjusted = depthFeet;
    for (final fault in _faults) {
      final dist = worldX - fault.worldX;
      if (dist.abs() < fault.width * 3) {
        final t = _smoothstep(0, fault.width, dist.abs());
        if (dist > 0) {
          adjusted -= fault.displacement * t;
        } else {
          adjusted += fault.displacement * t;
        }
      }
    }
    return adjusted;
  }

  static double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  /// Returns the [Stratum] at a given world position, accounting for
  /// noise-based layer folding and fault line displacements.
  Stratum getStratumAtPosition(double worldX, double depthFeet) {
    final faultAdjustedDepth = _applyFaults(depthFeet, worldX);
    for (int i = strata.length - 1; i >= 0; i--) {
      final stratum = strata[i];
      final boundary = getStratumBoundary(stratum, worldX);
      if (faultAdjustedDepth >= boundary) {
        return stratum;
      }
    }
    return strata.first;
  }

  // -------------------------------------------------------------------------
  // Temperature
  // -------------------------------------------------------------------------

  /// Get the temperature at a position in Celsius.
  /// Accounts for depth gradient and local magma noise hotspots.
  double getTemperatureAtPosition(double worldX, double depthFeet) {
    final stratum = getStratumAtPosition(worldX, depthFeet);
    final depthInStratum = depthFeet - stratum.baseDepth;
    final baseTemp =
        stratum.baseTemperature + depthInStratum * stratum.temperatureGradient;

    // Magma hotspot noise — localized heat sources in deep layers
    if (depthFeet > 2000) {
      final heatNoise = NoiseUtils.sampleMultiOctave(
        seed: seed + 7777,
        x: worldX,
        y: depthFeet,
        octaves: 2,
        frequency: 0.008,
        gain: 0.5,
      );
      if (heatNoise > 0.75) {
        // Hotspot: +200-600 C boost
        return baseTemp + (heatNoise - 0.75) * 4.0 * 600.0;
      }
    }

    return baseTemp;
  }

  // -------------------------------------------------------------------------
  // Per-cell layer generation
  // -------------------------------------------------------------------------

  /// Generate a [CellLayers] for a specific world position.
  ///
  /// The multi-layer breakdown is derived from the stratum at that position
  /// plus local noise for sediment coverage, fluid pockets, and void space.
  CellLayers generateCellLayers(double worldX, double depthFeet) {
    final stratum = getStratumAtPosition(worldX, depthFeet);
    final bedMat = stratum.bedrockMaterial;
    final bedProps = MaterialRegistry.get(bedMat);
    final temp = getTemperatureAtPosition(worldX, depthFeet);

    // Base bedrock fraction: high for hard strata, lower for porous ones
    final bedrockBase = 1.0 - stratum.porosity;

    // Sediment noise — loose material deposits
    double sedimentFraction = 0.0;
    MaterialType? sedMat = stratum.sedimentMaterial;
    if (sedMat != null) {
      final sedNoise = NoiseUtils.sampleMultiOctave(
        seed: seed + 8888,
        x: worldX,
        y: depthFeet,
        octaves: 2,
        frequency: 0.04,
        gain: 0.4,
      );
      sedimentFraction = sedNoise * stratum.porosity * 0.6;
    }

    // Fluid detection — water in shallow, oil in shale, lava in deep/hot
    FluidType fluidType = FluidType.none;
    double fluidFraction = 0.0;

    final fluidNoise = NoiseUtils.sampleMultiOctave(
      seed: seed + 9999,
      x: worldX,
      y: depthFeet,
      octaves: 2,
      frequency: 0.03,
      gain: 0.5,
    );

    if (fluidNoise > 0.7) {
      final pocket = fluidNoise - 0.7; // 0-0.3 range
      if (temp > 800) {
        fluidType = FluidType.lava;
        fluidFraction = pocket * 0.5;
      } else if (stratum.type == StratumType.shale && depthFeet > 600) {
        fluidType = FluidType.oil;
        fluidFraction = pocket * 0.4;
      } else if (depthFeet < 1500) {
        fluidType = FluidType.water;
        fluidFraction = pocket * 0.3;
      } else if (depthFeet > 2000) {
        fluidType = FluidType.gas;
        fluidFraction = pocket * 0.2;
      }
    }

    final bedrockFraction =
        (bedrockBase - sedimentFraction - fluidFraction).clamp(0.05, 1.0);
    final voidFraction =
        (1.0 - bedrockFraction - sedimentFraction - fluidFraction)
            .clamp(0.0, 1.0);

    final layers = CellLayers(
      bedrockMaterial: bedMat,
      bedrockFraction: bedrockFraction,
      bedrockHardness: bedProps.hardness,
      sedimentMaterial: sedMat,
      sedimentFraction: sedimentFraction,
      sedimentDensity:
          sedMat != null ? MaterialRegistry.get(sedMat).density : 0.0,
      fluidType: fluidType,
      fluidFraction: fluidFraction,
      voidFraction: voidFraction,
      temperature: temp,
    );

    layers.normalize();
    return layers;
  }

  // -------------------------------------------------------------------------
  // Color & convenience accessors
  // -------------------------------------------------------------------------

  Color getStratumColor(double worldX, double depthFeet) {
    final stratum = getStratumAtPosition(worldX, depthFeet);
    final base = stratum.primaryColor;
    final variation = NoiseUtils.sampleMultiOctave(
      seed: seed + 6000,
      x: worldX,
      y: depthFeet,
      octaves: 2,
      frequency: 0.05,
      gain: 0.4,
    );
    final factor = (variation - 0.5) * 0.2;
    return Color.from(
      alpha: base.a,
      red: (base.r + factor).clamp(0.0, 1.0),
      green: (base.g + factor).clamp(0.0, 1.0),
      blue: (base.b + factor).clamp(0.0, 1.0),
    );
  }

  double getHardnessAtPosition(double worldX, double depthFeet) {
    return getStratumAtPosition(worldX, depthFeet).hardness;
  }

  double getPorosityAtPosition(double worldX, double depthFeet) {
    return getStratumAtPosition(worldX, depthFeet).porosity;
  }

  double getErosionRateAtPosition(double worldX, double depthFeet) {
    return getStratumAtPosition(worldX, depthFeet).erosionRate;
  }

  CellType getCellTypeAtPosition(double worldX, double depthFeet) {
    return getStratumAtPosition(worldX, depthFeet).cellType;
  }

  List<OreType> getNativeOresAtPosition(double worldX, double depthFeet) {
    return getStratumAtPosition(worldX, depthFeet).nativeOres;
  }
}
