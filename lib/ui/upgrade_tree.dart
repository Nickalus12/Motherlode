import 'package:flutter/material.dart';

import 'package:motherlode/data/upgrade_definitions.dart';
import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/ui/upgrade_visuals.dart';

/// Upgrade tree panel showing all 6 upgrade categories with tiers
class UpgradeTreePanel extends StatefulWidget {
  final MotherlodeGame game;

  const UpgradeTreePanel({super.key, required this.game});

  @override
  State<UpgradeTreePanel> createState() => _UpgradeTreePanelState();
}

class _UpgradeTreePanelState extends State<UpgradeTreePanel> {
  int _selectedCategory = 0;

  static const _cardColor = Color(0xFF1C1C28);
  static const _surfaceColor = Color(0xFF16161E);
  static const _borderColor = Color(0xFF2A2A3A);
  static const _accentAmber = Color(0xFFF5A623);

  static const _categoryColors = [
    Colors.orange, // Drill
    Colors.cyan, // Hull
    Colors.green, // Engine
    Colors.amber, // Fuel Tank
    Colors.red, // Radiator
    Colors.purple, // Cargo
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Category selector
        Container(
          height: 68,
          decoration: const BoxDecoration(
            color: _surfaceColor,
            border: Border(bottom: BorderSide(color: _borderColor)),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: UpgradeDefinitions.allCategories.length,
            itemBuilder: (context, index) {
              final cat = UpgradeDefinitions.allCategories[index];
              final isSelected = _selectedCategory == index;
              final catColor = _categoryColors[index % _categoryColors.length];
              final currentLevel = _getCurrentLevel(index);
              final maxLevel = cat.tiers.length - 1;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCategory = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                catColor.withValues(alpha: 0.2),
                                catColor.withValues(alpha: 0.05),
                              ],
                            )
                          : null,
                      color: isSelected
                          ? null
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? catColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.08),
                        width: isSelected ? 1.5 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: catColor.withValues(alpha: 0.15),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(cat.icon, style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 30,
                          height: 2,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(1),
                            child: LinearProgressIndicator(
                              value: maxLevel > 0
                                  ? (currentLevel + 1) / (maxLevel + 1)
                                  : 0,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.05),
                              valueColor: AlwaysStoppedAnimation(
                                isSelected
                                    ? catColor
                                    : catColor.withValues(alpha: 0.3),
                              ),
                            ),
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

        // Visual for selected category
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _buildCategoryVisual(),
        ),

