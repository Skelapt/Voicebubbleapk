import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks STT and AI usage for free/pro limits.
///
/// Free model (NB-era):
///   • Zero standard free time. Nothing is given just for installing.
///   • The user UNLOCKS 5 minutes the FIRST time they record via the
///     floating bubble. The single-mission goal of the app is to get
///     them to activate the bubble and use it once — the reward
///     arrives at exactly that moment so the gift can't be cashed
///     without the activation.
///   • Reviewing the app on Play unlocks +1 min on top.
///   • Pro = unlimited.
///
/// Why the bubble-only reward:
///   The previous "free 10 min just for opening the app" tier wasn't
///   converting because heavy users could exhaust their need inside
///   the free tier without ever feeling the value of the bubble. Now
///   minutes only exist if you've felt the bubble's "speak in any
///   app" magic — every minute of free usage is also a minute of
///   reinforcement on the upgrade path.
class UsageService {
  static const String _boxName = 'usage_data';

  /// Standard free seconds with no action — zero. The user must
  /// activate AND use the bubble to unlock anything.
  static const int freeSecondsLimit = 0;

  /// Unlimited for Pro.
  static const int proSecondsLimit = 999999;

  /// Bonus added when the user leaves a review — one minute on top.
  static const int reviewBonusSeconds = 60;

  /// Bonus unlocked the first time the user records VIA the floating
  /// bubble (not from inside the main app). 5 minutes — enough to
  /// taste the value, not so much that the wall feels arbitrary.
  static const int bubbleFirstUseBonusSeconds = 300;

  /// Deprecated: kept at zero for backward compat with any code that
  /// still references the old "onboarding bonus" name.
  static const int onboardingBonusSeconds = 0;

  // SharedPreferences key written by either the Dart side or by
  // native code (OverlayService.kt) the moment the user first taps
  // record via the bubble. Picked up here on the next read of
  // [hasClaimedBubbleFirstUseBonus].
  static const String _bubbleBonusPrefsKey = 'flutter.bubble_first_use_bonus_claimed';

  // Singleton
  static final UsageService _instance = UsageService._internal();
  factory UsageService() => _instance;
  UsageService._internal();

  /// Get total seconds used this month
  Future<int> getSecondsUsed() async {
    final box = await Hive.openBox(_boxName);
    final monthKey = _getCurrentMonthKey();
    return box.get('stt_seconds_$monthKey', defaultValue: 0);
  }

  /// Add seconds to usage (call after recording/export)
  Future<void> addUsage(int seconds) async {
    final box = await Hive.openBox(_boxName);
    final monthKey = _getCurrentMonthKey();
    final current = box.get('stt_seconds_$monthKey', defaultValue: 0);
    await box.put('stt_seconds_$monthKey', current + seconds);
  }

  /// Check if user can use STT/AI
  Future<bool> canUseSTT({required bool isPro}) async {
    final used = await getSecondsUsed();
    final limit = await getTotalLimit(isPro: isPro);
    return used < limit;
  }

  /// Get remaining seconds
  Future<int> getRemainingSeconds({required bool isPro}) async {
    final used = await getSecondsUsed();
    final limit = await getTotalLimit(isPro: isPro);
    return (limit - used).clamp(0, limit);
  }

  /// Get total limit including bonuses
  Future<int> getTotalLimit({required bool isPro}) async {
    if (isPro) return proSecondsLimit;

    final hasReviewBonus = await hasClaimedReviewBonus();
    final hasBubbleBonus = await hasClaimedBubbleFirstUseBonus();
    return freeSecondsLimit
        + (hasReviewBonus ? reviewBonusSeconds : 0)
        + (hasBubbleBonus ? bubbleFirstUseBonusSeconds : 0);
  }

  /// Check if review bonus has been claimed
  Future<bool> hasClaimedReviewBonus() async {
    final box = await Hive.openBox(_boxName);
    return box.get('review_bonus_claimed', defaultValue: false);
  }

  /// Claim the review bonus (adds 1 minute). Returns true if successfully claimed, false if already claimed.
  Future<bool> claimReviewBonus() async {
    final box = await Hive.openBox(_boxName);
    final alreadyClaimed = box.get('review_bonus_claimed', defaultValue: false);
    if (alreadyClaimed) return false;
    await box.put('review_bonus_claimed', true);
    return true;
  }

  /// Has the user already unlocked the 5-minute first-bubble-use bonus?
  /// Native (OverlayService.kt) writes this flag the moment the user
  /// taps record via the bubble for the first time, so the limit
  /// updates immediately.
  Future<bool> hasClaimedBubbleFirstUseBonus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Stored under the FlutterSharedPreferences-style key name (the
      // Dart plugin strips the "flutter." prefix on read so we use the
      // plain key here).
      return prefs.getBool('bubble_first_use_bonus_claimed') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Claim the bubble-first-use bonus (5 minutes). Returns true the
  /// first time, false on subsequent calls. Either Dart or native
  /// can call this — both end up flipping the same flag.
  Future<bool> claimBubbleFirstUseBonus() async {
    final prefs = await SharedPreferences.getInstance();
    final already = prefs.getBool('bubble_first_use_bonus_claimed') ?? false;
    if (already) return false;
    await prefs.setBool('bubble_first_use_bonus_claimed', true);
    return true;
  }

  /// Backwards-compat shim — older code paths still call this.
  /// Kept as a no-op (returns false) since the onboarding bonus has
  /// been removed; the native bubble flow now provides the gift.
  Future<bool> hasClaimedOnboardingBonus() async => false;

  /// Backwards-compat shim — calling this no longer grants minutes.
  Future<bool> claimOnboardingBonus() async => false;

  /// Should we prompt for review? (after using 3+ minutes, and not yet claimed)
  Future<bool> shouldShowReviewPrompt({required bool isPro}) async {
    if (isPro) return false;
    final claimed = await hasClaimedReviewBonus();
    if (claimed) return false;
    final used = await getSecondsUsed();
    return used >= 180; // After 3 minutes of use
  }

  /// Format seconds as "Xm Ys"
  String formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }
    return '${secs}s';
  }

  /// Get the current month key (e.g., "2026_2" for February 2026)
  String _getCurrentMonthKey() {
    final now = DateTime.now();
    return '${now.year}_${now.month}';
  }
}
