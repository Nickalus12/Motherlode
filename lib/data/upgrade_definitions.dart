/// Definition of a single upgrade tier
class UpgradeTier {
  final String name;
  final int cost;
  final double statValue; // The stat this upgrade provides
  final String description;

  const UpgradeTier({
    required this.name,
    required this.cost,
    required this.statValue,
    required this.description,
  });
}

/// Upgrade category with all tiers
class UpgradeCategory {
  final String name;
  final String icon;
  final List<UpgradeTier> tiers;

  const UpgradeCategory({
    required this.name,
    required this.icon,
    required this.tiers,
  });

  /// Get the tier at a given level (0-indexed)
  UpgradeTier? getTier(int level) {
    if (level < 0 || level >= tiers.length) return null;
    return tiers[level];
  }

  /// Max upgrade level (0-indexed)
  int get maxLevel => tiers.length - 1;
}

/// Complete upgrade definitions matching original Motherload
class UpgradeDefinitions {
  UpgradeDefinitions._();

  // ─── DRILLS ───
  static const UpgradeCategory drills = UpgradeCategory(
    name: 'Drill',
    icon: '⛏',
    tiers: [
      UpgradeTier(
        name: 'Stock Drill',
        cost: 0,
        statValue: 50, // drill speed ft/s
        description: 'Basic mining drill. Gets the job done... slowly.',
      ),
      UpgradeTier(
        name: 'Silvide Drill',
        cost: 2000,
        statValue: 80,
        description: 'Silver-carbide tipped. 60% faster drilling.',
      ),
      UpgradeTier(
        name: 'Goldium Drill',
        cost: 5000,
        statValue: 120,
        description: 'Gold-alloy edges. Cuts through rock with ease.',
      ),
      UpgradeTier(
        name: 'Emerald Drill',
        cost: 20000,
        statValue: 180,
        description: 'Emerald crystalline bit. Extremely hard.',
      ),
      UpgradeTier(
        name: 'Ruby Drill',
        cost: 100000,
        statValue: 260,
        description: 'Ruby-tipped. Slices through obsidian.',
      ),
      UpgradeTier(
        name: 'Diamond Drill',
        cost: 500000,
        statValue: 400,
        description: 'Diamond-edge. Almost nothing resists it.',
      ),
      UpgradeTier(
        name: 'Amazonite Drill',
        cost: 2000000,
        statValue: 600,
        description: 'Amazonite composite. The ultimate drill.',
      ),
      UpgradeTier(
        name: 'Multi Drill',
        cost: 0, // Requires Ancient Scroll
        statValue: 900,
        description:
            'Ancient tech. Drills 3 cells wide. [Ancient Scroll required]',
      ),
    ],
  );

  // ─── HULLS ───
  static const UpgradeCategory hulls = UpgradeCategory(
    name: 'Hull',
    icon: '🛡',
    tiers: [
      UpgradeTier(
        name: 'Stock Hull',
        cost: 0,
        statValue: 50, // max HP (base)
        description: 'Thin aluminum shell. Handle with care.',
      ),
      UpgradeTier(
        name: 'Ironium Hull',
        cost: 2000,
        statValue: 100,
        description: 'Ironium plating. Twice the protection.',
      ),
      UpgradeTier(
        name: 'Bronzium Hull',
        cost: 5000,
        statValue: 175,
        description: 'Bronzium alloy. Resists moderate impacts.',
      ),
      UpgradeTier(
        name: 'Steel Hull',
        cost: 20000,
        statValue: 275,
        description: 'Reinforced steel. Built to last.',
      ),
      UpgradeTier(
        name: 'Platinium Hull',
        cost: 75000,
        statValue: 400,
        description: 'Platinium composite. Military grade.',
      ),
      UpgradeTier(
        name: 'Einsteinium Hull',
        cost: 300000,
        statValue: 600,
        description: 'Einsteinium matrix. Absorbs massive impacts.',
      ),
      UpgradeTier(
        name: 'Energy-Shielded Hull',
        cost: 1500000,
        statValue: 1000,
        description: 'Force-field reinforced. Near-indestructible.',
      ),
      UpgradeTier(
        name: 'Regenerative Hull',
        cost: 0, // Requires Ancient Scroll
        statValue: 1500,
        description: 'Self-healing nanomaterial. [Ancient Scroll required]',
      ),
    ],
  );

  // ─── ENGINES ───
  static const UpgradeCategory engines = UpgradeCategory(
    name: 'Engine',
    icon: '🚀',
    tiers: [
      UpgradeTier(
        name: 'Stock Engine',
        cost: 0,
        statValue: 3000, // engine power
        description: 'Sputtering single-cylinder. Barely lifts off.',
      ),
      UpgradeTier(
        name: 'V4 1600cc',
        cost: 2500,
        statValue: 4500,
        description: 'Inline four. Reliable and responsive.',
      ),
      UpgradeTier(
        name: 'V4 2.0 Turbo',
        cost: 7500,
        statValue: 6500,
        description: 'Turbocharged. Serious thrust.',
      ),
      UpgradeTier(
        name: 'V6 3.8L',
        cost: 25000,
        statValue: 9000,
        description: 'Six cylinders of raw power.',
      ),
      UpgradeTier(
        name: 'V8 5.0L',
        cost: 100000,
        statValue: 12000,
        description: 'Muscle car of mining robots.',
      ),
      UpgradeTier(
        name: 'V12 6.0L',
        cost: 400000,
        statValue: 16000,
        description: 'Supercar performance. Lifts fully loaded robot easily.',
      ),
      UpgradeTier(
        name: 'V16 Jag',
        cost: 2000000,
        statValue: 22000,
        description: 'Experimental 16-cylinder. Absurd power.',
      ),
      UpgradeTier(
        name: 'Hyper Drive',
        cost: 0, // Requires Ancient Scroll
        statValue: 35000,
        description: 'Gravity-defying propulsion. [Ancient Scroll required]',
      ),
    ],
  );

