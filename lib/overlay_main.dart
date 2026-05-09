import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'services/ai_service.dart';
import 'services/text_injection_service.dart';

/// Entry point for the floating recording overlay isolate. Spun up
/// by `flutter_overlay_window` whenever the bubble is tapped.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
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

enum _Phase { recording, polishing, result, inserting, error }

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

    _startRecording();
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _recorder.dispose();
    _shimmerCtrl.dispose();
    _waveCtrl.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  // ───────── Recording ─────────

  Future<void> _startRecording() async {
    HapticFeedback.lightImpact();
    try {
      if (!await _recorder.hasPermission()) {
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
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        // amp.current is roughly -45..0 dBFS. Map to 0.1..1.0.
        final norm = ((amp.current + 45) / 45).clamp(0.1, 1.0);
        _targetLevel = norm.toDouble();
      });
    } catch (e) {
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
      final transcript = await _ai.transcribeAudio(file);
      if (transcript.trim().isEmpty) {
        await _failTo('No speech detected');
        return;
      }
      final magic =
          await _ai.rewriteMagic(text: transcript, languageCode: 'en');
      if (!mounted) return;
      setState(() {
        _resultText = magic.text.isNotEmpty ? magic.text : transcript;
        _intentLabel = magic.label;
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
    if (!ok) {
      // Fallback: clipboard. The user can paste manually wherever they want.
      await Clipboard.setData(ClipboardData(text: _resultText));
    }
    // Brief breath so the user sees the transition land, then close.
    await Future.delayed(const Duration(milliseconds: 180));
    await FlutterOverlayWindow.closeOverlay();
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
