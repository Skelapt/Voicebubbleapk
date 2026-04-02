import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_state_provider.dart';
import '../../constants/presets.dart';
import '../../models/recording_item.dart';
import '../../widgets/multi_option_fab.dart';
import '../../services/reminder_manager.dart';
import '../settings/settings_screen.dart';
import '../paywall/paywall_screen.dart';
import '../../services/subscription_service.dart';
import 'recording_screen.dart';
import 'recording_detail_screen.dart';
import 'outcome_creation_screen.dart';

// ============================================================
//   SIMPLE BEAUTIFUL OUTCOMES - NO BULLSHIT
// ============================================================

class OutcomesScreenClean extends StatefulWidget {
  const OutcomesScreenClean({super.key});

  @override
  State<OutcomesScreenClean> createState() => _OutcomesScreenCleanState();
}

class _OutcomesScreenCleanState extends State<OutcomesScreenClean> {
  bool _showCompleted = false;
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _checkProStatus();
  }

  Future<void> _checkProStatus() async {
    final isPro = await SubscriptionService().isPro();
    if (mounted && isPro != _isPro) {
      setState(() => _isPro = isPro);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Consumer<AppStateProvider>(
          builder: (context, appState, _) {
            // Get ONLY outcome items (hiddenInLibrary = true)
            final allOutcomes = appState.outcomesItems;
            
            // Split into active and completed
            final activeItems = allOutcomes.where((i) => i.isCompleted != true).toList();
            final completedItems = allOutcomes.where((i) => i.isCompleted == true).toList();
            
            // Group active by outcome type
            final messageItems = activeItems.where((i) => i.outcomes.contains('message')).toList();
            final contentItems = activeItems.where((i) => i.outcomes.contains('content')).toList();
            final taskItems = activeItems.where((i) => i.outcomes.contains('task')).toList();
            final ideaItems = activeItems.where((i) => i.outcomes.contains('idea')).toList();
            final noteItems = activeItems.where((i) => i.outcomes.contains('note')).toList();

            return Column(
              children: [
                // ══════════════════════════════════════════
                // HEADER
                // ══════════════════════════════════════════
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      const Icon(Icons.dashboard, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Outcomes',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                      const Spacer(),
                      if (_isPro)
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(38),
                          ),
                          child: const Center(
                            child: Text('\u2B50', style: TextStyle(fontSize: 16)),
                          ),
                        )
                      else
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(38),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => PaywallScreen(
                                  onSubscribe: () {
                                    _checkProStatus();
                                  },
                                  onRestore: () {
                                    _checkProStatus();
                                  },
                                  onClose: () => Navigator.pop(context),
                                ),
                              );
                            },
                            icon: const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 20),
                          ),
                        ),
                      const SizedBox(width: 6),
                      // Settings icon
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(38),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          ),
                          icon: const Icon(Icons.settings, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),

                // ══════════════════════════════════════════
                // EMPTY STATE or SECTIONS
                // ══════════════════════════════════════════
                if (allOutcomes.isEmpty)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF3B82F6).withOpacity(0.15),
                                    const Color(0xFF2563EB).withOpacity(0.05),
                                  ],
                                ),
                                border: Border.all(
                                  color: const Color(0xFF3B82F6).withOpacity(0.3),
                                ),
                              ),
                              child: const Icon(
                                Icons.splitscreen_rounded,
                                color: Color(0xFF3B82F6),
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'Speak your mind.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Record anything \u2014 a conversation, a thought, a meeting. Hit the Outcomes preset and watch it pull out your tasks, actions and key points automatically.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.45),
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                height: 1.6,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: () {
                                  // Pre-select Outcomes preset and go to recording
                                  final outcomesPreset = AppPresets.findById('outcomes');
                                  if (outcomesPreset != null) {
                                    context.read<AppStateProvider>().setSelectedPreset(outcomesPreset);
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const RecordingScreen(),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Try it now',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    children: [
                      // MESSAGES
                      if (messageItems.isNotEmpty)
                        _buildSection('Messages', '💬', messageItems, const Color(0xFF3B82F6)),
                      
                      if (messageItems.isNotEmpty) const SizedBox(height: 24),
                      
                      // CONTENT
                      if (contentItems.isNotEmpty)
                        _buildSection('Content', '📝', contentItems, const Color(0xFF8B5CF6)),
                      
                      if (contentItems.isNotEmpty) const SizedBox(height: 24),
                      
                      // TASKS
                      if (taskItems.isNotEmpty)
                        _buildSection('Tasks', '✅', taskItems, const Color(0xFF10B981)),
                      
                      if (taskItems.isNotEmpty) const SizedBox(height: 24),
                      
                      // IDEAS
                      if (ideaItems.isNotEmpty)
                        _buildSection('Ideas', '💡', ideaItems, const Color(0xFFF59E0B)),
                      
                      if (ideaItems.isNotEmpty) const SizedBox(height: 24),
                      
                      // NOTES
                      if (noteItems.isNotEmpty)
                        _buildSection('Notes', '📋', noteItems, const Color(0xFF64748B)),
                      
                      if (noteItems.isNotEmpty) const SizedBox(height: 24),

                      // ══════════════════════════════════════════
                      // COMPLETED SECTION (COLLAPSIBLE)
                      // ══════════════════════════════════════════
                      if (completedItems.isNotEmpty) ...[
                        GestureDetector(
                          onTap: () => setState(() => _showCompleted = !_showCompleted),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  'Completed (${completedItems.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  _showCompleted ? Icons.expand_less : Icons.expand_more,
                                  color: Colors.white54,
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        if (_showCompleted) ...[
                          const SizedBox(height: 12),
                          ...completedItems.map((item) => _buildCard(
                            item,
                            _getColorForItem(item),
                            isCompleted: true,
                          )),
                        ],
                      ],

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const OutcomeCreationScreen(contentType: 'todo'),
            ),
          );
        },
        backgroundColor: const Color(0xFF3B82F6), // Blue - same as across app
        child: const Icon(Icons.check_box, color: Colors.white),
      ),
    );
  }

  // ══════════════════════════════════════════
  // BUILD SECTION
  // ══════════════════════════════════════════
  Widget _buildSection(String title, String emoji, List<RecordingItem> items, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${items.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Cards
        ...items.map((item) => _buildCard(item, color)),
      ],
    );
  }

  // ══════════════════════════════════════════
  // BUILD CARD (SIMPLE RECTANGLE)
  // ══════════════════════════════════════════
  Widget _buildCard(RecordingItem item, Color color, {bool isCompleted = false}) {
    final hasReminder = item.reminderDateTime != null;
    final isOverdue = hasReminder && item.reminderDateTime!.isBefore(DateTime.now());
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(item.id),
        background: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF10B981),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 24),
          child: const Icon(Icons.check_circle, color: Colors.white, size: 28),
        ),
        secondaryBackground: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Icon(Icons.delete, color: Colors.white, size: 28),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            _toggleComplete(item);
            return false;
          } else {
            return await _confirmDelete(item);
          }
        },
        child: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecordingDetailScreen(recordingId: item.id),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Checkbox
                GestureDetector(
                  onTap: () => _toggleComplete(item),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted ? color : Colors.transparent,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: isCompleted
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.finalText.isNotEmpty ? item.finalText : item.rawTranscript,
                        style: TextStyle(
                          fontSize: 15,
                          color: isCompleted ? const Color(0xFF64748B) : Colors.white,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.formattedDate,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Alarm icon with TIME DISPLAY - ALWAYS SHOW - NOW CLICKABLE
                GestureDetector(
                  onTap: () => _showReminderPicker(item),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isOverdue 
                              ? const Color(0xFFEF4444).withOpacity(0.15)
                              : (hasReminder ? color.withOpacity(0.15) : const Color(0xFF374151).withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.alarm,
                          size: 18,
                          color: isOverdue 
                              ? const Color(0xFFEF4444) 
                              : (hasReminder ? color : const Color(0xFF6B7280)),
                        ),
                      ),
                      // Show time if reminder is set
                      if (hasReminder) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${item.reminderDateTime!.hour.toString().padLeft(2, '0')}:${item.reminderDateTime!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isOverdue ? const Color(0xFFEF4444) : color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${item.reminderDateTime!.day}/${item.reminderDateTime!.month}',
                          style: TextStyle(
                            fontSize: 9,
                            color: isOverdue ? const Color(0xFFEF4444) : color.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════
  // SHOW REMINDER PICKER
  // ══════════════════════════════════════════
  Future<void> _showReminderPicker(RecordingItem item) async {
    final selectedDateTime = await showDatePicker(
      context: context,
      initialDate: item.reminderDateTime ?? DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF3B82F6),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDateTime != null) {
      final selectedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          item.reminderDateTime ?? DateTime.now().add(const Duration(hours: 1)),
        ),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF3B82F6),
                onPrimary: Colors.white,
                surface: Color(0xFF1A1A1A),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );

      if (selectedTime != null) {
        final newReminder = DateTime(
          selectedDateTime.year,
          selectedDateTime.month,
          selectedDateTime.day,
          selectedTime.hour,
          selectedTime.minute,
        );
        
        // Update the item with new reminder
        final appState = Provider.of<AppStateProvider>(context, listen: false);
        final updatedItem = item.copyWith(reminderDateTime: newReminder);
        await appState.updateRecording(updatedItem);
        
        // Schedule reminder notification
        await ReminderManager().scheduleReminder(updatedItem);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Reminder set for ${newReminder.day}/${newReminder.month} at ${newReminder.hour.toString().padLeft(2, '0')}:${newReminder.minute.toString().padLeft(2, '0')}'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  // ══════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════
  
  Color _getColorForItem(RecordingItem item) {
    if (item.outcomes.contains('message')) return const Color(0xFF3B82F6);
    if (item.outcomes.contains('content')) return const Color(0xFF8B5CF6);
    if (item.outcomes.contains('task')) return const Color(0xFF10B981);
    if (item.outcomes.contains('idea')) return const Color(0xFFF59E0B);
    return const Color(0xFF64748B); // notes
  }

  void _toggleComplete(RecordingItem item) async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final updated = item.copyWith(isCompleted: !(item.isCompleted ?? false));
    await appState.updateRecording(updated);
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  Future<bool> _confirmDelete(RecordingItem item) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Item?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final appState = Provider.of<AppStateProvider>(context, listen: false);
              await appState.deleteRecording(item.id);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    ) ?? false;
  }
}
