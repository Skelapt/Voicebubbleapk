import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_service.dart';
import '../../services/continue_service.dart';
import '../../services/reminder_manager.dart';
import '../../models/recording_item.dart';
import '../../models/extracted_outcome.dart';
import '../../models/outcome_type.dart';
import '../../widgets/extracted_outcome_card.dart';
import '../../widgets/add_to_project_dialog.dart';
import 'preset_selection_screen.dart';
import 'recording_screen.dart';

class OutcomesResultScreen extends StatefulWidget {
  final String? continueFromItemId;
  
  const OutcomesResultScreen({
    super.key,
    this.continueFromItemId,
  });

  @override
  State<OutcomesResultScreen> createState() => _OutcomesResultScreenState();
}

class _OutcomesResultScreenState extends State<OutcomesResultScreen> {
  bool _isLoading = true;
  String? _error;
  List<ExtractedOutcome> _outcomes = [];
  bool _showFullContext = false;
  String? _savedItemId;
  final Map<int, String> _outcomeToItemId = {}; // Map outcome index to saved item ID

  @override
  void initState() {
    super.initState();
    _extractOutcomes();
  }

  Future<void> _extractOutcomes() async {
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
      final extractedOutcomes = await aiService.extractOutcomes(
        transcription,
        language.code,
      );

      setState(() {
        _outcomes = extractedOutcomes;
        _isLoading = false;
      });

      // Save each outcome as a separate recording item
      await _saveOutcomes();
      
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

  Future<void> _saveOutcomes() async {
    final appState = context.read<AppStateProvider>();
    final transcription = appState.transcription;
    final preset = appState.selectedPreset;
    final continueContext = appState.continueContext;

    if (preset == null) return;

    try {
      for (int i = 0; i < _outcomes.length; i++) {
        final outcome = _outcomes[i];
        final itemId = const Uuid().v4();
        
        final item = RecordingItem(
          id: itemId,
          rawTranscript: transcription,
          finalText: outcome.text,
          presetUsed: preset.name,
          presetId: preset.id,
          outcomes: [outcome.type.toStorageString()],
          createdAt: DateTime.now(),
          editHistory: [outcome.text],
          continuedFromId: continueContext?.singleItemId,
          contentType: 'voice',
          hiddenInLibrary: true, // CRITICAL: Mark as outcome so it shows in outcomes tab!
        );

        await appState.saveRecording(item);
        
        // Map this outcome index to its saved item ID
        _outcomeToItemId[i] = itemId;
        
        // Add to project if continuing from a project
        if (continueContext?.projectId != null) {
          await appState.addItemToProject(continueContext!.projectId!, itemId);
        }
      }
      
      debugPrint('✅ Saved ${_outcomes.length} outcomes');
    } catch (e) {
      debugPrint('❌ Error saving outcomes: $e');
    }
  }
  
  Future<void> _showReminderPickerForOutcome(int outcomeIndex) async {
    final itemId = _outcomeToItemId[outcomeIndex];
    if (itemId == null) return;
    
    final appState = context.read<AppStateProvider>();
    final item = appState.allRecordingItems.firstWhere(
      (i) => i.id == itemId,
      orElse: () => appState.allRecordingItems.first,
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

  Future<void> _continueFromOutcome(ExtractedOutcome outcome) async {
    final continueService = ContinueService();
    
    // Find the saved item for this outcome
    final appState = context.read<AppStateProvider>();
    final items = appState.allRecordingItems;
    
    // Find item by matching text (since we just saved it)
    final matchingItem = items.firstWhere(
      (item) => item.finalText == outcome.text,
      orElse: () => items.first,
    );
    
    final continueContext = await continueService.buildContextFromItem(matchingItem.id);
    appState.setContinueContext(continueContext);
    
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => const RecordingScreen(),
        ),
      );
    }
  }

  void _onOutcomeTextChanged(int index, String newText) {
    setState(() {
      _outcomes[index] = ExtractedOutcome(
        id: _outcomes[index].id,
        type: _outcomes[index].type,
        text: newText,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF22D3EE); // Outcomes color

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                  Text(
                    'Outcomes',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primaryColor,
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
                          CircularProgressIndicator(color: primaryColor),
                          const SizedBox(height: 16),
                          Text(
                            'Extracting outcomes...',
                            style: TextStyle(
                              fontSize: 16,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: const Color(0xFFEF4444),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Error extracting outcomes',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
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
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Outcomes count
                              Text(
                                '${_outcomes.length} ${_outcomes.length == 1 ? 'outcome' : 'outcomes'} extracted',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: secondaryTextColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Outcome cards
                              ..._outcomes.asMap().entries.map((entry) {
                                final index = entry.key;
                                final outcome = entry.value;
                                final itemId = _outcomeToItemId[index];
                                final appState = context.read<AppStateProvider>();
                                final savedItem = itemId != null 
                                    ? appState.allRecordingItems.firstWhere(
                                        (i) => i.id == itemId,
                                        orElse: () => appState.allRecordingItems.first,
                                      )
                                    : null;
                                
                                return ExtractedOutcomeCard(
                                  outcome: outcome,
                                  onContinue: () => _continueFromOutcome(outcome),
                                  onTextChanged: (newText) => _onOutcomeTextChanged(index, newText),
                                  savedItem: savedItem,
                                  onReminderPressed: () => _showReminderPickerForOutcome(index),
                                );
                              }).toList(),
                              
                              const SizedBox(height: 24),
                              
                              // Different Style button (smaller and cleaner)
                              Center(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const PresetSelectionScreen(
                                          fromRecording: true,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.auto_awesome, size: 16),
                                  label: const Text(
                                    'Different Style',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF22D3EE),
                                    side: const BorderSide(
                                      color: Color(0xFF22D3EE),
                                      width: 1.5,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Optional: View Full Context section
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showFullContext = !_showFullContext;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: surfaceColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'View Full Context',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                        ),
                                      ),
                                      Icon(
                                        _showFullContext
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        color: secondaryTextColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              if (_showFullContext) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: surfaceColor.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    context.read<AppStateProvider>().transcription,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: secondaryTextColor,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                              
                              const SizedBox(height: 32),
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
