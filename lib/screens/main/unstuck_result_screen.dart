import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_service.dart';
import '../../services/reminder_manager.dart';
import '../../models/recording_item.dart';
import '../../models/outcome_type.dart';
import '../../models/unstuck_response.dart';
import '../../widgets/unstuck_action.dart';
import 'preset_selection_screen.dart';

class UnstuckResultScreen extends StatefulWidget {
  final String? continueFromItemId;
  
  const UnstuckResultScreen({
    super.key,
    this.continueFromItemId,
  });

  @override
  State<UnstuckResultScreen> createState() => _UnstuckResultScreenState();
}

class _UnstuckResultScreenState extends State<UnstuckResultScreen> {
  bool _isLoading = true;
  String? _error;
  UnstuckResponse? _unstuckData;
  String? _savedItemId;

  @override
  void initState() {
    super.initState();
    _extractUnstuck();
  }

  Future<void> _extractUnstuck() async {
    final appState = context.read<AppStateProvider>();
    final transcription = appState.transcription;
    final language = appState.selectedLanguage;
    final continueContext = appState.continueContext;

    if (transcription.isEmpty) {
      setState(() {
        _error = 'No transcription available';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final aiService = AIService();
      final unstuckData = await aiService.extractUnstuck(
        transcription,
        language.code,
      );

      setState(() {
        _unstuckData = unstuckData;
        _isLoading = false;
      });

      // Save the task to Outcomes
      await _saveTask();
      
      // Clear continue context after saving
      if (continueContext != null) {
        appState.clearContinueContext();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTask() async {
    if (_unstuckData == null) return;
    
    final appState = context.read<AppStateProvider>();
    final transcription = appState.transcription;
    final preset = appState.selectedPreset;
    final continueContext = appState.continueContext;

    if (preset == null) return;

    try {
      final itemId = const Uuid().v4();
      
      // Save only the task (action) as a RecordingItem
      final item = RecordingItem(
        id: itemId,
        rawTranscript: transcription,
        finalText: _unstuckData!.action,
        presetUsed: preset.name,
        presetId: preset.id,
        outcomes: [OutcomeType.task.toStorageString()],
        createdAt: DateTime.now(),
        editHistory: [_unstuckData!.action],
        continuedFromId: continueContext?.singleItemId,
        contentType: 'voice',
      );

      await appState.saveRecording(item);
      
      // Add to project if continuing from a project
      if (continueContext?.projectId != null) {
        await appState.addItemToProject(continueContext!.projectId!, itemId);
      }
      
      _savedItemId = itemId;
      
      debugPrint('✅ Saved Unstuck task');
    } catch (e) {
      debugPrint('❌ Error saving Unstuck task: $e');
    }
  }

  void _onActionChanged(String newAction) {
    if (_unstuckData != null) {
      setState(() {
        _unstuckData = UnstuckResponse(
          insight: _unstuckData!.insight,
          action: newAction,
        );
      });
    }
  }
  
  Future<void> _showReminderPicker() async {
    if (_savedItemId == null) return;
    
    final appState = context.read<AppStateProvider>();
    final item = appState.recordingItems.firstWhere(
      (i) => i.id == _savedItemId,
      orElse: () => appState.recordingItems.first,
    );
    
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

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final calmColor = const Color(0xFF67E8F9); // Unstuck calm color

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Minimal header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      icon: Icon(Icons.close, color: textColor, size: 20),
                    ),
                  ),
                  Icon(
                    Icons.psychology,
                    color: calmColor,
                    size: 28,
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: calmColor,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.check, color: Colors.black, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: calmColor),
                          const SizedBox(height: 24),
                          Text(
                            'Finding clarity...',
                            style: TextStyle(
                              fontSize: 18,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: const Color(0xFFEF4444),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Unable to process',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: secondaryTextColor,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            children: [
                              const SizedBox(height: 40),
                              
                              // "What's going on" - Insight Section
                              Text(
                                'What\'s going on',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: secondaryTextColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              
                              const SizedBox(height: 20),
                              
                              // Insight text (centered, non-editable)
                              Text(
                                _unstuckData?.insight ?? '',
                                style: TextStyle(
                                  fontSize: 22,
                                  color: textColor,
                                  height: 1.6,
                                  fontWeight: FontWeight.w400,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              
                              const SizedBox(height: 60),
                              
                              // "One small move" - Action Section
                              Text(
                                'One small move',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: secondaryTextColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              
                              const SizedBox(height: 20),
                              
                              // Action widget (editable task)
                              if (_unstuckData != null)
                                UnstuckActionWidget(
                                  initialAction: _unstuckData!.action,
                                  onActionChanged: _onActionChanged,
                                  onReminderTap: _showReminderPicker,
                                ),
                              
                              const SizedBox(height: 60),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
