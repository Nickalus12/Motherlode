import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:motherlode/world/terrain_cell.dart';
import 'package:motherlode/world/ore_registry.dart';
import 'package:motherlode/world/sdf_primitives.dart';
import 'package:motherlode/world/stratigraphy.dart';

void main() {
  group('TerrainCell construction', () {
    test('default cell is empty with positive SDF', () {
      final cell = TerrainCell();
      expect(cell.type, CellType.empty);
      expect(cell.sdf, greaterThan(0)); // density=0 -> sdf=0.5
      expect(cell.oreType, isNull);
      expect(cell.isDirty, isTrue);
      expect(cell.hasCreatureSpawn, isFalse);
      expect(cell.stratum, isNull);
    });

    test('cell with explicit SDF ignores density', () {
      final cell = TerrainCell(type: CellType.dirt, sdf: -5.0, density: 0.9);
      expect(cell.sdf, -5.0);
    });

    test('cell with density converts to SDF via densityToSdf', () {
      final cell = TerrainCell(type: CellType.dirt, density: 0.8);
      expect(cell.sdf, SdfPrimitives.densityToSdf(0.8));
    });

    test('cell with sdf=null falls back to density conversion', () {
      final cell = TerrainCell(type: CellType.rock, density: 1.0);
      expect(cell.sdf, SdfPrimitives.densityToSdf(1.0));
      expect(cell.sdf, lessThan(0)); // solid
    });
  });

  group('SDF/density conversion', () {
    test('density getter converts SDF back', () {
      final cell = TerrainCell(sdf: -0.3);
      expect(cell.density, SdfPrimitives.sdfToDensity(-0.3));
    });

    test('density setter updates SDF', () {
      final cell = TerrainCell(sdf: 1.0);
      cell.density = 0.9;
      expect(cell.sdf, SdfPrimitives.densityToSdf(0.9));
    });

    test('density roundtrip is consistent', () {
      for (final d in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final cell = TerrainCell(density: d);
        // density -> sdf -> density should be close (clamped)
        expect(cell.density, closeTo(d.clamp(0.0, 1.0), 0.01));
      }
    });

    test('SDF threshold at 0.5 density', () {
      // density=0.5 -> sdf=0.0 (surface)
      final cell = TerrainCell(density: 0.5);
      expect(cell.sdf, closeTo(0.0, 0.001));
    });
  });

  group('isSolid', () {
    test('negative SDF with solid type is solid', () {
      expect(TerrainCell(type: CellType.dirt, sdf: -1.0).isSolid, isTrue);
      expect(TerrainCell(type: CellType.rock, sdf: -1.0).isSolid, isTrue);
      expect(TerrainCell(type: CellType.sand, sdf: -1.0).isSolid, isTrue);
      expect(TerrainCell(type: CellType.obsidian, sdf: -1.0).isSolid, isTrue);
      expect(TerrainCell(type: CellType.bedrock, sdf: -1.0).isSolid, isTrue);
      expect(TerrainCell(type: CellType.ore, sdf: -1.0).isSolid, isTrue);
    });

    test('positive SDF is not solid', () {
      expect(TerrainCell(type: CellType.dirt, sdf: 1.0).isSolid, isFalse);
    });

    test('empty type is not solid even with negative SDF', () {
      expect(TerrainCell(type: CellType.empty, sdf: -1.0).isSolid, isFalse);
    });

    test('lava is not solid even with negative SDF', () {
      expect(TerrainCell(type: CellType.lava, sdf: -1.0).isSolid, isFalse);
    });

    test('gas is not solid even with negative SDF', () {
      expect(TerrainCell(type: CellType.gas, sdf: -1.0).isSolid, isFalse);
    });
  });

  group('isDrillable', () {
    test('drillable types', () {
      expect(TerrainCell(type: CellType.dirt).isDrillable, isTrue);
      expect(TerrainCell(type: CellType.rock).isDrillable, isTrue);
      expect(TerrainCell(type: CellType.sand).isDrillable, isTrue);
      expect(TerrainCell(type: CellType.obsidian).isDrillable, isTrue);
      expect(TerrainCell(type: CellType.ore).isDrillable, isTrue);
    });

    test('non-drillable types', () {
      expect(TerrainCell(type: CellType.empty).isDrillable, isFalse);
      expect(TerrainCell(type: CellType.lava).isDrillable, isFalse);
      expect(TerrainCell(type: CellType.gas).isDrillable, isFalse);
      expect(TerrainCell(type: CellType.bedrock).isDrillable, isFalse);
    });
  });

  group('isHazard', () {
    test('lava and gas are hazards', () {
      expect(TerrainCell(type: CellType.lava).isHazard, isTrue);
      expect(TerrainCell(type: CellType.gas).isHazard, isTrue);
    });

    test('other types are not hazards', () {
      expect(TerrainCell(type: CellType.dirt).isHazard, isFalse);
      expect(TerrainCell(type: CellType.rock).isHazard, isFalse);
      expect(TerrainCell(type: CellType.empty).isHazard, isFalse);
    });
  });

  group('hardness', () {
    test('sand has lowest hardness', () {
      expect(TerrainCell(type: CellType.sand).hardness, 0.5);
    });

    test('dirt has base hardness', () {
      expect(TerrainCell(type: CellType.dirt).hardness, 1.0);
    });

    test('rock has 2x hardness', () {
      expect(TerrainCell(type: CellType.rock).hardness, 2.0);
    });

    test('obsidian has 4x hardness', () {
      expect(TerrainCell(type: CellType.obsidian).hardness, 4.0);
    });

    test('bedrock has infinite hardness', () {
      expect(TerrainCell(type: CellType.bedrock).hardness, double.infinity);
    });

    test('ore uses ore type hardness', () {
      final cell =
          TerrainCell(type: CellType.ore, oreType: OreRegistry.diamond);
      expect(cell.hardness, OreRegistry.diamond.hardness);
    });

    test('ore with null oreType defaults to 1.0', () {
      expect(TerrainCell(type: CellType.ore).hardness, 1.0);
    });

    test('empty has 0 hardness', () {
      expect(TerrainCell(type: CellType.empty).hardness, 0.0);
    });
  });

  group('baseColor', () {
    test('each cell type has a non-null color', () {
      for (final type in CellType.values) {
        final cell = TerrainCell(type: type);
        expect(cell.baseColor, isA<Color>());
      }
    });

    test('ore color uses oreType color', () {
      final cell =
          TerrainCell(type: CellType.ore, oreType: OreRegistry.goldium);
      expect(cell.baseColor, OreRegistry.goldium.color);
    });

    test('ore with null oreType uses default gold', () {
      final cell = TerrainCell(type: CellType.ore);
      expect(cell.baseColor, const Color(0xFFFFD700));
    });
  });

  group('alwaysCollapses', () {
    test('sand always collapses', () {
      expect(TerrainCell(type: CellType.sand).alwaysCollapses, isTrue);
    });

    test('other types do not always collapse', () {
      expect(TerrainCell(type: CellType.dirt).alwaysCollapses, isFalse);
      expect(TerrainCell(type: CellType.rock).alwaysCollapses, isFalse);
    });
  });

  group('copy', () {
    test('copy creates independent cell with same values', () {
      final original = TerrainCell(
        type: CellType.ore,
        sdf: -2.5,
        oreType: OreRegistry.ruby,
        isDirty: false,
        hasCreatureSpawn: true,
        stratum: StratumType.basalt,
      );
      final copied = original.copy();

      expect(copied.type, original.type);
      expect(copied.sdf, original.sdf);
      expect(copied.oreType, original.oreType);
      expect(copied.isDirty, original.isDirty);
      expect(copied.hasCreatureSpawn, original.hasCreatureSpawn);
      expect(copied.stratum, original.stratum);
    });

    test('modifying copy does not affect original', () {
      final original = TerrainCell(type: CellType.dirt, sdf: -1.0);
      final copied = original.copy();
      copied.type = CellType.rock;
      copied.sdf = -5.0;

      expect(original.type, CellType.dirt);
      expect(original.sdf, -1.0);
    });
  });

  group('serialization', () {
    test('toMap includes all fields', () {
      final cell = TerrainCell(
        type: CellType.ore,
        sdf: -3.0,
        oreType: OreRegistry.goldium,
        hasCreatureSpawn: true,
        stratum: StratumType.granite,
      );
      final map = cell.toMap();

      expect(map['type'], CellType.ore.index);
      expect(map['sdf'], -3.0);
      expect(map['oreId'], 'Goldium');
      expect(map['hasCreature'], isTrue);
      expect(map['stratum'], StratumType.granite.index);
    });

    test('toMap omits stratum when null', () {
      final cell = TerrainCell(type: CellType.dirt, sdf: -1.0);
      final map = cell.toMap();
      expect(map.containsKey('stratum'), isFalse);
    });

    test('toMap omits oreId when null', () {
      final cell = TerrainCell(type: CellType.dirt, sdf: -1.0);
      final map = cell.toMap();
      expect(map['oreId'], isNull);
    });

    test('fromMap roundtrip preserves SDF cell', () {
      final original = TerrainCell(
        type: CellType.rock,
        sdf: -2.5,
        hasCreatureSpawn: true,
        stratum: StratumType.basalt,
      );
      final restored = TerrainCell.fromMap(original.toMap());

      expect(restored.type, original.type);
      expect(restored.sdf, original.sdf);
      expect(restored.hasCreatureSpawn, original.hasCreatureSpawn);
      expect(restored.stratum, original.stratum);
    });

    test('fromMap handles legacy density format', () {
      // Old save format without SDF
      final legacyMap = {
        'type': CellType.dirt.index,
        'density': 0.8,
        'oreId': null,
        'hasCreature': false,
      };
      final cell = TerrainCell.fromMap(legacyMap);
      expect(cell.type, CellType.dirt);
      expect(cell.sdf, SdfPrimitives.densityToSdf(0.8));
    });

    test('fromMap with ore restores ore type', () {
      final map = {
        'type': CellType.ore.index,
        'sdf': -1.5,
        'oreId': 'Ironium',
        'hasCreature': false,
      };
      final cell = TerrainCell.fromMap(map);
      expect(cell.oreType, isNotNull);
      expect(cell.oreType!.name, 'Ironium');
    });
  });
}
