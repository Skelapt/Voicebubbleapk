import 'package:hive_flutter/hive_flutter.dart';

/// Tracks STT and AI usage for free/pro limits
/// FREE: 10 min standard every month (no button required).
/// Bonuses: 1 min review bonus.
/// PRO: Unlimited
class UsageService {
  static const String _boxName = 'usage_data';
  static const int freeSecondsLimit = 600;      // 10 minutes standard for every free user
  static const int proSecondsLimit = 999999;    // Unlimited for pro
  static const int reviewBonusSeconds = 60;     // 1 minute bonus for review
  static const int onboardingBonusSeconds = 0;  // Deprecated: 10 min is now standard (see freeSecondsLimit)

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
    final hasOnboardingBonus = await hasClaimedOnboardingBonus();
    return freeSecondsLimit
        + (hasReviewBonus ? reviewBonusSeconds : 0)
        + (hasOnboardingBonus ? onboardingBonusSeconds : 0);
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

  /// Check if onboarding bonus has been claimed
  Future<bool> hasClaimedOnboardingBonus() async {
    final box = await Hive.openBox(_boxName);
    return box.get('onboarding_bonus_claimed', defaultValue: false);
  }

  /// Claim the onboarding bonus (adds 10 minutes). Returns true if successfully claimed.
  Future<bool> claimOnboardingBonus() async {
    final box = await Hive.openBox(_boxName);
    final alreadyClaimed = box.get('onboarding_bonus_claimed', defaultValue: false);
    if (alreadyClaimed) return false;
    await box.put('onboarding_bonus_claimed', true);
    return true;
  }

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
