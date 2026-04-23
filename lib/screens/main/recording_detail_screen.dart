import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/app_state_provider.dart';
import '../../services/share_handler_service.dart';
import '../import/import_content_screen.dart';
import '../../models/recording_item.dart';
import '../../models/tag.dart';
import '../../models/outcome_type.dart';
import '../../widgets/outcome_chip.dart';
import '../../widgets/preset_chip.dart';
import '../../widgets/tag_chip.dart';
import '../../widgets/add_tag_bottom_sheet.dart';
import '../../widgets/add_to_project_dialog.dart';
import '../../widgets/rich_text_editor.dart';
import '../../services/continue_service.dart';
import '../../models/continue_context.dart';
import '../../services/reminder_manager.dart';
import '../../constants/presets.dart';
import 'recording_screen.dart';
// ✨ NEW IMPORTS ✨
import '../version_history_screen.dart';
import '../../widgets/export_dialogs.dart';
import '../../widgets/background_picker.dart';
import '../../services/version_history_service.dart';
import '../../constants/visual_constants.dart';
import '../../services/analytics_service.dart';
import '../../services/review_service.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ✨ END NEW IMPORTS ✨

class RecordingDetailScreen extends StatefulWidget {
  final String recordingId;

  const RecordingDetailScreen({
    super.key,
    required this.recordingId,
  });

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  bool _isEditingTitle = false;
  late TextEditingController _titleController;
  int _editorRebuildKey = 0;  // Forces editor to rebuild with fresh content from Hive

  // First-recording celebration
  static const String _firstRecordingKey = 'has_recorded_once';
  late final ConfettiController _confettiController;
  bool _showUnlockBanner = false;

