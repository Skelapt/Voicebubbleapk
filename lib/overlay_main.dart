import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/preset.dart';
import 'services/ai_service.dart';
import 'services/debug_log_service.dart';
import 'services/text_injection_service.dart';

/// Entry point for the floating recording overlay isolate. Spun up
/// by `flutter_overlay_window` whenever the bubble is tapped.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DebugLogService()
      .log('Overlay', 'overlayMain entry-point reached (overlay isolate)');
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: _RecordingFlow(),
      ),
    );
  }
}

// ───────────────────── Design tokens ─────────────────────

const _kBrandPurple = Color(0xFF7C6AE8);
const _kSurface = Color(0xFF0D0D1A);
const _kDangerRed = Color(0xFFEF4444);
const _kPillRadius = 28.0;

enum _Phase {
  presetSelection,
  customInput,
  recording,
  polishing,
  result,
  inserting,
  error,
}

/// The five quick presets we expose on the long-press fan, in order.
/// Custom is special — it opens a text input rather than starting
/// recording immediately.
class _QuickPreset {
  final String id; // backend preset id, or "custom"
  final String label;
  final IconData icon;
  const _QuickPreset(this.id, this.label, this.icon);
}

const _kQuickPresets = <_QuickPreset>[
  _QuickPreset('magic', 'Magic', Icons.auto_awesome_rounded),
  _QuickPreset('quick_reply', 'Reply', Icons.reply_rounded),
  _QuickPreset('email_professional', 'Email', Icons.mail_outline_rounded),
  _QuickPreset('instagram_caption', 'Social', Icons.local_fire_department_rounded),
  _QuickPreset('custom', 'Custom', Icons.edit_rounded),
];

// ───────────────────── Main flow widget ─────────────────────

class _RecordingFlow extends StatefulWidget {
  const _RecordingFlow();

  @override
  State<_RecordingFlow> createState() => _RecordingFlowState();
}

