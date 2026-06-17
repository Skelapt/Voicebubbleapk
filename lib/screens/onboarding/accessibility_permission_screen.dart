import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/text_injection_service.dart';

/// One-screen explainer + grant flow for the Android Accessibility
/// permission. Without this enabled, the bubble's Insert button falls
/// back to clipboard (still works, just one extra paste). With it on,
/// AI text lands directly at the user's cursor in any app.
///
/// This screen is the formal, in-product prominent disclosure
/// required by Google Play's "Use of the AccessibilityService API"
/// policy. It is reachable in normal usage as part of the standard
/// onboarding flow — not gated behind a feature — and it covers, on
/// the same screen, BEFORE any consent button:
///
///   1. The single feature the Accessibility API enables
///      (one-tap in-place text insertion into the focused EditText
///      of any other app).
///   2. Why that feature genuinely requires the Accessibility API
///      and not a less-privileged alternative.
///   3. The exact scope and limits of what the service does (only
///      at the moment the user taps Insert; never in the background;
///      never read/log/transmit/share content from other apps).
///   4. What data is collected and how it's used: NONE. The Insert
///      action sends text into the focused field locally; no
///      Accessibility event content is sent off the device.
///   5. The user's control: deny, skip, or revoke at any time;
///      denial is treated as a non-consent and the bubble falls back
///      to clipboard.
///   6. A direct pointer to the in-app privacy policy and to the
///      Play Store listing's Data safety section, which restate the
///      same disclosure verbatim.
class AccessibilityPermissionScreen extends StatefulWidget {
  /// Called when permission is granted (auto-detected on resume) OR when
  /// the user dismisses the screen with "Skip for now". The caller
  /// decides what to do — usually just pop and carry on.
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
                          const SizedBox(height: 8),
                          Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                      scale: animation, child: child),
                              child: _granted
                                  ? const _GrantedHero()
                                  : const _IdleHero(purple: purple),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _granted
                                ? 'You\'re ready'
                                : 'How VoiceBubble uses the Accessibility Service API',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _granted
                                ? 'The Accessibility Service can now place text at your cursor in any app.'
                                : 'Please read this disclosure before you decide.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textSecondary,
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),

                          if (!_granted) ...[
                            // ── HEADLINE DATA-USE STATEMENT ──
                            // Tight, Accessibility-only. No references
                            // to microphone, AI, or any other feature —
                            // those have their OWN disclosures at their
                            // OWN permission prompts. Bundling them
                            // here is a documented Play policy flag:
                            // "Cannot be included with other disclosures
                            // unrelated to personal and sensitive user
                            // data collection."
                            _DataUseStatement(),
                            const SizedBox(height: 14),

                            // Three cards — every line below is about
                            // the Accessibility Service API and nothing
                            // else. Microphone and AI use have their
                            // own permission prompts and their own
                            // disclosure screens elsewhere in the app.
                            _DisclosureItem(
                              icon: Icons.touch_app_rounded,
                              title:
                                  'The feature the Accessibility Service enables',
                              body:
                                  'A single in-app action: an “Insert” button '
                                  'inside VoiceBubble. When you tap Insert, the '
                                  'Accessibility Service identifies the text '
                                  'field you have focused in any other app — '
                                  'WhatsApp\'s message box, Gmail\'s compose, '
                                  'Messages, Slack, X/Twitter reply, LinkedIn, '
                                  'Notes, or any editable input — and writes '
                                  'text from VoiceBubble into that field at '
                                  'your cursor. That is the only thing the '
                                  'Accessibility Service is used for in this '
                                  'app.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.shield_outlined,
                              title:
                                  'What the Service reads — and does not read',
                              body:
                                  'Only at the exact moment you tap Insert, '
                                  'the Service reads ONE AccessibilityNodeInfo '
                                  '— the descriptor of the focused text field '
                                  '— purely to write text into it. It does NOT '
                                  'read that field\'s existing contents, other '
                                  'fields, screen contents, notifications, or '
                                  'any UI tree. It does NOT run in the '
                                  'background, start at boot, log, store, '
                                  'transmit, sell, or share anything. It is '
                                  'NOT used for click automation, ad-blocking, '
                                  'call recording, screen capture, password '
                                  'autofill, app-usage tracking, or any form '
                                  'of background surveillance. The Insert '
                                  'action is a local on-device operation — '
                                  'nothing the Accessibility Service touches '
                                  'leaves your device.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.person_outline_rounded,
                              title: 'Your control',
                              body:
                                  'Granting the Accessibility Service is '
                                  'fully optional. Tap “Skip for now” to '
                                  'proceed without it — VoiceBubble works '
                                  'without the Accessibility API. You can '
                                  'revoke the permission at any time from '
                                  'Android Settings → Accessibility → '
                                  'Installed services → VoiceBubble. The '
                                  'same disclosure is restated in our in-app '
                                  'Privacy Policy and in the Play Store '
                                  'listing\'s Data safety section.',
                            ),
                            const SizedBox(height: 12),
                            // Bold one-line confirmation directly above
                            // the affirmative-consent button so the act
                            // of granting is unambiguously voluntary.
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                'By tapping “I agree — enable Accessibility Service” '
                                'you consent to VoiceBubble using the Android '
                                'Accessibility Service API solely for the '
                                'one-tap text insertion described above.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFD1D5DB),
                                  fontSize: 12.5,
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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

                  const SizedBox(height: 12),

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
                          padding: const EdgeInsets.symmetric(vertical: 16),
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
                  const SizedBox(height: 4),
                  // Skip — declining is NOT treated as consent. Voice
                  // works without the Accessibility Service (falls back
                  // to clipboard).
                  if (!_granted)
                    TextButton(
                      onPressed: widget.onComplete,
                      style: TextButton.styleFrom(
                          foregroundColor: textSecondary),
                      child: const Text(
                        'Skip for now — I do not consent',
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
      width: 112,
      height: 112,
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
            blurRadius: 32,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Icon(Icons.accessibility_new_rounded,
          size: 54, color: Colors.white),
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
      width: 112,
      height: 112,
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
            blurRadius: 32,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, size: 60, color: Colors.white),
    );
  }
}

/// One-sentence core-purpose statement, rendered as a high-contrast
/// banner above the breakdown. This is the canonical answer to Google
/// Play's required "what is your app's core purpose for using the
/// Accessibility API?" question.
/// Headline data-use statement, written in the EXACT template Google
/// Play's "Best practices for prominent disclosure and consent" article
/// recommends for sensitive-API disclosures:
///
///   "[This app] collects/transmits/syncs/stores [type of data] to
///   enable [feature], [in what scenario]."
///
/// We intentionally lift each clause from that template so a reviewer
/// can map them one-to-one against the policy.
class _DataUseStatement extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF34C759);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: green.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: green.withOpacity(0.55), width: 1.5),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  color: green, size: 18),
              SizedBox(width: 8),
              Text(
                'How VoiceBubble uses the Accessibility API',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'VoiceBubble accesses one piece of data through the '
            'Accessibility Service API: the descriptor of the text '
            'field you currently have focused in another app. It uses '
            'that descriptor to write text from VoiceBubble into that '
            'field, to enable one-tap text insertion at your cursor, '
            'only at the exact moment you tap the “Insert” button in '
            'VoiceBubble.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'VoiceBubble does not collect, transmit, sync, store, sell, '
            'or share any data accessed through the Accessibility '
            'Service API. The action runs on-device and stops the '
            'instant the text is inserted.',
            style: TextStyle(
              color: Color(0xFFD1D5DB),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
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
    const textSecondary = Color(0xFFC2C8D6);
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
                    height: 1.5,
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
