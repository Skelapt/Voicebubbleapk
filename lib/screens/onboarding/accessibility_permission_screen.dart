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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                children: [
                  // Top bar: back / dismiss
                  Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: widget.onComplete,
                        style: TextButton.styleFrom(
                          foregroundColor: textSecondary,
                        ),
                        child: const Text(
                          'Not now',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Hero icon
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: _granted
                        ? _GrantedHero()
                        : _IdleHero(purple: purple),
                  ),
                  const SizedBox(height: 36),

                  // Headline
                  Text(
                    _granted ? 'You\'re ready' : 'One last switch',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _granted
                        ? 'The bubble can now drop AI replies straight into any app you\'re typing in.'
                        : 'Enable the Accessibility Service so the bubble can paste your AI-rewritten text into the app you\'re typing in.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: textSecondary,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // PROMINENT DISCLOSURE — required by Google Play's
                  // Accessibility API + User Data policies. Uses Google's
                  // recommended format verbatim:
                  //   "[App] accesses [data] to enable [feature], [when]."
                  // Names the Accessibility Service explicitly, states
                  // exactly what is accessed, how it's used, and that
                  // nothing else is collected/stored/shared. Shown in the
                  // normal onboarding flow, immediately before the consent
                  // action — not buried in a menu or the privacy policy.
                  if (!_granted)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: purple.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.lock_outline,
                                color: purple, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'How VoiceBubble uses the Accessibility Service',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'VoiceBubble uses the Accessibility Service to detect the '
                                  'text field you have selected and to insert your '
                                  'AI-rewritten text into it — only at the moment you tap '
                                  '“Insert”. VoiceBubble does not read, collect, store, or '
                                  'share any other content from the apps you use. The '
                                  'service is never used in the background.',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),

                  // Steps preview — sets expectation for what the next
                  // tap actually opens, so the system Accessibility
                  // screen doesn't feel like a bait-and-switch.
                  if (!_granted && !_waitingForGrant)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _StepRow(
                            num: '1',
                            text: 'Tap "Agree & enable" — opens system settings'),
                        SizedBox(height: 10),
                        _StepRow(
                            num: '2',
                            text: 'Find VoiceBubble, turn the toggle ON'),
                        SizedBox(height: 10),
                        _StepRow(
                            num: '3',
                            text: 'Press back — the bubble is ready'),
                      ],
                    ),

                  if (_waitingForGrant && !_granted)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(purple),
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

                  const SizedBox(height: 24),

                  // Primary CTA
                  if (!_granted)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _waitingForGrant ? null : _openSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: purple,
                          disabledBackgroundColor:
                              purple.withOpacity(0.4),
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
                              : 'Agree & enable Accessibility',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
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

class _StepRow extends StatelessWidget {
  final String num;
  final String text;
  const _StepRow({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF7C6AE8).withOpacity(0.18),
            shape: BoxShape.circle,
          ),
          child: Text(
            num,
            style: const TextStyle(
              color: Color(0xFF7C6AE8),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
