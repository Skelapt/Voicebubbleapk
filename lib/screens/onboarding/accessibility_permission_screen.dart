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
                                : 'Accessibility permission',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _granted
                                ? 'The bubble can now drop AI replies straight into any app you\'re typing in.'
                                : 'VoiceBubble uses Android\'s Accessibility API for one specific reason. Please read this disclosure in full before you decide.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textSecondary,
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),

                          if (!_granted) ...[
                            // ── HEADLINE CORE-PURPOSE STATEMENT ──
                            // The Accessibility API policy is "the
                            // requested permissions must be needed to
                            // provide the core purpose of the app or
                            // service". This banner is the single,
                            // one-sentence core-purpose statement,
                            // verbatim — the rest of the screen
                            // elaborates on it.
                            _CorePurposeBanner(),
                            const SizedBox(height: 14),

                            _DisclosureItem(
                              icon: Icons.touch_app_rounded,
                              title: '1. The single feature this enables',
                              body:
                                  'After you record a voice note, the floating bubble shows '
                                  'an AI-polished version of your message in a small result '
                                  'panel. Tapping the “Insert” button on that panel uses '
                                  'the Accessibility API to identify the text field you '
                                  'currently have focused inside another app — for example '
                                  'WhatsApp\'s message box, Gmail\'s compose body, the '
                                  'Messages text input, Slack\'s reply box, the Twitter / X '
                                  'reply composer, the LinkedIn message field, the Notes '
                                  'app body — and writes the polished text into that exact '
                                  'field, at your cursor position, in one action. This is '
                                  'the only feature the Accessibility API is used for.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.bolt_rounded,
                              title:
                                  '2. Why this requires the Accessibility API',
                              body:
                                  'Android does not give a third-party app any other way to '
                                  'write text into another app\'s editable input field. The '
                                  'system clipboard is not equivalent — it requires the '
                                  'user to manually long-press, tap “Paste”, and '
                                  're-position the cursor, which defeats VoiceBubble\'s '
                                  'core purpose of a one-tap voice-to-text reply across '
                                  'any app. The standard Android share sheet only opens a '
                                  'NEW screen in the target app; it cannot inject into the '
                                  'composer the user is already typing into. An IME-based '
                                  'approach would require replacing the user\'s keyboard '
                                  'system-wide, which would intercept far more data and is '
                                  'a strictly worse privacy outcome. The Accessibility '
                                  'service\'s ACTION_SET_TEXT / ACTION_PASTE on the '
                                  'currently-focused EditText is the only API that allows '
                                  'in-place insertion at the cursor of an app the user is '
                                  'already inside.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.timer_outlined,
                              title: '3. Strict scope — only at Insert tap',
                              body:
                                  'The Accessibility service is invoked only at the exact '
                                  'moment you tap “Insert” on VoiceBubble\'s result panel. '
                                  'It does not run in the background. It does not start at '
                                  'boot. It does not listen to AccessibilityEvents from '
                                  'other apps when the panel is closed. It is not used to '
                                  'observe what you type, what you read, or which apps '
                                  'you open. Its onAccessibilityEvent callback is a no-op; '
                                  'the only path that touches another app\'s UI is the '
                                  'explicit user-initiated Insert action.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.shield_outlined,
                              title: '4. Data accessed — and not accessed',
                              body:
                                  'When you tap Insert, VoiceBubble briefly reads ONE '
                                  'AccessibilityNodeInfo — the descriptor of the currently '
                                  'focused EditText — so it can write your text into it. '
                                  'It does NOT read the existing contents of that field. '
                                  'It does NOT read any other field on the screen. It does '
                                  'NOT capture screen contents, take screenshots, record '
                                  'audio of other apps, read notifications, or scan UI '
                                  'trees. No AccessibilityEvent content is ever logged, '
                                  'stored on disk, transmitted, sold, or shared. The text '
                                  'that gets inserted is the AI-rewritten version of YOUR '
                                  'OWN voice recording — content you produced inside '
                                  'VoiceBubble, not anything read from another app.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.block_rounded,
                              title:
                                  '5. What the service is NOT used for',
                              body:
                                  'VoiceBubble\'s Accessibility service is not used for: '
                                  'click automation, gesture replay, ad-blocking, call '
                                  'recording, screen capture or recording, app usage '
                                  'analytics, banking-app data scraping, password '
                                  'auto-fill, scraping notifications, monitoring chats, '
                                  'tracking what apps you open, tracking your screen time, '
                                  'or any form of background surveillance. There is no '
                                  'code path for any of those behaviours; the service\'s '
                                  'manifest description, event handler, and Java/Kotlin '
                                  'source are limited to the one user-initiated Insert '
                                  'action described above.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.cloud_off_rounded,
                              title:
                                  '6. No off-device transmission via Accessibility',
                              body:
                                  'Nothing the Accessibility service touches leaves your '
                                  'device. The Insert action is a local OS call against '
                                  'the focused field on the same device. The only network '
                                  'traffic VoiceBubble generates is the audio you '
                                  'explicitly record being sent to our transcription / '
                                  'rewrite backend so the AI can turn your voice into '
                                  'polished text — and that path runs over HTTPS '
                                  'independently of the Accessibility API. The '
                                  'Accessibility API itself never originates network '
                                  'traffic in this app.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.person_outline_rounded,
                              title:
                                  '7. Your control — grant, deny, or revoke',
                              body:
                                  'Granting Accessibility is fully optional. Tapping '
                                  '“Skip for now” below proceeds without it; VoiceBubble '
                                  'still works — the bubble copies the AI text to your '
                                  'clipboard and you paste it manually. After granting, '
                                  'you can revoke at any time from Android Settings → '
                                  'Accessibility → Installed services → VoiceBubble → '
                                  'turn off. Revoking immediately stops all use of the '
                                  'API; no future Insert action will succeed until you '
                                  're-enable it.',
                            ),
                            const SizedBox(height: 10),
                            _DisclosureItem(
                              icon: Icons.policy_outlined,
                              title:
                                  '8. Privacy policy and Data safety section',
                              body:
                                  'This same disclosure is restated verbatim in our '
                                  'in-app Privacy Policy (Settings → About → Privacy '
                                  'Policy) and in the Play Store listing\'s Data safety '
                                  'section. The Data safety section discloses that '
                                  'VoiceBubble: does not sell user data; does not share '
                                  'Accessibility data with any third party; collects no '
                                  'data via the Accessibility API; and uses the '
                                  'Accessibility API solely for one-tap text insertion '
                                  'as described above.',
                            ),
                            const SizedBox(height: 12),
                            // Bold one-line confirmation directly above
                            // the affirmative-consent button so the act
                            // of granting is unambiguously voluntary.
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                'By tapping “I agree — enable Accessibility”, you confirm '
                                'you have read this disclosure and consent to VoiceBubble '
                                'using Android\'s Accessibility API solely for the '
                                'one-tap in-place text insertion described above.',
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
class _CorePurposeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final purple = const Color(0xFF7C6AE8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            purple.withOpacity(0.18),
            const Color(0xFF6253D6).withOpacity(0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: purple.withOpacity(0.45), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: purple, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Core purpose: VoiceBubble uses the Android Accessibility '
              'API solely so that, when you tap “Insert” on the floating '
              'bubble\'s result panel, your AI-polished voice message is '
              'written directly into the focused text field of the app '
              'you\'re already typing in — one tap, at your cursor, no '
              'manual paste. That is the only thing the Accessibility '
              'API is used for.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
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
