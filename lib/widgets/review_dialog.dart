import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import '../services/usage_service.dart';
import '../services/subscription_service.dart';

/// Dialog to ask for app review using native OS review dialog
/// - Free users: Shown when free time exhausted, offers 1 min bonus
/// - Pro users: Shown after upgrade to say thanks
class ReviewDialog extends StatelessWidget {
  final bool isFreeUser;
  final VoidCallback? onReviewComplete;

  const ReviewDialog({
    super.key,
    required this.isFreeUser,
    this.onReviewComplete,
  });

  static final InAppReview _inAppReview = InAppReview.instance;

  /// Show review dialog for free user (with bonus)
  static Future<bool?> showForFreeUser(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ReviewDialog(isFreeUser: true),
    );
  }

  /// Show review dialog for pro user (thank you)
  static Future<bool?> showForProUser(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => const ReviewDialog(isFreeUser: false),
    );
  }

  static Future<void> _requestReview() async {
    if (await _inAppReview.isAvailable()) {
      await _inAppReview.requestReview();
    } else {
      // Fallback: open store listing
      await _inAppReview.openStoreListing(
        appStoreId: 'com.voicebubble.app', // Your app ID
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const textColor = Colors.white;
    const secondaryTextColor = Color(0xFF94A3B8);
    const primaryColor = Color(0xFF3B82F6);
    const accentColor = Color(0xFFF59E0B);
    const greenColor = Color(0xFF10B981);

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (_) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.star, color: accentColor, size: 28),
              );
            }),
          ),
          const SizedBox(height: 16),
          Text(
            isFreeUser ? 'Enjoying VoiceBubble?' : 'Thank You! \uD83C\uDF89',
            style: const TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFreeUser) ...[
            const Text(
              'You\'ve used your 10 minutes of free STT & AI.',
              style: TextStyle(color: secondaryTextColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    greenColor.withOpacity(0.2),
                    primaryColor.withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: greenColor.withOpacity(0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.card_giftcard, color: Color(0xFF10B981), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Get 1 extra minute FREE!',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Leave a review and we\'ll add 1 minute to your account.',
                          style: TextStyle(color: secondaryTextColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Text(
              'Thanks for upgrading to Pro! We\'d love to hear your feedback.',
              style: TextStyle(color: secondaryTextColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Would you mind leaving us a review? It helps us grow and improve the app for everyone.',
              style: TextStyle(color: secondaryTextColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        if (isFreeUser)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'No Thanks',
              style: TextStyle(color: secondaryTextColor),
            ),
          ),
        if (!isFreeUser)
          TextButton(
            onPressed: () async {
              await SubscriptionService().markAskedForReviewAfterUpgrade();
              if (context.mounted) Navigator.pop(context, false);
            },
            child: const Text(
              'Maybe Later',
              style: TextStyle(color: secondaryTextColor),
            ),
          ),
        ElevatedButton(
          onPressed: () async {
            // Close dialog first, then show native review dialog
            Navigator.pop(context, true);

            // Request native review
            await _requestReview();

            if (isFreeUser) {
              final claimed = await UsageService().claimReviewBonus();
              if (claimed) {
                debugPrint('\u2705 Review bonus claimed - 1 minute added');
              }
            } else {
              await SubscriptionService().markLeftReview();
              await SubscriptionService().markAskedForReviewAfterUpgrade();
            }

            if (context.mounted && isFreeUser) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 12),
                      Text('\uD83C\uDF89 1 extra minute added to your account!'),
                    ],
                  ),
                  backgroundColor: Color(0xFF10B981),
                  duration: Duration(seconds: 3),
                ),
              );
            }

            onReviewComplete?.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isFreeUser ? greenColor : primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.rate_review, size: 18),
              const SizedBox(width: 8),
              Text(
                isFreeUser ? 'Leave Review & Get Bonus' : 'Leave a Review',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