        // Tier list for selected category
        Expanded(
          child: _buildTierList(),
        ),
      ],
    );
  }

  Widget _buildCategoryVisual() {
    final currentLevel = _getCurrentLevel(_selectedCategory);
    final category = UpgradeDefinitions.allCategories[_selectedCategory];
    final maxLevel = category.maxLevel;

    switch (_selectedCategory) {
      case 0: // Drill
        return DrillVisualWidget(level: currentLevel, maxLevel: maxLevel);
      case 1: // Hull
        final hpPercent =
            widget.game.hullSystem.currentHull / widget.game.hullSystem.maxHull;
        return HullVisual(
            level: currentLevel, maxLevel: maxLevel, hpPercent: hpPercent);
      case 2: // Engine
        return EngineVisual(level: currentLevel, maxLevel: maxLevel);
      case 3: // Fuel Tank
        final fillPercent =
            widget.game.fuelSystem.currentFuel / widget.game.fuelSystem.maxFuel;
        return FuelTankVisual(
            level: currentLevel, maxLevel: maxLevel, fillPercent: fillPercent);
      case 4: // Radiator
        return RadiatorVisual(level: currentLevel, maxLevel: maxLevel);
      case 5: // Cargo Bay
        final cargo = widget.game.pod.cargoSystem;
        final fillPercent = cargo.currentWeight / cargo.maxCapacity;
        return CargoBayVisual(
            level: currentLevel,
            maxLevel: maxLevel,
            fillPercent: fillPercent.clamp(0.0, 1.0));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTierList() {
    final category = UpgradeDefinitions.allCategories[_selectedCategory];
    final currentLevel = _getCurrentLevel(_selectedCategory);
    final catColor =
        _categoryColors[_selectedCategory % _categoryColors.length];

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: category.tiers.length,
      itemBuilder: (context, index) {
        final tier = category.tiers[index];
        final isOwned = index <= currentLevel;
        final isNext = index == currentLevel + 1;
        final isLocked = index > currentLevel + 1;
        final isAncientScrollTier = tier.cost == 0 && index > 0;
        final canAfford = isAncientScrollTier
            ? widget.game.ancientScrollCount > 0
            : widget.game.playerCash >= tier.cost && tier.cost > 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress line
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    if (index > 0)
                      Container(
                        width: 2,
                        height: 8,
                        color: isOwned
                            ? catColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    _buildTierDot(isOwned, isNext, isLocked, catColor),
                    if (index < category.tiers.length - 1)
                      Container(
                        width: 2,
                        height: 8,
                        color: isOwned
                            ? catColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Tier card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOwned
                        ? catColor.withValues(alpha: 0.06)
                        : isNext
                            ? (canAfford
                                ? _accentAmber.withValues(alpha: 0.04)
                                : _cardColor)
                            : _cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isOwned
                          ? catColor.withValues(alpha: 0.3)
                          : isNext && canAfford
                              ? _accentAmber.withValues(alpha: 0.3)
                              : _borderColor,
                    ),
                    boxShadow: isOwned
                        ? [
                            BoxShadow(
                              color: catColor.withValues(alpha: 0.08),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      _buildTierIcon(index, isOwned, isLocked, catColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tier.name,
                              style: TextStyle(
                                color: isOwned
                                    ? catColor
                                    : isLocked
                                        ? Colors.white24
                                        : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tier.description,
                              style: TextStyle(
                                color: isLocked
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                              ),
                            ),
                            if (!isOwned && !isAncientScrollTier)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  'Stat: ${tier.statValue}',
                                  style: TextStyle(
                                    color: Colors.cyan.withValues(
                                        alpha: isLocked ? 0.2 : 0.6),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildTierAction(
                        isOwned: isOwned,
                        isNext: isNext,
                        isLocked: isLocked,
                        isAncientScrollTier: isAncientScrollTier,
                        canAfford: canAfford,
                        cost: tier.cost,
                        catColor: catColor,
                        onBuy: () => _purchaseUpgrade(index),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTierDot(
      bool isOwned, bool isNext, bool isLocked, Color catColor) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOwned
            ? catColor
            : isNext
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: isOwned
              ? catColor.withValues(alpha: 0.8)
              : isNext
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08),
          width: 1.5,
        ),
        boxShadow: isOwned
            ? [
                BoxShadow(
                  color: catColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
      child: isOwned
          ? const Icon(Icons.check, size: 10, color: Colors.white)
          : null,
    );
  }

  Widget _buildTierAction({
    required bool isOwned,
    required bool isNext,
    required bool isLocked,
    required bool isAncientScrollTier,
    required bool canAfford,
    required int cost,
    required Color catColor,
    required VoidCallback onBuy,
  }) {
    if (isOwned) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: catColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: catColor.withValues(alpha: 0.2)),
        ),
        child: Icon(
          Icons.check,
          color: catColor,
          size: 16,
        ),
      );
    }

    if (isAncientScrollTier) {
      final hasScroll = canAfford && isNext;
      return GestureDetector(
        onTap: hasScroll ? onBuy : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: hasScroll
                ? Colors.purple.withValues(alpha: 0.2)
                : Colors.purple.withValues(alpha: isLocked ? 0.05 : 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: hasScroll
                    ? Colors.purple.withValues(alpha: 0.6)
                    : Colors.purple.withValues(alpha: isLocked ? 0.1 : 0.3)),
            boxShadow: hasScroll
                ? [
                    BoxShadow(
                      color: Colors.purple.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories,
                color: hasScroll
                    ? Colors.purple
                    : Colors.purple.withValues(alpha: isLocked ? 0.25 : 0.7),
                size: 16,
              ),
              if (hasScroll) ...[
                const SizedBox(width: 4),
                Text(
                  'x${widget.game.ancientScrollCount}',
                  style: const TextStyle(
                    color: Colors.purple,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (isNext) {
      return GestureDetector(
        onTap: canAfford ? onBuy : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: canAfford
                ? LinearGradient(colors: [
                    _accentAmber.withValues(alpha: 0.8),
                    Colors.orange.withValues(alpha: 0.7),
                  ])
                : null,
            color: canAfford ? null : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: canAfford
                  ? _accentAmber.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
            ),
            boxShadow: canAfford
                ? [
                    BoxShadow(
                      color: _accentAmber.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Text(
            '\$${_formatCost(cost)}',
            style: TextStyle(
              color: canAfford ? Colors.white : Colors.white30,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Text(
      '\$${_formatCost(cost)}',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.15),
        fontSize: 11,
      ),
    );
  }

  static const _drillAssets = {
    0: 'assets/images/drills/drill_basic.png',
    1: 'assets/images/drills/drill_silver.png',
    2: 'assets/images/drills/drill_gold.png',
    3: 'assets/images/drills/drill_emerald.png',
    4: 'assets/images/drills/drill_magma.png',
    5: 'assets/images/drills/drill_diamond.png',
  };

  Widget _buildTierIcon(
      int index, bool isOwned, bool isLocked, Color catColor) {
    if (_selectedCategory == 0 && _drillAssets.containsKey(index)) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOwned
                ? catColor.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
          ),
          color: isOwned
              ? catColor.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.02),
          boxShadow: isOwned
              ? [
                  BoxShadow(
                    color: catColor.withValues(alpha: 0.15),
                    blurRadius: 4,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Image.asset(
            _drillAssets[index]!,
            fit: BoxFit.contain,
            opacity: AlwaysStoppedAnimation(isLocked ? 0.2 : 1.0),
            errorBuilder: (_, __, ___) => Icon(
              isOwned ? Icons.check : Icons.hardware,
              size: 16,
              color: isOwned ? catColor : Colors.white24,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isOwned
            ? LinearGradient(
                colors: [catColor, catColor.withValues(alpha: 0.7)])
            : null,
        color: isOwned ? null : Colors.white.withValues(alpha: 0.03),
        border: Border.all(
          color: isOwned
              ? catColor.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
        boxShadow: isOwned
            ? [
                BoxShadow(
                  color: catColor.withValues(alpha: 0.2),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
      child: Center(
        child: isOwned
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  color: isLocked ? Colors.white10 : Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  int _getCurrentLevel([int? category]) {
    switch (category ?? _selectedCategory) {
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

  void _purchaseUpgrade(int tierIndex) async {
    final category = UpgradeDefinitions.allCategories[_selectedCategory];
    final tier = category.tiers[tierIndex];
    final cost = tier.cost.toDouble();
    final isScrollTier = tier.cost == 0 && tierIndex > 0;

    if (isScrollTier) {
      // Ancient Scroll tier — confirm and consume a scroll
      if (widget.game.ancientScrollCount <= 0) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C28),
          title: Text('Unlock ${tier.name}?',
              style: const TextStyle(color: Colors.white)),
          content: Text(
            'Use an Ancient Scroll to unlock ${tier.name}?\n'
            'Scrolls remaining: ${widget.game.ancientScrollCount}',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('UNLOCK',
                  style: TextStyle(
                      color: Colors.purple, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      widget.game.ancientScrollCount--;
    } else {
      // Normal cash purchase — confirmation dialog for expensive upgrades
      if (cost >= 1000) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C28),
            title: Text('Buy ${tier.name}?',
                style: const TextStyle(color: Colors.white)),
            content: Text(
              'Purchase ${category.name} upgrade for \$${_formatCost(tier.cost)}?',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('BUY',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      if (!widget.game.spendCash(cost)) return;
    }

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
