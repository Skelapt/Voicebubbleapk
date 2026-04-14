import 'package:flutter/material.dart';
import '../models/outcome_type.dart';
import '../models/recording_item.dart';

class OutcomeCard extends StatelessWidget {
  final OutcomeType outcomeType;
  final int itemCount;
  final List<RecordingItem> items; // Preview items (max 3)
  final VoidCallback onTap;

  const OutcomeCard({
    super.key,
    required this.outcomeType,
    required this.itemCount,
    required this.items,
    required this.onTap,
  });

  List<Color> _getGradientColors() {
    switch (outcomeType) {
      case OutcomeType.message:
        return [const Color(0xFF3B82F6), const Color(0xFF2563EB)];
      case OutcomeType.content:
        return [const Color(0xFF9333EA), const Color(0xFFEC4899)];
      case OutcomeType.task:
        return [const Color(0xFF10B981), const Color(0xFF14B8A6)];
      case OutcomeType.idea:
        return [const Color(0xFFF59E0B), const Color(0xFFF97316)];
      case OutcomeType.note:
        return [const Color(0xFF6B7280), const Color(0xFF4B5563)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = _getGradientColors();
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final surfaceColor = const Color(0xFF1A1A2E);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              gradientColors[0].withOpacity(0.15),
              gradientColors[1].withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: gradientColors[0].withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      outcomeType.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          outcomeType.displayName,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        Text(
                          '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'View',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: textColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Preview items (max 3)
            if (items.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...items.take(3).map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: surfaceColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.finalText,
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor.withOpacity(0.9),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.formattedDate.split(',')[0], // Just "Today" or "Yesterday"
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
