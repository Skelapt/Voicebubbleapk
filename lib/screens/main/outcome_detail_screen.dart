import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../models/outcome_type.dart';
import '../../models/recording_item.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/reminder_button.dart';
import '../../services/reminder_manager.dart';
import 'recording_detail_screen.dart';

class OutcomeDetailScreen extends StatefulWidget {
  final OutcomeType outcomeType;
  final List<RecordingItem> items;

  const OutcomeDetailScreen({
    super.key,
    required this.outcomeType,
    required this.items,
  });

  @override
  State<OutcomeDetailScreen> createState() => _OutcomeDetailScreenState();
}

class _OutcomeDetailScreenState extends State<OutcomeDetailScreen> {
  String _searchQuery = '';
  final Map<String, bool> _completedTasks = {}; // Track completion state locally
  
  Future<void> _showReminderPicker(RecordingItem item) async {
    final appState = context.read<AppStateProvider>();
    await ReminderManager().showReminderPicker(
      context: context,
      item: item,
      appState: appState,
    );
    // Refresh to show updated reminder
    if (mounted) {
      setState(() {});
    }
  }
  
  List<RecordingItem> get filteredItems {
    if (_searchQuery.isEmpty) {
      return widget.items;
    }
    return widget.items.where((item) {
      return item.finalText.toLowerCase().contains(_searchQuery) ||
          item.rawTranscript.toLowerCase().contains(_searchQuery) ||
          item.presetUsed.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<Color> _getGradientColors() {
    switch (widget.outcomeType) {
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
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final gradientColors = _getGradientColors();

    // Group by date
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    
    final todayItems = filteredItems.where((item) {
      return item.createdAt.year == today.year &&
          item.createdAt.month == today.month &&
          item.createdAt.day == today.day;
    }).toList();

    final yesterdayItems = filteredItems.where((item) {
      return item.createdAt.year == yesterday.year &&
          item.createdAt.month == yesterday.month &&
          item.createdAt.day == yesterday.day;
    }).toList();

    final olderItems = filteredItems.where((item) {
      return !todayItems.contains(item) && !yesterdayItems.contains(item);
    }).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: textColor, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.outcomeType.emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.outcomeType.displayName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${widget.items.length} items',
                          style: TextStyle(
                            fontSize: 14,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  style: TextStyle(color: textColor, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.outcomeType.displayName.toLowerCase()}...',
                    hintStyle: TextStyle(color: secondaryTextColor),
                    prefixIcon: Icon(Icons.search, color: secondaryTextColor),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Items List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  // Today
                  if (todayItems.isNotEmpty) ...[
                    Text(
                      '📅 Today',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...todayItems.map((item) => _buildItemCard(
                          item,
                          surfaceColor,
                          textColor,
                          secondaryTextColor,
                          gradientColors,
                        )),
                    const SizedBox(height: 24),
                  ],

                  // Yesterday
                  if (yesterdayItems.isNotEmpty) ...[
                    Text(
                      '📅 Yesterday',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...yesterdayItems.map((item) => _buildItemCard(
                          item,
                          surfaceColor,
                          textColor,
                          secondaryTextColor,
                          gradientColors,
                        )),
                    const SizedBox(height: 24),
                  ],

                  // Older
                  if (olderItems.isNotEmpty) ...[
                    Text(
                      '📅 Older',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...olderItems.map((item) => _buildItemCard(
                          item,
                          surfaceColor,
                          textColor,
                          secondaryTextColor,
                          gradientColors,
                        )),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(
    RecordingItem item,
    Color surfaceColor,
    Color textColor,
    Color secondaryTextColor,
    List<Color> gradientColors,
  ) {
    final isTask = widget.outcomeType == OutcomeType.task;
    final isCompleted = _completedTasks[item.id] ?? item.isCompleted;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          // All content types now use the unified RecordingDetailScreen with RichTextEditor
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RecordingDetailScreen(
                recordingId: item.id,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: gradientColors[0].withOpacity(isCompleted ? 0.1 : 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox + Preset name row + Reminder button
              Row(
                children: [
                  // Completion checkbox for ALL outcome types
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _completedTasks[item.id] = !isCompleted;
                      });
                      // TODO: Save completion state to database
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isCompleted
                            ? LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        border: Border.all(
                          color: isCompleted ? Colors.transparent : gradientColors[0],
                          width: 2,
                        ),
                      ),
                      child: isCompleted
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.presetUsed,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: gradientColors[0],
                      ),
                    ),
                  ),
                  // Reminder button for ALL outcome types
                  ReminderButton(
                    reminderDateTime: item.reminderDateTime,
                    onPressed: () => _showReminderPicker(item),
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Content preview
              Text(
                item.finalText,
                style: TextStyle(
                  fontSize: 14,
                  color: isCompleted ? secondaryTextColor : textColor,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                  decorationColor: isCompleted ? secondaryTextColor : null,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),

              // Time and actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.formattedDate,
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryTextColor,
                    ),
                  ),
                  Row(
                    children: [
                      // Copy button
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: item.finalText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied to clipboard'),
                              backgroundColor: Color(0xFF10B981),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.copy,
                            size: 18,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                      // Share button
                      InkWell(
                        onTap: () {
                          Share.share(item.finalText);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.share,
                            size: 18,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