  // Undo chip — one-shot, 10s lifetime, reverts AI rewrite to raw transcript
  bool _showUndoChip = false;
  Timer? _undoChipTimer;

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreenView(screenName: 'RecordingDetail');
    _titleController = TextEditingController();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _maybeCelebrateFirstRecording();
    _maybeShowUndoChip();
  }

  Future<void> _maybeCelebrateFirstRecording() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasRecorded = prefs.getBool(_firstRecordingKey) ?? false;
      if (!hasRecorded) {
        await prefs.setBool(_firstRecordingKey, true);
        // Brief delay so the editor settles first, then celebrate
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        setState(() => _showUnlockBanner = true);
        _confettiController.play();
        HapticFeedback.mediumImpact();
        // Auto-hide the banner after 4s
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showUnlockBanner = false);
        });
      }
    } catch (_) {}
  }

  /// Show a one-time "Undo" chip for 20 seconds the first time the user
  /// lands on a voice recording whose AI rewrite differs from the raw
  /// transcript. Tapping restores the raw text.
  Future<void> _maybeShowUndoChip() async {
    try {
      // Wait one frame so Provider is accessible and the editor has built
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final seenKey = 'undo_chip_seen_${widget.recordingId}';
      if (prefs.getBool(seenKey) ?? false) return;

      final appState = context.read<AppStateProvider>();
      final item = appState.allRecordingItems.firstWhere(
        (r) => r.id == widget.recordingId,
        orElse: () => RecordingItem(
          id: widget.recordingId,
          rawTranscript: '',
          finalText: '',
          presetUsed: '',
          outcomes: const [],
          projectId: null,
          createdAt: DateTime.now(),
          editHistory: const [],
          presetId: '',
          tags: const [],
          contentType: 'text',
        ),
      );

      final isVoice = item.contentType == 'voice';
      final hasRewrite = item.rawTranscript.trim().isNotEmpty &&
          item.rawTranscript.trim() != item.finalText.trim();
      if (!isVoice || !hasRewrite) return;

      await prefs.setBool(seenKey, true);
      if (!mounted) return;
      setState(() => _showUndoChip = true);
      _undoChipTimer = Timer(const Duration(seconds: 20), () {
        if (mounted) setState(() => _showUndoChip = false);
      });
    } catch (_) {}
  }

  Future<void> _handleUndoRewrite(
      AppStateProvider appState, RecordingItem item) async {
    _undoChipTimer?.cancel();
    HapticFeedback.lightImpact();
    final restored = item.copyWith(
      finalText: item.rawTranscript,
      clearFormattedContent: true,
    );
    await appState.updateRecording(restored);
    if (!mounted) return;
    setState(() {
      _showUndoChip = false;
      _editorRebuildKey++;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _confettiController.dispose();
    _undoChipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF8B8FA3);
    final primaryColor = const Color(0xFF7C6AE8);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Consumer<AppStateProvider>(
          builder: (context, appState, _) {
            // Search in ALL items, not just recordingItems (which filters out outcome items)
            final item = appState.allRecordingItems.firstWhere(
              (r) => r.id == widget.recordingId,
              orElse: () => RecordingItem(
                id: widget.recordingId,
                rawTranscript: '',
                finalText: '',
                presetUsed: '',
                outcomes: [],
                projectId: null,
                createdAt: DateTime.now(),
                editHistory: [],
                presetId: '',
                tags: [],
                contentType: 'text',
              ),
            );

            // If item wasn't found in state yet, show loading
            if (!appState.allRecordingItems.any((r) => r.id == widget.recordingId)) {
              return const Center(child: CircularProgressIndicator());
            }

            // ✨ BUILD BACKGROUND IF SET ✨
            Widget? backgroundWidget;
            if (item.background != null) {
              final bg = VisualConstants.findById(item.background!);
              if (bg != null) {
                backgroundWidget = Opacity(
                  opacity: 0.15, // Subtle so text is readable
                  child: bg.buildBackground(context),
                );
              }
            }
            // ✨ END BACKGROUND BUILD ✨

            return Stack(
              children: [
                // Background layer
                if (backgroundWidget != null)
                  Positioned.fill(child: backgroundWidget),
                
                // Content layer — single scrollable unit
                Column(
              children: [
                Expanded(
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) {
                      return [
                        SliverAppBar(
                          backgroundColor: backgroundColor,
                          automaticallyImplyLeading: false,
                          floating: true,
                          snap: true,
                          toolbarHeight: 44,
                          title: Row(
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => Navigator.pop(context),
                                icon: Icon(Icons.arrow_back_ios_new, color: primaryColor, size: 22),
                              ),
                              const Spacer(),
                              Text(
                                _formatDate(item.createdAt),
                                style: TextStyle(fontSize: 13, color: secondaryTextColor),
                              ),
                              const Spacer(),
                              // Share button — direct action, no menu
                              GestureDetector(
                                onTap: () => _handleMenuAction(context, appState, item, 'share'),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.shortcut, color: textColor, size: 20),
                                ),
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: Icon(Icons.more_vert, color: textColor, size: 22),
                                color: surfaceColor,
                                onSelected: (value) => _handleMenuAction(context, appState, item, value),
                                itemBuilder: (context) {
                                  final isOutcome = item.outcomes.isNotEmpty && item.hiddenInLibrary;
                                  return [
                                    PopupMenuItem(value: 'continue', child: Row(children: [Icon(Icons.mic, color: primaryColor, size: 18), const SizedBox(width: 12), Text('Continue', style: TextStyle(color: textColor))])),
                                    PopupMenuItem(value: 'version_history', child: Row(children: [Icon(Icons.history, color: primaryColor, size: 18), const SizedBox(width: 12), Text('Version History', style: TextStyle(color: textColor))])),
                                    PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, color: textColor, size: 18), const SizedBox(width: 12), Text('Share', style: TextStyle(color: textColor))])),
                                    PopupMenuItem(value: 'add_to_project', child: Row(children: [Icon(Icons.folder_outlined, color: textColor, size: 18), const SizedBox(width: 12), Text('Add to Project', style: TextStyle(color: textColor))])),
                                    if (!isOutcome) PopupMenuItem(value: 'manage_tags', child: Row(children: [Icon(Icons.local_offer, color: textColor, size: 18), const SizedBox(width: 12), Text('Manage Tags', style: TextStyle(color: textColor))])),
                                    PopupMenuItem(value: 'import', child: Row(children: [Icon(Icons.file_download, color: const Color(0xFF8B5CF6), size: 18), const SizedBox(width: 12), Text('Import', style: TextStyle(color: textColor))])),
                                    PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.upload, color: textColor, size: 18), const SizedBox(width: 12), Text('Export', style: TextStyle(color: textColor))])),
                                    const PopupMenuDivider(),
                                    PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_forever, color: Color(0xFFEF4444), size: 18), const SizedBox(width: 12), Text('Delete', style: TextStyle(color: Color(0xFFEF4444)))])),
                                  ];
                                },
                              ),
                            ],
                          ),
                        ),
                        // Title + Tags as a pinned sliver that scrolls away
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Big headline
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                                child: _isEditingTitle
                                    ? Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _titleController,
                                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor),
                                              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero, isDense: true),
                                              autofocus: true,
                                              maxLines: null,
                                              onSubmitted: (_) => _saveTitle(appState, item),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(onTap: () => _saveTitle(appState, item), child: Icon(Icons.check, color: primaryColor, size: 22)),
                                        ],
                                      )
                                    : GestureDetector(
                                        onTap: () => _startEditingTitle(item),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: Text(_getDisplayTitle(item), style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor)),
                                        ),
                                      ),
                              ),
                              // Tags
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: GestureDetector(
                                    onTap: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (context) => AddTagBottomSheet(recordingId: item.id, currentTags: item.tags),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.add, color: secondaryTextColor, size: 14),
                                          const SizedBox(width: 4),
                                          Text('Tags', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ];
                    },
                    body: _buildContentEditor(item, appState),
                  ),
                ),
              ],
            ), // ← End of Column

                // 🎉 Confetti burst from the top-center on first recording
                Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: _confettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    shouldLoop: false,
                    numberOfParticles: 30,
                    maxBlastForce: 22,
                    minBlastForce: 8,
                    emissionFrequency: 0.05,
                    gravity: 0.35,
                    colors: const [
                      Color(0xFF7C6AE8),
                      Color(0xFFFFD700),
                      Color(0xFFFAF5F0),
                      Color(0xFF34C759),
                      Color(0xFFEC4899),
                    ],
                  ),
                ),

                // 🎁 Unlock banner — slides down from the top
                if (_showUnlockBanner)
                  Positioned(
                    top: 12,
                    left: 24,
                    right: 24,
                    child: _UnlockBanner(),
                  ),

                // ↩︎ Undo chip — one-shot, 10s lifetime. Reverts AI rewrite
                // so user can reach for other rewrite options on the raw text.
                // Sits above the "Now the magic" first-open card (bottom 85,
                // ~60px tall → top edge at ~145) and the Continue / Rewrite
                // bottom bar so it never covers anything.
                if (_showUndoChip)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 170,
                    child: Center(
                      child: _UndoChip(
                        onTap: () => _handleUndoRewrite(appState, item),
                      ),
                    ),
                  ),
              ], // ← End of Stack children
            ); // ← End of Stack
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getDisplayTitle(RecordingItem item) {
    // Prioritize custom title over generated title
    if (item.customTitle != null && item.customTitle!.isNotEmpty) {
      return item.customTitle!;
    }
    return _getTitleFromContent(item.finalText);
  }
  
  String _getTitleFromContent(String content) {
    if (content.isEmpty) return 'Untitled';
    
    // Get first line or first 50 characters
    final firstLine = content.split('\n').first.trim();
    if (firstLine.length <= 50) return firstLine;
    
    return '${firstLine.substring(0, 47)}...';
  }
  
  void _startEditingTitle(RecordingItem item) {
    setState(() {
      _isEditingTitle = true;
      _titleController.text = item.customTitle ?? _getTitleFromContent(item.finalText);
    });
  }
  
  void _cancelEditingTitle() {
    setState(() {
      _isEditingTitle = false;
      _titleController.clear();
    });
  }
  
  Future<void> _saveTitle(AppStateProvider appState, RecordingItem item) async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isNotEmpty) {
      final updatedItem = item.copyWith(customTitle: newTitle);
      await appState.updateRecording(updatedItem);
    }
    setState(() {
      _isEditingTitle = false;
      _titleController.clear();
    });
  }

  Widget _buildContentEditor(RecordingItem item, AppStateProvider appState) {
    // ALWAYS use RichTextEditor with context-aware features
    return RichTextEditor(
      key: ValueKey('editor_${item.id}_$_editorRebuildKey'),
      initialFormattedContent: item.formattedContent,
      initialPlainText: item.finalText,
      onSave: (plainText, deltaJson) => _saveContent(appState, item, plainText, deltaJson),
      readOnly: false,
      contentType: item.contentType, // Pass content type for auto-initialization
      // Context-aware features based on item type
      showImageSection: item.contentType == 'image',
      initialImagePath: item.contentType == 'image' ? item.rawTranscript : null,
      onImageChanged: (imagePath) => _updateItemImage(appState, item, imagePath),
      showOutcomeChips: item.outcomes.isNotEmpty,
      initialOutcomeType: item.outcomes.isNotEmpty ? OutcomeTypeExtension.fromString(item.outcomes.first) : null,
      onOutcomeChanged: (outcomeType) => _updateItemOutcome(appState, item, outcomeType),
      // Reminder button ONLY for outcomes (hiddenInLibrary = true)
      showReminderButton: false,
      initialReminder: item.reminderDateTime,
      onReminderChanged: (dateTime) => _updateItemReminder(appState, item, dateTime),
      showCompletionCheckbox: item.outcomes.isNotEmpty && item.hiddenInLibrary, // ONLY for outcomes, NOT library todos
      initialCompletion: item.isCompleted,
      onCompletionChanged: (completed) => _updateItemCompletion(appState, item, completed),
      // Top toolbar (Google Keep style) for library items
      showTopToolbar: !item.hiddenInLibrary || item.projectId != null, // Show for library AND project items, hide only for outcomes
      isPinned: item.isPinned ?? false,
      onPinChanged: (pinned) => _updateItemPin(appState, item, pinned),
      onVoiceNoteAdded: (path) => _handleVoiceNoteAdded(appState, item, path),
      // Background support
      backgroundId: item.background,
      onBackgroundChanged: (backgroundId) => _updateItemBackground(appState, item, backgroundId),
      // Continue recording — same logic as dropdown menu
      onContinuePressed: () => _handleContinue(context, appState, item),
    );
  }

  Future<void> _saveContent(AppStateProvider appState, RecordingItem item, String plainText, String deltaJson) async {
    try {
      final updatedItem = item.copyWith(
        finalText: plainText,
        formattedContent: deltaJson,
      );
      
      await appState.updateRecording(updatedItem);
      
      // ✨ AUTO-SAVE TO VERSION HISTORY ✨
      final versionService = VersionHistoryService();
      await versionService.saveVersion(updatedItem, 'Auto-save');
      // ✨ END AUTO-SAVE ✨
      
      debugPrint('✅ Saved formatted content for item: ${item.id}');
    } catch (e) {
      debugPrint('❌ Error saving formatted content: $e');
    }
  }
  
  // Context-aware update methods
  
  Future<void> _updateItemImage(AppStateProvider appState, RecordingItem item, String? imagePath) async {
    try {
      final updatedItem = item.copyWith(
        rawTranscript: imagePath ?? '', // Store image path in rawTranscript
      );
      await appState.updateRecording(updatedItem);
      debugPrint('✅ Updated image for item: ${item.id}');
    } catch (e) {
      debugPrint('❌ Error updating image: $e');
    }
  }
  
  Future<void> _updateItemOutcome(AppStateProvider appState, RecordingItem item, OutcomeType outcomeType) async {
    try {
      final updatedItem = item.copyWith(
        outcomes: [outcomeType.toStorageString()],
      );
      await appState.updateRecording(updatedItem);
      debugPrint('✅ Updated outcome for item: ${item.id}');
    } catch (e) {
      debugPrint('❌ Error updating outcome: $e');
    }
  }
  
  Future<void> _updateItemReminder(AppStateProvider appState, RecordingItem item, DateTime? dateTime) async {
    try {
      final updatedItem = item.copyWith(
        reminderDateTime: dateTime,
      );
      await appState.updateRecording(updatedItem);
      
      // Schedule or cancel reminder
      if (dateTime != null) {
        await ReminderManager().scheduleReminder(updatedItem);

        final hoursFromNow = dateTime.difference(DateTime.now()).inHours;
        AnalyticsService().logReminderSet(
          outcomeType: item.outcomes.isNotEmpty
            ? item.outcomes.first.toString()
            : 'generic',
          hoursFromNow: hoursFromNow,
        );
      } else {
        await ReminderManager().cancelReminder(updatedItem);
      }

      debugPrint('✅ Updated reminder for item: ${item.id}');
    } catch (e) {
      debugPrint('❌ Error updating reminder: $e');
    }
  }
  
  Future<void> _updateItemCompletion(AppStateProvider appState, RecordingItem item, bool completed) async {
    try {
      final updatedItem = item.copyWith(
        isCompleted: completed,
      );
      await appState.updateRecording(updatedItem);

      if (completed) {
        AnalyticsService().logOutcomeCompleted(
          outcomeType: item.outcomes.isNotEmpty
            ? item.outcomes.first.toString()
            : 'generic',
        );
        await ReviewService().trackOutcomeCompletion();
      }

      debugPrint('✅ Updated completion for item: ${item.id}');
    } catch (e) {
      debugPrint('❌ Error updating completion: $e');
    }
  }
  
  Future<void> _updateItemPin(AppStateProvider appState, RecordingItem item, bool pinned) async {
    try {
      final updatedItem = item.copyWith(
        isPinned: pinned,
      );
      await appState.updateRecording(updatedItem);
      debugPrint('✅ Updated pin status for item: ${item.id}');
    } catch (e) {
      debugPrint('❌ Error updating pin: $e');
    }
  }
  
  Future<void> _handleVoiceNoteAdded(AppStateProvider appState, RecordingItem item, String voiceNotePath) async {
    debugPrint('🎤 Voice note added at: $voiceNotePath');
    // Voice note is already inserted into the document text by RichTextEditor
    // Just log it here for reference
  }

  Future<void> _handleMenuAction(BuildContext context, AppStateProvider appState, RecordingItem item, String action) async {
    switch (action) {
      case 'continue':
        _handleContinue(context, appState, item);
        break;
      case 'version_history':
        final restored = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => VersionHistoryScreen(note: item),
          ),
        );
        if (restored == true && mounted) {
          setState(() {
            _editorRebuildKey++;
          });
        }
        break;
      case 'share':
        AnalyticsService().logOutputShared(
          presetId: item.presetId,
          shareMethod: 'native_share',
        );
        Share.share(item.finalText);
        break;
      case 'add_to_project':
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) => AddToProjectDialog(
            recordingItemId: item.id,
          ),
        );
        break;
      case 'manage_tags':
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => AddTagBottomSheet(
            recordingId: item.id,
            currentTags: item.tags,
          ),
        );
        break;
      // ✨ IMPORT HANDLER ✨
      case 'import':
        _showImportDialog(context, appState, item);
        break;
      // ✨ EXPORT HANDLER ✨
      case 'export':
        AnalyticsService().logCustomEvent(
          eventName: 'document_exported',
          parameters: {
            'format': 'dialog_opened',
            'source': 'recording_detail',
            'content_type': item.contentType,
          },
        );
        // Wait for any pending auto-saves and get fresh item
        await Future.delayed(const Duration(milliseconds: 100));
        final freshExportItem = appState.allRecordingItems.firstWhere(
          (r) => r.id == item.id,
          orElse: () => item,
        );
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (_) => ExportDialog(note: freshExportItem),
          );
        }
        break;
      // ✨ END NEW HANDLERS ✨
      case 'delete':
        _showDeleteConfirmation(context, appState, item.id);
        break;
    }
  }

  void _handleContinue(BuildContext context, AppStateProvider appState, RecordingItem item) async {
    try {
      AnalyticsService().logContinueFromItem();
      // Small delay to ensure any pending auto-saves complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Reload item from state to get latest saved content
      final freshItem = appState.allRecordingItems.firstWhere(
        (r) => r.id == item.id,
        orElse: () => item,
      );

      // Build context with FRESH content
      final continueContext = ContinueContext(
        singleItemId: freshItem.id,
        contextTexts: [freshItem.finalText],
      );

      appState.setContinueContext(continueContext);

      // Navigate to recording screen (PUSH, not replace - so we can come back)
      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const RecordingScreen(),
          ),
        );

        // FORCE EDITOR TO REBUILD WITH FRESH CONTENT FROM HIVE
        // This ensures the editor reloads content including any appended text
        if (mounted) {
          setState(() {
            _editorRebuildKey++;  // This forces editor to reload from Hive
          });
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation(BuildContext context, AppStateProvider appState, String itemId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Delete Recording?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          TextButton(
            onPressed: () async {
              await appState.deleteRecording(itemId);
              if (context.mounted) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back to library
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Recording deleted'),
                    backgroundColor: Color(0xFF10B981),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateItemBackground(AppStateProvider appState, RecordingItem item, String? backgroundId) async {
    try {
      final updatedItem = backgroundId == null
          ? item.copyWith(clearBackground: true)
          : item.copyWith(background: backgroundId);
      await appState.updateRecording(updatedItem);
      debugPrint('✅ Updated background for item: ${item.id}');
    } catch (e) {
      debugPrint('❌ Error updating background: $e');
    }
  }

  /// Show import type selection dialog
  /// CRITICAL: Captures NavigatorState BEFORE opening dialog to avoid dead context issues
  void _showImportDialog(BuildContext outerContext, AppStateProvider appState, RecordingItem item) {
    // Capture the navigator BEFORE opening the dialog
    // Use the State's own `context` (from State<RecordingDetailScreen>)
    // which is ALWAYS valid as long as the screen is alive
    final nav = Navigator.of(this.context);

    showDialog(
      context: this.context,  // Use State's context, not the popup menu's
      builder: (dialogContext) {
        final surfaceColor = Theme.of(dialogContext).brightness == Brightness.dark
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFFFFFFF);
        final textColor = Theme.of(dialogContext).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF1F2937);

        return Dialog(
          backgroundColor: surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Content',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose what to import',
                  style: TextStyle(
                    color: textColor.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),

                // PDF
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444)),
                  title: Text('PDF Document', style: TextStyle(color: textColor)),
                  subtitle: const Text('Extract text from PDF', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _pickAndImportFile(
                      nav, appState, item,
                      extensions: ['pdf'],
                      forceType: SharedContentType.pdf,
                      forceMime: 'application/pdf',
                    );
                  },
                ),

                // Word Document
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description, color: Color(0xFF3B82F6)),
                  title: Text('Word Document', style: TextStyle(color: textColor)),
                  subtitle: const Text('Import .docx files', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _pickAndImportFile(
                      nav, appState, item,
                      extensions: ['doc', 'docx'],
                      forceType: SharedContentType.document,
                      forceMime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                    );
                  },
                ),

                // Text File
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.text_fields, color: Color(0xFF10B981)),
                  title: Text('Text File', style: TextStyle(color: textColor)),
                  subtitle: const Text('Import .txt, .md, .rtf', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _pickAndImportFile(
                      nav, appState, item,
                      extensions: ['txt', 'md', 'rtf'],
                      forceType: SharedContentType.text,
                      forceMime: 'text/plain',
                    );
                  },
                ),

                // Image (visual)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image, color: Color(0xFFF59E0B)),
                  title: Text('Image', style: TextStyle(color: textColor)),
                  subtitle: const Text('Add image to document', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _pickAndImportFile(
                      nav, appState, item,
                      extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
                      forceType: SharedContentType.image,
                      forceMime: 'image/jpeg',
                    );
                  },
                ),

                // Image to Text (OCR)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.document_scanner, color: Color(0xFF8B5CF6)),
                  title: Text('Image to Text (OCR)', style: TextStyle(color: textColor)),
                  subtitle: const Text('Extract text from image', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    AnalyticsService().logCustomEvent(
                      eventName: 'ocr_feature_opened',
                      parameters: {'from_screen': 'recording_detail'},
                    );
                    _pickAndImportFile(
                      nav, appState, item,
                      extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
                      forceType: SharedContentType.image,
                      forceMime: 'image/jpeg',
                      ocrMode: true,
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Cancel
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: textColor.withOpacity(0.7),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Pick a file and navigate to import screen
  /// Uses pre-captured NavigatorState to avoid dead context issues after file picker returns
  Future<void> _pickAndImportFile(
    NavigatorState nav,
    AppStateProvider appState,
    RecordingItem item, {
    required List<String> extensions,
    required SharedContentType forceType,
    required String forceMime,
    bool ocrMode = false,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
      );

      if (result == null || result.files.single.path == null) return;

      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;
      final extension = result.files.single.extension?.toLowerCase() ?? '';

      // Refine mime type based on actual file extension
      String mimeType = forceMime;
      if (forceType == SharedContentType.image) {
        switch (extension) {
          case 'png': mimeType = 'image/png'; break;
          case 'gif': mimeType = 'image/gif'; break;
          case 'webp': mimeType = 'image/webp'; break;
          default: mimeType = 'image/jpeg'; break;
        }
      } else if (forceType == SharedContentType.text) {
        switch (extension) {
          case 'md': mimeType = 'text/markdown'; break;
          case 'rtf': mimeType = 'text/rtf'; break;
          default: mimeType = 'text/plain'; break;
        }
      } else if (forceType == SharedContentType.document && extension == 'doc') {
        mimeType = 'application/msword';
      }

      if (!mounted) return;

      // If OCR mode, override type to trigger OCR path
      final actualType = ocrMode ? SharedContentType.unknown : forceType;

      // Use the pre-captured NavigatorState — guaranteed to be alive
      final imported = await nav.push<bool>(
        MaterialPageRoute(
          builder: (_) => ImportContentScreen(
            content: SharedContent(
              type: actualType,
              filePath: filePath,
              fileName: fileName,
              mimeType: ocrMode ? 'image/ocr' : mimeType,
            ),
            appendToNoteId: item.id,
          ),
        ),
      );

      // If content was imported, refresh the editor
      if (imported == true && mounted) {
        setState(() {
          _editorRebuildKey++;
        });
      }
    } catch (e) {
      debugPrint('Error picking import file: $e');
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text('Import error: ${e.toString()}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }
}
/// "10 minutes of Pro unlocked" celebration banner — slides in from
/// the top with a soft bounce, fades out after 4s.
class _UnlockBanner extends StatefulWidget {
  @override
  State<_UnlockBanner> createState() => _UnlockBannerState();
}

class _UnlockBannerState extends State<_UnlockBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C6AE8), Color(0xFF5B4BC9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C6AE8).withOpacity(0.45),
                blurRadius: 24,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('🎉', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '10 minutes of Pro unlocked',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Your gift is ready. Try a Rewrite.',
                      style: TextStyle(
                        color: Color(0xFFE0DBFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "Undo" chip shown briefly after a voice rewrite — tapping reverts
/// the polished output back to the raw transcript so the user can reach
/// for a different rewrite preset.
class _UndoChip extends StatefulWidget {
  final VoidCallback onTap;
  const _UndoChip({required this.onTap});

  @override
  State<_UndoChip> createState() => _UndoChipState();
}

class _UndoChipState extends State<_UndoChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: Colors.white.withOpacity(0.14),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.undo, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  'Undo rewrite',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
