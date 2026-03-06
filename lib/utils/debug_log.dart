import 'package:flutter/foundation.dart';

/// Severity levels for debug log entries.
enum LogLevel { info, warn, error }

/// A single log entry with timestamp, tag, level, and message.
class LogEntry {
  final DateTime timestamp;
  final String tag;
  final LogLevel level;
  final String message;

  LogEntry(this.timestamp, this.tag, this.level, this.message);

  @override
  String toString() {
    final t = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final lvl = level.name.toUpperCase();
    return '[$t][$lvl][$tag] $message';
  }
}

/// In-game debug log with ring buffer storage.
///
/// Stores the last [maxEntries] messages and also forwards them to debugPrint.
/// Read [entries] to display in the perf overlay or any debug UI.
class DebugLog {
  DebugLog._();

  static const int maxEntries = 100;
  static final List<LogEntry> _buffer = [];

  /// All stored log entries (oldest first).
  static List<LogEntry> get entries => List.unmodifiable(_buffer);

  /// Number of stored entries.
  static int get length => _buffer.length;

  static void _add(String tag, LogLevel level, String message) {
    final entry = LogEntry(DateTime.now(), tag, level, message);
    _buffer.add(entry);
    if (_buffer.length > maxEntries) _buffer.removeAt(0);
    debugPrint(entry.toString());
  }

  static void info(String tag, String message) =>
      _add(tag, LogLevel.info, message);

  static void warn(String tag, String message) =>
      _add(tag, LogLevel.warn, message);

  static void error(String tag, String message) =>
      _add(tag, LogLevel.error, message);

  /// Returns the last [count] entries (most recent last).
  static List<LogEntry> recent([int count = 5]) {
    final start = _buffer.length > count ? _buffer.length - count : 0;
    return _buffer.sublist(start);
  }

  /// Clear all entries.
  static void clear() => _buffer.clear();
}
