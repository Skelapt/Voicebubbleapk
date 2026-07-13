import 'package:flutter/material.dart';

/// Reusable upgrade dialog when user hits a limit
class UpgradeDialog extends StatelessWidget {
  final String title;
  final String reason;
  final VoidCallback? onUpgrade;
  final VoidCallback? onMaybeLater;

  const UpgradeDialog({
    super.key,
    this.title = 'Upgrade to Pro',
    required this.reason,
    this.onUpgrade,
    this.onMaybeLater,
  });

  /// Show the dialog easily
  static Future<bool?> show(
    BuildContext context, {
    String title = 'Upgrade to Pro',
    required String reason,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => UpgradeDialog(
        title: title,
        reason: reason,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF1A1A1A);
    const textColor = Colors.white;
    const secondaryTextColor = Color(0xFF94A3B8);
    const primaryColor = Color(0xFF3B82F6);
    const accentColor = Color(0xFFF59E0B);

    return AlertDialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.workspace_premium, color: accentColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reason text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: secondaryTextColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(
                      color: secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pro includes:',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          // Must match the paywall's offer EXACTLY — the Subscriptions
          // policy bans misleading in-app promotions, and promising
          // "90 minutes" here while the paywall says "Unlimited" is a
          // contradictory claim about what the subscription includes.
          _buildFeature('Unlimited voice-to-text transcriptions'),
          _buildFeature('Unlimited AI rewrites'),
          _buildFeature('Upload audio files for transcription'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context, false);
            onMaybeLater?.call();
          },
          child: const Text(
            'Maybe Later',
            style: TextStyle(color: secondaryTextColor),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, true);
            onUpgrade?.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rocket_launch, size: 18),
              SizedBox(width: 8),
              Text(
                'Upgrade Now',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeature(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
