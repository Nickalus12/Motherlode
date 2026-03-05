import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// A single leaderboard entry
class LeaderboardEntry {
  final double maxDepth;
  final double totalCash;
  final String biomeReached;
  final DateTime date;
  final Duration playTime;
  final int ngPlusLevel;

  const LeaderboardEntry({
    required this.maxDepth,
    required this.totalCash,
    required this.biomeReached,
    required this.date,
    required this.playTime,
    this.ngPlusLevel = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'maxDepth': maxDepth,
      'totalCash': totalCash,
      'biome': biomeReached,
      'date': date.toIso8601String(),
      'playTimeMs': playTime.inMilliseconds,
      'ngPlus': ngPlusLevel,
    };
  }

  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    return LeaderboardEntry(
      maxDepth: (map['maxDepth'] as num).toDouble(),
      totalCash: (map['totalCash'] as num).toDouble(),
      biomeReached: map['biome'] as String? ?? 'Unknown',
      date: DateTime.parse(map['date'] as String),
      playTime: Duration(milliseconds: map['playTimeMs'] as int? ?? 0),
      ngPlusLevel: map['ngPlus'] as int? ?? 0,
    );
  }
}

/// Local leaderboard manager (high scores by depth and ore value)
class Leaderboard {
  Leaderboard._();

  static const String _boxName = 'hellbore_leaderboard';
  static const String _entriesKey = 'entries';
  static const int _maxEntries = 20;

  static Box? _box;

  /// Initialize leaderboard storage
  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Add a new entry to the leaderboard
  static Future<void> addEntry(LeaderboardEntry entry) async {
    final box = _box ?? await Hive.openBox(_boxName);
    final entries = await getEntries();

    entries.add(entry);

    // Sort by depth (primary) and cash (secondary)
    entries.sort((a, b) {
      final depthCompare = b.maxDepth.compareTo(a.maxDepth);
      if (depthCompare != 0) return depthCompare;
      return b.totalCash.compareTo(a.totalCash);
    });

    // Keep only top entries
    if (entries.length > _maxEntries) {
      entries.removeRange(_maxEntries, entries.length);
    }

    final json =
        jsonEncode(entries.map((e) => e.toMap()).toList());
    await box.put(_entriesKey, json);
  }

  /// Get all leaderboard entries sorted by score
  static Future<List<LeaderboardEntry>> getEntries() async {
    final box = _box ?? await Hive.openBox(_boxName);
    final json = box.get(_entriesKey) as String?;

    if (json == null) return [];

    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) =>
              LeaderboardEntry.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get top N entries
  static Future<List<LeaderboardEntry>> getTopEntries([int count = 10]) async {
    final entries = await getEntries();
    return entries.take(count).toList();
  }

  /// Check if a score would make the leaderboard
  static Future<bool> isHighScore(double depth, double cash) async {
    final entries = await getEntries();
    if (entries.length < _maxEntries) return true;

    final worstEntry = entries.last;
    return depth > worstEntry.maxDepth ||
        (depth == worstEntry.maxDepth && cash > worstEntry.totalCash);
  }

  /// Clear all leaderboard data
  static Future<void> clear() async {
    final box = _box ?? await Hive.openBox(_boxName);
    await box.delete(_entriesKey);
  }
}
