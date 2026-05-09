import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cross-process debug log shared between:
///   • the main app isolate
///   • the flutter_overlay_window overlay isolate
///   • the cached background engine isolate
///   • native code (Kotlin) — writes to the same key
///
/// Stored as a single JSON-encoded string in SharedPreferences so
/// both Dart and Kotlin can read/write without fighting the
/// shared_preferences StringList format. Surfaced in-app via
/// `DebugLogScreen` so we can diagnose without `adb logcat`.
class DebugLogService {
  /// Plain SharedPreferences key (Flutter side — the plugin adds the
  /// `flutter.` prefix internally; native side writes
  /// `flutter.vb_debug_log_json` directly).
  static const String _key = 'vb_debug_log_json';
  static const int _maxEntries = 200;

  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final StreamController<List<DebugLogEntry>> _ctrl =
      StreamController<List<DebugLogEntry>>.broadcast();

  Stream<List<DebugLogEntry>> get stream => _ctrl.stream;

  Future<void> log(String source, String message) async {
    final entry = DebugLogEntry(
      timestamp: DateTime.now(),
      source: source,
      message: message,
    );
    if (kDebugMode) {
      // ignore: avoid_print
      print('🪵 [${entry.source}] ${entry.message}');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key) ?? '[]';
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      list.add(entry.toMap());
      if (list.length > _maxEntries) {
        list.removeRange(0, list.length - _maxEntries);
      }
      await prefs.setString(_key, jsonEncode(list));
      _ctrl.add(list.map(DebugLogEntry.fromMap).toList());
    } catch (_) {
      // Logging must never throw or block — swallow.
    }
  }

  Future<List<DebugLogEntry>> readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key) ?? '[]';
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(DebugLogEntry.fromMap).toList();
    } catch (_) {
      return const <DebugLogEntry>[];
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      _ctrl.add(const <DebugLogEntry>[]);
    } catch (_) {}
  }

  Future<String> exportText() async {
    final entries = await readAll();
    return entries.map((e) => e.formatLine()).join('\n');
  }
}

class DebugLogEntry {
  final DateTime timestamp;
  final String source;
  final String message;

  DebugLogEntry({
    required this.timestamp,
    required this.source,
    required this.message,
  });

  Map<String, dynamic> toMap() => {
        't': timestamp.toIso8601String(),
        's': source,
        'm': message,
      };

  factory DebugLogEntry.fromMap(Map<String, dynamic> map) => DebugLogEntry(
        timestamp:
            DateTime.tryParse(map['t']?.toString() ?? '') ?? DateTime.now(),
        source: map['s']?.toString() ?? '?',
        message: map['m']?.toString() ?? '',
      );

  String formatLine() {
    final ts = timestamp.toLocal();
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    final ss = ts.second.toString().padLeft(2, '0');
    final ms = ts.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms  [$source]  $message';
  }
}
