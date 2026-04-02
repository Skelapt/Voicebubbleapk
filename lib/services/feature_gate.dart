import 'package:flutter/material.dart';
import 'usage_service.dart';
import 'subscription_service.dart';
import '../widgets/upgrade_dialog.dart';
import '../widgets/review_dialog.dart';
import '../screens/paywall/paywall_screen.dart';

/// Central place to check feature access and show appropriate dialogs
class FeatureGate {
  static final UsageService _usageService = UsageService();
  static final SubscriptionService _subService = SubscriptionService();

  /// Check if user can use STT/AI recording
  /// Returns true if allowed, false if blocked (and shows dialog)
  static Future<bool> canUseSTT(BuildContext context) async {
    final isPro = await _subService.isPro();
    final canUse = await _usageService.canUseSTT(isPro: isPro);

    if (!canUse) {
      final shouldShowReview = await _usageService.shouldShowReviewPrompt(isPro: isPro);

      if (shouldShowReview && context.mounted) {
        final didReview = await ReviewDialog.showForFreeUser(context);

        if (didReview == true) {
          return await _usageService.canUseSTT(isPro: isPro);
        }
      }

      if (context.mounted) {
        final totalLimit = await _usageService.getTotalLimit(isPro: isPro);
        final totalMinutes = totalLimit ~/ 60;
        final reason = isPro
            ? 'You\'ve used all 90 minutes this month.'
            : 'You\'ve used all $totalMinutes minutes of free STT & AI.';
        final shouldUpgrade = await UpgradeDialog.show(
          context,
          reason: reason,
        );

        if (shouldUpgrade == true && context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaywallScreen(
                onSubscribe: () => Navigator.pop(context, true),
                onRestore: () => Navigator.pop(context, true),
                onClose: () => Navigator.pop(context),
              ),
            ),
          );
        }
      }
      return false;
    }

    return true;
  }

  /// Check if user can use Highlight AI (Pro only)
  static Future<bool> canUseHighlightAI(BuildContext context) async {
    final isPro = await _subService.isPro();

    if (!isPro) {
      if (context.mounted) {
        final shouldUpgrade = await UpgradeDialog.show(
          context,
          title: 'Pro Feature',
          reason: 'Highlight AI is a Pro feature. Upgrade to select text and transform it with AI.',
        );

        if (shouldUpgrade == true && context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaywallScreen(
                onSubscribe: () => Navigator.pop(context, true),
                onRestore: () => Navigator.pop(context, true),
                onClose: () => Navigator.pop(context),
              ),
            ),
          );
        }
      }
      return false;
    }

    return true;
  }

  /// Check if user can export audio (counts against STT limit)
  static Future<bool> canExportAudio(BuildContext context, int durationSeconds) async {
    final isPro = await _subService.isPro();
    final remaining = await _usageService.getRemainingSeconds(isPro: isPro);

    if (remaining < durationSeconds) {
      if (context.mounted) {
        final shouldUpgrade = await UpgradeDialog.show(
          context,
          reason: 'Not enough time remaining to export this audio. You need ${_usageService.formatTime(durationSeconds)} but only have ${_usageService.formatTime(remaining)} left.',
        );

        if (shouldUpgrade == true && context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaywallScreen(
                onSubscribe: () => Navigator.pop(context, true),
                onRestore: () => Navigator.pop(context, true),
                onClose: () => Navigator.pop(context),
              ),
            ),
          );
        }
      }
      return false;
    }

    return true;
  }

  /// Track STT usage after recording
  static Future<void> trackSTTUsage(int seconds) async {
    await _usageService.addUsage(seconds);
  }

  /// Track audio export usage
  static Future<void> trackAudioExport(int seconds) async {
    await _usageService.addUsage(seconds);
  }

  static Future<bool> isPro() async {
    return await _subService.isPro();
  }

  static Future<int> getRemainingSeconds() async {
    final isPro = await _subService.isPro();
    return await _usageService.getRemainingSeconds(isPro: isPro);
  }

  static Future<void> maybeShowReviewDialog(BuildContext context) async {
    final isPro = await _subService.isPro();

    if (isPro) {
      final hasAsked = await _subService.hasAskedForReviewAfterUpgrade();
      if (!hasAsked && context.mounted) {
        await ReviewDialog.showForProUser(context);
      }
    } else {
      final shouldShow = await _usageService.shouldShowReviewPrompt(isPro: false);
      if (shouldShow && context.mounted) {
        await ReviewDialog.showForFreeUser(context);
      }
    }
  }
}
