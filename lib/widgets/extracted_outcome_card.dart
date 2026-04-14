import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/extracted_outcome.dart';
import '../models/recording_item.dart';
import '../widgets/outcome_chip.dart';
import '../widgets/reminder_button.dart';

class ExtractedOutcomeCard extends StatefulWidget {
  final ExtractedOutcome outcome;
  final VoidCallback onContinue;
  final Function(String) onTextChanged;
  final RecordingItem? savedItem; // The actual saved item with reminder info
  final VoidCallback? onReminderPressed;
  
  const ExtractedOutcomeCard({
    super.key,
    required this.outcome,
    required this.onContinue,
    required this.onTextChanged,
    this.savedItem,
    this.onReminderPressed,
  });

  @override
  State<ExtractedOutcomeCard> createState() => _ExtractedOutcomeCardState();
}

class _ExtractedOutcomeCardState extends State<ExtractedOutcomeCard> {
  late TextEditingController _controller;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.outcome.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Outcome type chip
          Row(
            children: [
              OutcomeChip(
                outcomeType: widget.outcome.type,
                isSelected: true,
                onTap: () {},
              ),
              const Spacer(),
              // Reminder button (only if savedItem provided)
              if (widget.savedItem != null && widget.onReminderPressed != null)
                ReminderButton(
                  reminderDateTime: widget.savedItem!.reminderDateTime,
                  onPressed: widget.onReminderPressed!,
                  compact: true,
                ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Editable text
          TextField(
            controller: _controller,
            style: TextStyle(
              fontSize: 18, // Increased from 16
              color: textColor,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
            maxLines: null,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Edit outcome...',
              hintStyle: TextStyle(color: secondaryTextColor.withOpacity(0.5)),
            ),
            onChanged: widget.onTextChanged,
          ),
          
          const SizedBox(height: 16),
          
          // Compact action buttons (2 buttons side by side)
          Row(
            children: [
              // Share button (left side, smaller and cleaner)
              Expanded(
                child: SizedBox(
                  height: 42, // Reduced from 56
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Share.share(_controller.text);
                    },
                    icon: const Icon(Icons.share, size: 16, color: Color(0xFF22D3EE)),
                    label: const Text(
                      'Share',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF22D3EE),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF22D3EE), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 10),
              
              // Continue button (right side, smaller and cleaner)
              Expanded(
                child: SizedBox(
                  height: 42, // Reduced from 56
                  child: OutlinedButton.icon(
                    onPressed: widget.onContinue,
                    icon: const Icon(Icons.arrow_forward, size: 16, color: Color(0xFF22D3EE)),
                    label: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF22D3EE),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF22D3EE), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
