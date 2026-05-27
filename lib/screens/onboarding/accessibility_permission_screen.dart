import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/text_injection_service.dart';

/// One-screen explainer + grant flow for the Android Accessibility
/// permission. Without this enabled, the bubble's Insert button falls
/// back to clipboard (still works, just one extra paste). With it on,
/// AI text lands directly at the user's cursor in any app.
///
/// Show this once, after the user has activated the bubble. We listen
/// for app resume and auto-detect when the toggle gets flipped in
/// system settings — no need for the user to come back and tap again.
class AccessibilityPermissionScreen extends StatefulWidget {
  /// Called when permission is granted (auto-detected on resume) OR when
  /// the user dismisses the screen with "Not now". The caller decides
  /// what to do — usually just pop and carry on.
  final VoidCallback onComplete;
  const AccessibilityPermissionScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<AccessibilityPermissionScreen> createState() =>
      _AccessibilityPermissionScreenState();
}

class _AccessibilityPermissionScreenState
    extends State<AccessibilityPermissionScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _waitingForGrant = false;
  bool _granted = false;
  Timer? _pollTimer;
  late final AnimationController _enterCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _enterCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForGrant) {
      _checkGrantedSoon();
    }
  }

  /// After the user comes back from the system Accessibility settings,
  /// the OS sometimes takes a beat before reporting the new state. Poll
  /// a few times so the success animation lands without the user having
  /// to do anything else.
  void _checkGrantedSoon() {
    _pollTimer?.cancel();
    int tries = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 350), (t) async {
      tries += 1;
      final ok = await TextInjectionService.isEnabled();
      if (ok && mounted) {
        t.cancel();
        setState(() => _granted = true);
        // Brief celebration breath, then close.
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) widget.onComplete();
      } else if (tries >= 8) {
        t.cancel();
        if (mounted) setState(() => _waitingForGrant = false);
      }
    });
  }

  Future<void> _openSettings() async {
    setState(() => _waitingForGrant = true);
    await TextInjectionService.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C6AE8);
    const textPrimary = Colors.white;
    const textSecondary = Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _enterCtrl,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: _enterCtrl, curve: Curves.easeOutCubic)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                children: [
                  // Scrollable disclosure body so the full breakdown
                  // always fits, on any screen size, without overflow.
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                      scale: animation, child: child),
                              child: _granted
                                  ? _GrantedHero()
                                  : _IdleHero(purple: purple),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            _granted
                                ? 'You\'re ready'
                                : 'Enable Accessibility',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _granted
                                ? 'The bubble can now drop AI replies straight into any app you\'re typing in.'
                                : 'VoiceBubble needs Android\'s Accessibility Service to work. Here is exactly what it does.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textSecondary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── DEDICATED ACCESSIBILITY DISCLOSURE ──
                          // Google Play's Accessibility API policy requires
                          // a SEPARATE disclosure specifically for the
                          // AccessibilityService — it must NOT be bundled
                          // with unrelated data disclosures (mic, overlay,
                          // AI, etc., which are disclosed on their own
                          // screens / at their own permission prompts).
                          // This screen is ONLY about the AccessibilityService:
                          // why it's needed (core purpose), what data it
                          // accesses, how it's used, and when.
                          if (!_granted) ...[
                            _DisclosureItem(
                              icon: Icons.touch_app_rounded,
                              title: 'What the Accessibility Service does',
                              body:
                                  'VoiceBubble uses the Accessibility Service to detect the '
                                  'text field you have selected in another app and to insert '
                                  'your AI-written text directly into it.',
                            ),
                            const SizedBox(height: 12),
                            _DisclosureItem(
                              icon: Icons.bolt_rounded,
                              title: 'Why VoiceBubble needs it',
                              body:
                                  'This is the app\'s core feature: pasting your finished '
                                  'message straight into WhatsApp, Gmail, or any app — so you '
                                  'never have to copy and paste manually.',
                            ),
                            const SizedBox(height: 12),
                            _DisclosureItem(
                              icon: Icons.lock_outline_rounded,
                              title: 'When it runs, and what it does NOT do',
                              body:
                                  'It only acts at the moment you tap “Insert”. It does NOT '
                                  'read, collect, store, log, or share any other content from '
                                  'the apps you use, and it never runs in the background.',
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ),

                  if (_waitingForGrant && !_granted)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(purple),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Waiting for you to flip the switch…',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 14),

                  // Primary affirmative consent → opens the system
                  // Accessibility settings.
                  if (!_granted)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _waitingForGrant ? null : _openSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: purple,
                          disabledBackgroundColor: purple.withOpacity(0.4),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _waitingForGrant
                              ? 'Open settings again'
                              : 'I agree — enable Accessibility',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  // Skip — declining is NOT treated as consent. Voice
                  // works without the Accessibility Service (falls back
                  // to clipboard).
                  if (!_granted)
                    TextButton(
                      onPressed: widget.onComplete,
                      style: TextButton.styleFrom(
                          foregroundColor: textSecondary),
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IdleHero extends StatelessWidget {
  final Color purple;
  const _IdleHero({required this.purple});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('idle'),
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [purple.withOpacity(0.95), const Color(0xFF6253D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: purple.withOpacity(0.55),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.auto_awesome_rounded,
          size: 60, color: Colors.white),
    );
  }
}

class _GrantedHero extends StatelessWidget {
  const _GrantedHero();

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10B981);
    return Container(
      key: const ValueKey('granted'),
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [green, Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: green.withOpacity(0.55),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, size: 70, color: Colors.white),
    );
  }
}

/// One row of the prominent-disclosure breakdown: an icon, a bold
/// capability title, and a plain-English explanation of what's
/// accessed and why.
class _DisclosureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _DisclosureItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF7C6AE8);
    const textPrimary = Colors.white;
    const textSecondary = Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: purple.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: purple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
