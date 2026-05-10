import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/native_overlay_service.dart';

/// Single-screen onboarding focused on the one mission of the app:
/// activate the floating bubble and use it once.
///
/// Layout:
///   • Breathing brand bubble icon up top
///   • "Your AI in every app" headline
///   • Cross-fading example sentences ("I'm running late — text it
///     properly", etc.) so the user pictures themselves using it
///     before they tap anything
///   • Primary CTA: "Activate VoiceBubble" — guides them through the
///     mic + overlay permission flow, starts the bubble service,
///     and only then advances. The 5-minute free reward is tied
///     to first-tap of the bubble (granted natively when they
///     record), not to clicking this button — so the gift can't
///     be cashed without using the actual feature.
///   • Secondary link: "Use voice in the app instead" — requests
///     mic only, skips the bubble entirely. Available but quiet.
///
/// On resume from the system overlay settings, the screen polls
/// permission state and auto-advances the moment the user grants.
class ActivateBubbleScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const ActivateBubbleScreen({super.key, required this.onComplete});

  @override
  State<ActivateBubbleScreen> createState() => _ActivateBubbleScreenState();
}

class _ActivateBubbleScreenState extends State<ActivateBubbleScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _purple = Color(0xFF7C6AE8);
  static const _surface = Color(0xFF0D0D1A);

  static const _examples = <String>[
    '"I\'m running late — text it properly"',
    '"I can\'t make it tonight — say it nicely"',
    '"Reply to mum, sound warm but quick"',
    '"Make this sound professional"',
    '"Just say what I mean — make it good"',
  ];

  int _exampleIndex = 0;
  Timer? _exampleTimer;
  late final AnimationController _bubblePulse;

  bool _waitingForOverlayGrant = false;
  Timer? _grantPoll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _exampleTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted) return;
      setState(() => _exampleIndex = (_exampleIndex + 1) % _examples.length);
    });
    _bubblePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exampleTimer?.cancel();
    _grantPoll?.cancel();
    _bubblePulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForOverlayGrant) {
      _checkOverlayGranted();
    }
  }

  // ───────── Activation flow ─────────

  Future<void> _activateBubble() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 1. Microphone permission (any path needs it).
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        if (mounted) _showSimpleSnack('Microphone access is required.');
        return;
      }

      if (!Platform.isAndroid) {
        // iOS later — for now treat it as voice-only finish.
        widget.onComplete();
        return;
      }

      // 2. Overlay permission — opens system settings if not granted.
      final hasOverlay = await NativeOverlayService.checkPermission();
      if (!hasOverlay) {
        await NativeOverlayService.requestPermission();
        // Switch to "waiting" state — lifecycle observer + poll will
        // pick up the moment the user flips the toggle.
        if (mounted) {
          setState(() => _waitingForOverlayGrant = true);
        }
        _startGrantPoll();
        return;
      }

      // Already had it — start the bubble and finish.
      await _startBubbleAndFinish();
    } finally {
      if (mounted && !_waitingForOverlayGrant) {
        setState(() => _busy = false);
      }
    }
  }

  void _startGrantPoll() {
    _grantPoll?.cancel();
    int tries = 0;
    _grantPoll = Timer.periodic(const Duration(milliseconds: 600), (t) async {
      tries += 1;
      final ok = await NativeOverlayService.checkPermission();
      if (ok && mounted) {
        t.cancel();
        await _startBubbleAndFinish();
      } else if (tries >= 30) {
        // ~18s — give up the auto-detect, user can re-tap activate.
        t.cancel();
        if (mounted) {
          setState(() {
            _waitingForOverlayGrant = false;
            _busy = false;
          });
        }
      }
    });
  }

  Future<void> _checkOverlayGranted() async {
    final ok = await NativeOverlayService.checkPermission();
    if (ok && mounted) {
      _grantPoll?.cancel();
      await _startBubbleAndFinish();
    }
  }

  Future<void> _startBubbleAndFinish() async {
    final started = await NativeOverlayService.showOverlay();
    if (mounted) {
      setState(() {
        _waitingForOverlayGrant = false;
        _busy = false;
      });
      if (started) {
        widget.onComplete();
      } else {
        _showSimpleSnack('Could not start the bubble. Try again.');
      }
    }
  }

  Future<void> _voiceOnlyPath() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        if (mounted) _showSimpleSnack('Microphone access is required.');
        return;
      }
      widget.onComplete();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSimpleSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: _surface,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ───────── Build ─────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(
            children: [
              const Spacer(flex: 2),
              _buildHero(),
              const SizedBox(height: 32),
              _buildHeadline(),
              const SizedBox(height: 12),
              _buildSubhead(),
              const SizedBox(height: 28),
              _buildExamples(),
              const Spacer(flex: 3),
              _buildRewardPill(),
              const SizedBox(height: 14),
              _buildPrimaryCta(),
              const SizedBox(height: 10),
              _buildSecondaryLink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return AnimatedBuilder(
      animation: _bubblePulse,
      builder: (_, __) {
        final t = _bubblePulse.value;
        final scale = 0.96 + 0.04 * t;
        final glow = 0.30 + 0.20 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_purple, Color(0xFF6253D6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _purple.withOpacity(glow),
                  blurRadius: 38,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: const Icon(
              Icons.mic_rounded,
              size: 60,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeadline() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        'Your AI in every app',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          height: 1.15,
        ),
      ),
    );
  }

  Widget _buildSubhead() {
    return Text(
      'Tap the floating bubble in WhatsApp, Gmail, anywhere — speak, and it pastes a perfect message at your cursor.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withOpacity(0.62),
        fontSize: 14,
        height: 1.5,
      ),
    );
  }

  Widget _buildExamples() {
    return SizedBox(
      height: 24,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          _examples[_exampleIndex],
          key: ValueKey(_exampleIndex),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontStyle: FontStyle.italic,
            color: Colors.white.withOpacity(0.45),
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildRewardPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _purple.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: _purple.withOpacity(0.35), width: 1),
      ),
      child: const Text(
        '🎁  5 free minutes when you first tap the bubble',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _buildPrimaryCta() {
    final waiting = _waitingForOverlayGrant;
    final disabled = _busy && !waiting;
    final label = waiting
        ? 'Waiting for permission…'
        : (_busy ? 'Working…' : 'Activate VoiceBubble');
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: disabled || waiting ? null : _activateBubble,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: disabled || waiting
                  ? const [Color(0xFF4A4564), Color(0xFF3A364E)]
                  : const [_purple, Color(0xFF6253D6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: disabled || waiting
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x66_7C6AE8),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!waiting && !_busy)
                const Icon(Icons.bubble_chart_rounded,
                    color: Colors.white, size: 22),
              if (!waiting && !_busy) const SizedBox(width: 10),
              if (waiting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              if (waiting) const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryLink() {
    return TextButton(
      onPressed: _busy ? null : _voiceOnlyPath,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withOpacity(0.55),
      ),
      child: const Text(
        'Use voice in the app instead',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