  // ─── FUEL TANKS ───
  static const UpgradeCategory fuelTanks = UpgradeCategory(
    name: 'Fuel Tank',
    icon: '⛽',
    tiers: [
      UpgradeTier(
        name: 'Micro Tank',
        cost: 0,
        statValue: 10, // liters
        description: 'Tiny fuel cell. Surface trips only.',
      ),
      UpgradeTier(
        name: 'Medium Tank',
        cost: 2000,
        statValue: 25,
        description: 'Decent range for shallow mining.',
      ),
      UpgradeTier(
        name: 'Huge Tank',
        cost: 5000,
        statValue: 50,
        description: 'Extended operations underground.',
      ),
      UpgradeTier(
        name: 'Gigantic Tank',
        cost: 15000,
        statValue: 100,
        description: 'Deep mining capable.',
      ),
      UpgradeTier(
        name: 'Titanic Tank',
        cost: 50000,
        statValue: 200,
        description: 'Marathon mining sessions.',
      ),
      UpgradeTier(
        name: 'Leviathan Tank',
        cost: 200000,
        statValue: 400,
        description: 'Massive fuel reserve.',
      ),
      UpgradeTier(
        name: 'Liquid Compression',
        cost: 1000000,
        statValue: 800,
        description: 'Compressed fuel technology. Nearly limitless range.',
      ),
      UpgradeTier(
        name: 'Fuel Integrator',
        cost: 0, // Requires Ancient Scroll
        statValue: 2000,
        description: 'Converts ambient heat to fuel. [Ancient Scroll required]',
      ),
    ],
  );

  // ─── RADIATORS ───
  static const UpgradeCategory radiators = UpgradeCategory(
    name: 'Radiator',
    icon: '❄',
    tiers: [
      UpgradeTier(
        name: 'Stock Fan',
        cost: 0,
        statValue: 0.0, // heat resistance (0.0 to 1.0)
        description: 'A desk fan bolted to the hull. Useless.',
      ),
      UpgradeTier(
        name: 'Dual Fans',
        cost: 2000,
        statValue: 0.15,
        description: 'Two fans. Slightly less useless.',
      ),
      UpgradeTier(
        name: 'Single Turbine',
        cost: 8000,
        statValue: 0.30,
        description: 'Turbine cooling. Handles warm zones.',
      ),
      UpgradeTier(
        name: 'Dual Turbine',
        cost: 30000,
        statValue: 0.45,
        description: 'Dual turbines. Volcanic zone ready.',
      ),
      UpgradeTier(
        name: 'Puron Cooling',
        cost: 100000,
        statValue: 0.60,
        description: 'Chemical coolant. Survives lava proximity.',
      ),
      UpgradeTier(
        name: 'Tri-Turbine',
        cost: 500000,
        statValue: 0.80,
        description: 'Triple turbine array. Near-immune to heat.',
      ),
      UpgradeTier(
        name: 'Magma Converter',
        cost: 0, // Requires Ancient Scroll
        statValue: 1.0,
        description:
            'Converts heat to energy. Immune to lava. [Ancient Scroll required]',
      ),
    ],
  );

  // ─── CARGO BAYS ───
  static const UpgradeCategory cargoBays = UpgradeCategory(
    name: 'Cargo Bay',
    icon: '📦',
    tiers: [
      UpgradeTier(
        name: 'Micro Bay',
        cost: 0,
        statValue: 50, // kg capacity
        description: 'A small compartment. A few rocks fit.',
      ),
      UpgradeTier(
        name: 'Medium Bay',
        cost: 2000,
        statValue: 100,
        description: 'Reasonable storage for short trips.',
      ),
      UpgradeTier(
        name: 'Huge Bay',
        cost: 5000,
        statValue: 200,
        description: 'Carry a decent haul.',
      ),
      UpgradeTier(
        name: 'Gigantic Bay',
        cost: 20000,
        statValue: 400,
        description: 'Major cargo capacity.',
      ),
      UpgradeTier(
        name: 'Titanic Bay',
        cost: 75000,
        statValue: 750,
        description: 'Massive holds. Fill them with diamonds.',
      ),
      UpgradeTier(
        name: 'Leviathan Bay',
        cost: 300000,
        statValue: 1200,
        description: 'Warehouse-sized cargo bay.',
      ),
      UpgradeTier(
        name: 'Portable Wormhole',
        cost: 1500000,
        statValue: 2500,
        description: 'Interdimensional storage. Practically unlimited.',
      ),
    ],
  );

  /// All upgrade categories
  static const List<UpgradeCategory> allCategories = [
    drills,
    hulls,
    engines,
    fuelTanks,
    radiators,
    cargoBays,
  ];

  /// Get an upgrade category by name
  static UpgradeCategory? getCategory(String name) {
    for (final cat in allCategories) {
      if (cat.name == name) return cat;
    }
    return null;
  }
}