class _RecordingFlowState extends State<_RecordingFlow>
    with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  final AIService _ai = AIService();

  _Phase _phase = _Phase.recording;
  String? _audioPath;
  StreamSubscription<Amplitude>? _ampSub;

  // Live waveform data — most recent on the right.
  final List<double> _wave = List<double>.filled(20, 0.18);
  double _targetLevel = 0.2;

  // Result data
  String _resultText = '';
  String? _intentLabel;
  String _errorMessage = '';

  // Preset / custom-instruction selection (set by the long-press fan).
  String _activePresetId = 'magic';
  String? _customInstruction;
  final TextEditingController _customCtrl = TextEditingController();

  // Animation controllers for the polishing shimmer + result fade-in.
  late final AnimationController _shimmerCtrl;
  late final AnimationController _waveCtrl;
  late final AnimationController _enterCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    )..addListener(_animateWave);
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..forward();
    _waveCtrl.repeat();

    _bootstrap();
  }

  /// Decide whether to start in recording mode (short tap on the bubble)
  /// or in preset selection mode (long-press), based on the flag the
  /// native OverlayService writes to SharedPreferences right before
  /// it invokes the activity.
  Future<void> _bootstrap() async {
    bool showPresets = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      showPresets = prefs.getBool('show_presets_on_open') ?? false;
      if (showPresets) {
        await prefs.setBool('show_presets_on_open', false);
      }
    } catch (_) {}

    await DebugLogService()
        .log('Overlay', 'Bootstrap: showPresets=$showPresets');

    if (!mounted) return;
    if (showPresets) {
      setState(() => _phase = _Phase.presetSelection);
    } else {
      _startRecording();
    }
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _recorder.dispose();
    _customCtrl.dispose();
    _shimmerCtrl.dispose();
    _waveCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  // ───────── Preset selection ─────────

  void _onPresetTap(_QuickPreset preset) {
    HapticFeedback.selectionClick();
    if (preset.id == 'custom') {
      setState(() => _phase = _Phase.customInput);
      return;
    }
    setState(() {
      _activePresetId = preset.id;
      _customInstruction = null;
      _phase = _Phase.recording;
    });
    _startRecording();
  }

  void _submitCustomInstruction() {
    final instruction = _customCtrl.text.trim();
    if (instruction.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _activePresetId = 'magic'; // Magic + custom instruction as steering
      _customInstruction = instruction;
      _phase = _Phase.recording;
    });
    _startRecording();
  }

  // ───────── Recording ─────────

  Future<void> _startRecording() async {
    HapticFeedback.lightImpact();
    await DebugLogService().log('Overlay', '_startRecording invoked');
    try {
      if (!await _recorder.hasPermission()) {
        await DebugLogService()
            .log('Overlay', 'Mic permission MISSING — failing to error phase');
        await _failTo('Microphone permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      _audioPath =
          '${dir.path}/vb_overlay_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _audioPath!,
      );
      await DebugLogService()
          .log('Overlay', 'Recorder started → $_audioPath');
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        final norm = ((amp.current + 45) / 45).clamp(0.1, 1.0);
        _targetLevel = norm.toDouble();
      });
    } catch (e) {
      await DebugLogService().log('Overlay', '_startRecording threw: $e');
      await _failTo('Could not start recording');
    }
  }

  Future<void> _stopAndProcess() async {
    if (_phase != _Phase.recording) return;
    HapticFeedback.lightImpact();
    setState(() => _phase = _Phase.polishing);
    try {
      await _ampSub?.cancel();
      _ampSub = null;
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) {
        await _failTo('No audio captured');
        return;
      }
      final file = File(path);
      final rawTranscript = await _ai.transcribeAudio(file);
      if (rawTranscript.trim().isEmpty) {
        await _failTo('No speech detected');
        return;
      }

      // If the user typed a custom steering instruction, prepend it to
      // the transcript so the magic preset uses it as guidance.
      final transcript = (_customInstruction != null &&
              _customInstruction!.isNotEmpty)
          ? '[Instruction: ${_customInstruction!}]\n$rawTranscript'
          : rawTranscript;

      String resultText;
      String? intentLabel;
      if (_activePresetId == 'magic') {
        final magic =
            await _ai.rewriteMagic(text: transcript, languageCode: 'en');
        resultText = magic.text.isNotEmpty ? magic.text : rawTranscript;
        intentLabel = magic.label ?? (_customInstruction != null ? 'Custom' : null);
      } else {
        final preset = _presetForId(_activePresetId);
        final rewritten =
            await _ai.rewriteText(transcript, preset, 'en');
        resultText = rewritten.isNotEmpty ? rewritten : rawTranscript;
        intentLabel = preset.name;
      }

      if (!mounted) return;
      setState(() {
        _resultText = resultText;
        _intentLabel = intentLabel;
        _phase = _Phase.result;
      });
      HapticFeedback.selectionClick();
      _enterCtrl
        ..reset()
        ..forward();
    } catch (_) {
      await _failTo('Polish failed — try again');
    }
  }

  /// Build a Preset object on the fly to hand to AIService.rewriteText.
  /// Only `id` matters server-side — name is just for the result label.
  Preset _presetForId(String id) {
    final quick = _kQuickPresets.firstWhere(
      (p) => p.id == id,
      orElse: () => _kQuickPresets.first,
    );
    return Preset(
      id: quick.id,
      icon: quick.icon,
      name: quick.label,
      description: '',
      category: '',
    );
  }

  Future<void> _retryRecording() async {
    HapticFeedback.lightImpact();
    setState(() {
      _phase = _Phase.recording;
      _resultText = '';
      _intentLabel = null;
      _errorMessage = '';
      for (int i = 0; i < _wave.length; i++) {
        _wave[i] = 0.18;
      }
    });
    await _startRecording();
  }

  Future<void> _cancel() async {
    HapticFeedback.selectionClick();
    try {
      await _ampSub?.cancel();
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    await FlutterOverlayWindow.closeOverlay();
  }

  // ───────── Insert / Copy ─────────

  Future<void> _insertOrCopy() async {
    if (_resultText.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _phase = _Phase.inserting);

    final ok = await TextInjectionService.injectText(_resultText);
    await DebugLogService()
        .log('Overlay', 'Insert tapped — injectText returned $ok');
    if (!ok) {
      // Fallback: clipboard. The user can paste manually wherever they want.
      await Clipboard.setData(ClipboardData(text: _resultText));
      await DebugLogService()
          .log('Overlay', 'Fell back to clipboard.setData');
    }
    // Brief breath so the user sees the transition land, then close.
    await Future.delayed(const Duration(milliseconds: 180));
    await FlutterOverlayWindow.closeOverlay();
    await DebugLogService().log('Overlay', 'Overlay closed after insert/copy');
  }

  Future<void> _failTo(String msg) async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = msg;
    });
  }

  // ───────── Wave animation tween ─────────

  void _animateWave() {
    setState(() {
      // Shift left, append new tip
      for (int i = 0; i < _wave.length - 1; i++) {
        _wave[i] = _wave[i + 1];
      }
      final jitter = (Random().nextDouble() - 0.5) * 0.18;
      final next = (_targetLevel + jitter).clamp(0.12, 1.0);
      _wave[_wave.length - 1] = next;
    });
  }

  // ───────── Build ─────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tapping the empty area outside the pill cancels and dismisses.
      onTap: _cancel,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          children: [
            // Soft dimmer behind so the pill pops without nuking visibility
            // of the underlying app.
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _phase == _Phase.recording ? 0.18 : 0.32,
                duration: const Duration(milliseconds: 200),
                child: Container(color: Colors.black),
              ),
            ),
            Center(
              child: GestureDetector(
                // Absorb taps inside the pill so they don't dismiss.
                onTap: () {},
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_phase),
                    child: _buildForPhase(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForPhase() {
    switch (_phase) {
      case _Phase.presetSelection:
        return _PresetFanPill(
          presets: _kQuickPresets,
          onSelect: _onPresetTap,
          onCancel: _cancel,
        );
      case _Phase.customInput:
        return _CustomInputPill(
          controller: _customCtrl,
          onSubmit: _submitCustomInstruction,
          onCancel: _cancel,
        );
      case _Phase.recording:
        return _RecordingPill(
          wave: _wave,
          onStop: _stopAndProcess,
          onCancel: _cancel,
        );
      case _Phase.polishing:
        return _PolishingPill(controller: _shimmerCtrl, onCancel: _cancel);
      case _Phase.result:
      case _Phase.inserting:
        return _ResultCard(
          text: _resultText,
          intentLabel: _intentLabel,
          inserting: _phase == _Phase.inserting,
          onInsert: _insertOrCopy,
          onRetry: _retryRecording,
          onCancel: _cancel,
        );
      case _Phase.error:
        return _ErrorPill(
          message: _errorMessage,
          onRetry: _retryRecording,
          onCancel: _cancel,
        );
    }
  }
}

// ───────────────────── Preset fan pill ─────────────────────

class _PresetFanPill extends StatelessWidget {
  final List<_QuickPreset> presets;
  final ValueChanged<_QuickPreset> onSelect;
  final VoidCallback onCancel;
  const _PresetFanPill({
    required this.presets,
    required this.onSelect,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 4),
                const Text(
                  'CHOOSE A STYLE',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                _ChipIcon(icon: Icons.close_rounded, onTap: onCancel),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal row of preset chips with a tiny stagger so they
            // appear to fan in.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(presets.length, (i) {
                final p = presets[i];
                return _PresetChip(
                  preset: p,
                  delayMs: i * 35,
                  onTap: () => onSelect(p),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatefulWidget {
  final _QuickPreset preset;
  final int delayMs;
  final VoidCallback onTap;
  const _PresetChip({
    required this.preset,
    required this.delayMs,
    required this.onTap,
  });

  @override
  State<_PresetChip> createState() => _PresetChipState();
}

class _PresetChipState extends State<_PresetChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
      ),
      child: FadeTransition(
        opacity: _ctrl,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: widget.onTap,
            radius: 36,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kBrandPurple.withOpacity(0.15),
                    border: Border.all(
                      color: _kBrandPurple.withOpacity(0.45),
                      width: 1,
                    ),
                  ),
                  child:
                      Icon(widget.preset.icon, color: _kBrandPurple, size: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.preset.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────── Custom instruction pill ─────────────────────

class _CustomInputPill extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  const _CustomInputPill({
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        child: Row(
          children: [
            const Icon(Icons.edit_rounded, color: _kBrandPurple, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: _kBrandPurple,
                decoration: const InputDecoration(
                  hintText: 'shorter / formal / translate to spanish…',
                  hintStyle: TextStyle(color: Color(0xFF60607A), fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => onSubmit(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSubmit,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBrandPurple,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 6),
            _ChipIcon(icon: Icons.close_rounded, onTap: onCancel),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── Recording pill ─────────────────────

class _RecordingPill extends StatelessWidget {
  final List<double> wave;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  const _RecordingPill({
    required this.wave,
    required this.onStop,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        child: Row(
          children: [
            // Live waveform
            Expanded(
              child: SizedBox(
                height: 44,
                child: CustomPaint(
                  painter: _WavePainter(wave: wave, color: _kBrandPurple),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Stop button (primary action — tap to finish)
            GestureDetector(
              onTap: onStop,
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBrandPurple,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x667C6AE8),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(Icons.stop_rounded,
                    color: Colors.white, size: 26),
              ),
            ),
            const SizedBox(width: 8),
            // Cancel
            _ChipIcon(icon: Icons.close_rounded, onTap: onCancel),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── Polishing pill ─────────────────────

class _PolishingPill extends StatelessWidget {
  final AnimationController controller;
  final VoidCallback onCancel;
  const _PolishingPill({required this.controller, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => CustomPaint(
                    painter: _ShimmerLinePainter(t: controller.value),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const SizedBox(
              width: 52,
              height: 52,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(_kBrandPurple),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ChipIcon(icon: Icons.close_rounded, onTap: onCancel),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── Result card ─────────────────────

class _ResultCard extends StatelessWidget {
  final String text;
  final String? intentLabel;
  final bool inserting;
  final VoidCallback onInsert;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  const _ResultCard({
    required this.text,
    required this.intentLabel,
    required this.inserting,
    required this.onInsert,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Intent badge row
            Row(
              children: [
                if (intentLabel != null && intentLabel!.isNotEmpty)
                  Text(
                    intentLabel!.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                const Spacer(),
                _ChipIcon(icon: Icons.close_rounded, onTap: onCancel),
              ],
            ),
            const SizedBox(height: 10),
            // Result text
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 92),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _SecondaryButton(
                  icon: Icons.refresh_rounded,
                  label: 'Retry',
                  onTap: inserting ? null : onRetry,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PrimaryInsertButton(
                    label: inserting ? 'Inserting…' : 'Insert',
                    onTap: inserting ? null : onInsert,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── Error pill ─────────────────────

class _ErrorPill extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  const _ErrorPill({
    required this.message,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: _kDangerRed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            _SecondaryButton(
              icon: Icons.refresh_rounded,
              label: 'Retry',
              onTap: onRetry,
            ),
            const SizedBox(width: 6),
            _ChipIcon(icon: Icons.close_rounded, onTap: onCancel),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── Building blocks ─────────────────────

class _GlassPill extends StatelessWidget {
  final Widget child;
  const _GlassPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kPillRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kPillRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: _kSurface.withOpacity(0.78),
              borderRadius: BorderRadius.circular(_kPillRadius),
              border: Border.all(
                color: Colors.white.withOpacity(0.06),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ChipIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ChipIcon({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white.withOpacity(0.85), size: 18),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SecondaryButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(disabled ? 0.04 : 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: Colors.white.withOpacity(disabled ? 0.4 : 0.85),
                  size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(disabled ? 0.4 : 0.92),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryInsertButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PrimaryInsertButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: disabled
                  ? const [Color(0xFF4A4564), Color(0xFF3A364E)]
                  : const [_kBrandPurple, Color(0xFF6253D6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: disabled
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x667C6AE8),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────── Painters ─────────────────────

class _WavePainter extends CustomPainter {
  final List<double> wave;
  final Color color;
  _WavePainter({required this.wave, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final n = wave.length;
    final barW = size.width / (n * 1.6);
    final gap = (size.width - barW * n) / (n - 1);
    for (int i = 0; i < n; i++) {
      final h = wave[i] * size.height;
      final x = i * (barW + gap);
      final rect = Rect.fromLTWH(
        x,
        (size.height - h) / 2,
        barW,
        h,
      );
      final p = Paint()
        ..color = color.withOpacity(0.55 + 0.45 * (i / n))
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barW / 2)),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

class _ShimmerLinePainter extends CustomPainter {
  final double t;
  _ShimmerLinePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // Three placeholder lines with a moving highlight sweep.
    const lineHeight = 8.0;
    const gap = 8.0;
    const totalHeight = lineHeight * 3 + gap * 2;
    final startY = (size.height - totalHeight) / 2;
    final widths = <double>[size.width, size.width * 0.78, size.width * 0.55];
    for (int i = 0; i < 3; i++) {
      final y = startY + i * (lineHeight + gap);
      final rect = Rect.fromLTWH(0, y, widths[i], lineHeight);
      final base = Paint()..color = Colors.white.withOpacity(0.08);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(lineHeight / 2)),
        base,
      );
      // Sweep highlight
      final sweepX = -widths[i] + 2 * widths[i] * t;
      final shader = LinearGradient(
        colors: [
          Colors.transparent,
          _kBrandPurple.withOpacity(0.45),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(sweepX - 60, y, 120, lineHeight));
      final hl = Paint()..shader = shader;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(lineHeight / 2)),
        hl,
      );
    }
  }

  @override
  bool shouldRepaint(_ShimmerLinePainter old) => old.t != t;
}
