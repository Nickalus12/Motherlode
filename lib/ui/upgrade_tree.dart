import 'package:flutter/material.dart';

import 'package:motherlode/data/upgrade_definitions.dart';
import 'package:motherlode/motherlode_game.dart';

/// Upgrade tree panel showing all 6 upgrade categories with tiers
class UpgradeTreePanel extends StatefulWidget {
  final MotherlodeGame game;

  const UpgradeTreePanel({super.key, required this.game});

  @override
  State<UpgradeTreePanel> createState() => _UpgradeTreePanelState();
}

class _UpgradeTreePanelState extends State<UpgradeTreePanel> {
  int _selectedCategory = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Category selector
        SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: UpgradeDefinitions.allCategories.length,
            itemBuilder: (context, index) {
              final cat = UpgradeDefinitions.allCategories[index];
              final isSelected = _selectedCategory == index;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCategory = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.amber.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? Colors.amber : Colors.white24,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(cat.icon, style: const TextStyle(fontSize: 16)),
                        Text(
                          cat.name,
                          style: TextStyle(
                            color: isSelected ? Colors.amber : Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Tier list for selected category
        Expanded(
          child: _buildTierList(),
        ),
      ],
    );
  }

  Widget _buildTierList() {
    final category = UpgradeDefinitions.allCategories[_selectedCategory];
    final currentLevel = _getCurrentLevel();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: category.tiers.length,
      itemBuilder: (context, index) {
        final tier = category.tiers[index];
        final isOwned = index <= currentLevel;
        final isNext = index == currentLevel + 1;
        final isLocked = index > currentLevel + 1;
        final canAfford =
            widget.game.playerCash >= tier.cost && tier.cost > 0;
        final isAncientScrollTier = tier.cost == 0 && index > 0;

        Color borderColor;
        Color bgColor;
        if (isOwned) {
          borderColor = Colors.green;
          bgColor = Colors.green.withValues(alpha: 0.1);
        } else if (isNext) {
          borderColor = canAfford ? Colors.amber : Colors.white30;
          bgColor = canAfford
              ? Colors.amber.withValues(alpha: 0.05)
              : Colors.transparent;
        } else {
          borderColor = Colors.white12;
          bgColor = Colors.transparent;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              // Tier indicator
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOwned ? Colors.green : Colors.transparent,
                  border: Border.all(
                    color: isOwned ? Colors.green : Colors.white24,
                  ),
                ),
                child: Center(
                  child: isOwned
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isLocked ? Colors.white24 : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Tier info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier.name,
                      style: TextStyle(
                        color: isOwned
                            ? Colors.green
                            : isLocked
                                ? Colors.white30
                                : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tier.description,
                      style: TextStyle(
                        color: isLocked ? Colors.white12 : Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    if (!isOwned && !isAncientScrollTier)
                      Text(
                        'Stat: ${tier.statValue}',
                        style: TextStyle(
                          color: Colors.cyan.withValues(alpha: isLocked ? 0.3 : 0.7),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),

              // Price / Buy button
              if (isOwned)
                const Text(
                  'OWNED',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (isAncientScrollTier)
                Text(
                  'SCROLL',
                  style: TextStyle(
                    color: Colors.purple.withValues(alpha: isLocked ? 0.3 : 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (isNext)
                ElevatedButton(
                  onPressed: canAfford ? () => _purchaseUpgrade(index) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canAfford
                        ? Colors.amber.shade800
                        : Colors.grey.shade800,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                  child: Text(
                    '\$${_formatCost(tier.cost)}',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                )
              else
                Text(
                  '\$${_formatCost(tier.cost)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  int _getCurrentLevel() {
    switch (_selectedCategory) {
      case 0:
        return widget.game.drillLevel;
      case 1:
        return widget.game.hullLevel;
      case 2:
        return widget.game.engineLevel;
      case 3:
        return widget.game.fuelTankLevel;
      case 4:
        return widget.game.radiatorLevel;
      case 5:
        return widget.game.cargoLevel;
      default:
        return 0;
    }
  }

  void _purchaseUpgrade(int tierIndex) {
    final category = UpgradeDefinitions.allCategories[_selectedCategory];
    final tier = category.tiers[tierIndex];

    if (!widget.game.spendCash(tier.cost.toDouble())) return;

    setState(() {
      switch (_selectedCategory) {
        case 0: // Drill
          widget.game.drillLevel = tierIndex;
          widget.game.pod.drillSpeed = tier.statValue;
          break;
        case 1: // Hull
          widget.game.hullLevel = tierIndex;
          widget.game.hullSystem.upgradeHull(tier.statValue);
          break;
        case 2: // Engine
          widget.game.engineLevel = tierIndex;
          widget.game.pod.enginePower = tier.statValue;
          break;
        case 3: // Fuel Tank
          widget.game.fuelTankLevel = tierIndex;
          widget.game.fuelSystem.upgradeCapacity(tier.statValue);
          break;
        case 4: // Radiator
          widget.game.radiatorLevel = tierIndex;
          widget.game.hullSystem.heatResistance = tier.statValue;
          break;
        case 5: // Cargo Bay
          widget.game.cargoLevel = tierIndex;
          widget.game.pod.cargoSystem.maxCapacity = tier.statValue;
          break;
      }
    });
  }

  String _formatCost(int cost) {
    if (cost >= 1000000) return '${(cost / 1000000).toStringAsFixed(1)}M';
    if (cost >= 1000) return '${(cost / 1000).toStringAsFixed(0)}K';
    return cost.toString();
  }
}
