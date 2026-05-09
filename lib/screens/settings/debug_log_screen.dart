import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debug_log_service.dart';
import '../../services/native_overlay_service.dart';
import '../../services/text_injection_service.dart';

/// In-app Debug Log screen — the unified diagnostic surface that
/// replaces `adb logcat` for our cloud-built APKs.
///
/// Top: a live HUD with current-state booleans (overlay perm, a11y
/// granted, bubble service active, focused app package, etc.).
/// Bottom: a scrollable list of cross-process log entries written
/// by every isolate + the native services.
class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final DebugLogService _log = DebugLogService();
  List<DebugLogEntry> _entries = const [];

  // HUD state
  bool? _overlayPerm;
  bool? _bubbleActive;
  bool? _a11yEnabled;
  String? _focusedPackage;

  Timer? _hudTimer;
  StreamSubscription? _logSub;

  @override
  void initState() {
    super.initState();
    _refreshLog();
    _refreshHud();
    _hudTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshHud());
    _logSub = _log.stream.listen((list) {
      if (mounted) setState(() => _entries = list);
    });
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _logSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshLog() async {
    final entries = await _log.readAll();
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _refreshHud() async {
    if (!Platform.isAndroid) return;
    final overlay = await NativeOverlayService.checkPermission();
    final active = await NativeOverlayService.isActive();
    final a11y = await TextInjectionService.isEnabled();
    final pkg = await TextInjectionService.getFocusedAppPackage();
    if (!mounted) return;
    setState(() {
      _overlayPerm = overlay;
      _bubbleActive = active;
      _a11yEnabled = a11y;
      _focusedPackage = pkg;
    });
  }

  Future<void> _copyAll() async {
    final text = await _log.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Log copied to clipboard'),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _clearAll() async {
    await _log.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log cleared'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        title: const Text('Debug Log',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copyAll,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _clearAll,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _refreshLog();
              _refreshHud();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _Hud(
            overlayPerm: _overlayPerm,
            bubbleActive: _bubbleActive,
            a11yEnabled: _a11yEnabled,
            focusedPackage: _focusedPackage,
            entryCount: _entries.length,
          ),
          const Divider(height: 1, color: Color(0xFF1A1A2E)),
          Expanded(
            child: _entries.isEmpty
                ? const Center(
                    child: Text(
                      'No log entries yet — tap the bubble to generate some',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) {
                      final e = _entries[_entries.length - 1 - i];
                      return _LogRow(entry: e);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  final bool? overlayPerm;
  final bool? bubbleActive;
  final bool? a11yEnabled;
  final String? focusedPackage;
  final int entryCount;
  const _Hud({
    required this.overlayPerm,
    required this.bubbleActive,
    required this.a11yEnabled,
    required this.focusedPackage,
    required this.entryCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: const Color(0xFF11111F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                label: 'Overlay perm',
                value: overlayPerm,
              ),
              _Pill(
                label: 'Bubble running',
                value: bubbleActive,
              ),
              _Pill(
                label: 'Accessibility',
                value: a11yEnabled,
              ),
              _Pill(
                label: 'Entries',
                neutralValue: entryCount.toString(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Focused app: ${focusedPackage ?? "(none reported)"}',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool? value;
  final String? neutralValue;
  const _Pill({required this.label, this.value, this.neutralValue});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    if (neutralValue != null) {
      color = const Color(0xFF7C6AE8);
      text = '$label: $neutralValue';
    } else {
      switch (value) {
        case true:
          color = const Color(0xFF10B981);
          text = '✓ $label';
          break;
        case false:
          color = const Color(0xFFEF4444);
          text = '✗ $label';
          break;
        default:
          color = const Color(0xFF94A3B8);
          text = '… $label';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final DebugLogEntry entry;
  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _colorForSource(entry.source);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF15152A),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              _hms(entry.timestamp),
              style: const TextStyle(
                color: Color(0xFF60607A),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              entry.source,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _hms(DateTime t) {
    final d = t.toLocal();
    String z(int n, [int len = 2]) => n.toString().padLeft(len, '0');
    return '${z(d.hour)}:${z(d.minute)}:${z(d.second)}.${z(d.millisecond, 3)}';
  }

  Color _colorForSource(String source) {
    switch (source) {
      case 'App':
        return const Color(0xFF7C6AE8);
      case 'Bubble':
        return const Color(0xFF3B82F6);
      case 'Bridge':
        return const Color(0xFFF59E0B);
      case 'Overlay':
        return const Color(0xFFEC4899);
      case 'A11y':
        return const Color(0xFF10B981);
      case 'BgEngine':
        return const Color(0xFF06B6D4);
      default:
        return const Color(0xFF94A3B8);
    }
  }
}
