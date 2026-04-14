import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_service.dart';
import '../../services/analytics_service.dart';
import '../../services/feature_gate.dart';
import '../../services/usage_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/usage_display_widget.dart';
import '../../models/recording_item.dart';
import 'package:uuid/uuid.dart';
import 'preset_selection_screen.dart';
import 'result_screen.dart';
import 'recording_detail_screen.dart';

class RecordingScreen extends StatefulWidget {
  final bool isInstructionsMode;
  
  const RecordingScreen({
    super.key,
    this.isInstructionsMode = false,
  });
  
  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with SingleTickerProviderStateMixin {
  // Audio recorder for high-quality Whisper transcription
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AIService _aiService = AIService();
  
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isProcessing = false;
  String? _audioPath;
  late AnimationController _pulseController;
  
  // Timer
  Timer? _timer;
  Timer? _waveTimer;
  int _recordingSeconds = 0;
  int _recordingMilliseconds = 0;
  
  // Sound wave animation - more bars for the waveform effect
  final int _waveBarCount = 50;
  List<double> _waveHeights = [];
  double _currentSoundLevel = 0.0;
  double _targetSoundLevel = 0.3;
  final Random _random = Random();

  // Usage limit tracking
  int _remainingSeconds = 300;
  bool _isPro = false;
  bool _limitReached = false;
  
  // App colors
  final Color _primaryBlue = const Color(0xFF7C6AE8);
  final Color _darkBlue = const Color(0xFF5B4BC9);
  
  @override
  void initState() {
    super.initState();
    _waveHeights = List.generate(_waveBarCount, (index) => 0.1 + _random.nextDouble() * 0.2);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Check if user can record BEFORE starting
    _checkCanRecordAndStart();
  }

  Future<void> _checkCanRecordAndStart() async {
    final canRecord = await FeatureGate.canUseSTT(context);

    if (!canRecord) {
      // No time left - FeatureGate already showed upgrade dialog
      if (mounted) Navigator.pop(context);
      return;
    }

    // Has time - proceed
    await _loadRemainingTime();
    _startRecording();
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    _waveTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }
  
  void _startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isPaused) {
        setState(() {
          _recordingMilliseconds += 100;
          if (_recordingMilliseconds >= 1000) {
            _recordingMilliseconds = 0;
            _recordingSeconds++;

            // Auto-stop when limit reached
            if (_recordingSeconds >= _remainingSeconds && !_isProcessing && !_limitReached) {
              _limitReached = true;
              _autoStopDueToLimit();
            }
          }
        });
      }
    });
  }
  
  void _startWaveAnimation() {
    _waveTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isPaused && mounted) {
        setState(() {
          // Smoothly interpolate toward target sound level
          _currentSoundLevel = _currentSoundLevel * 0.7 + _targetSoundLevel * 0.3;

          // Shift all bars to the left
          for (int i = 0; i < _waveHeights.length - 1; i++) {
            _waveHeights[i] = _waveHeights[i + 1];
          }

          // Generate new bar on the right with variation based on sound level
          final baseHeight = _currentSoundLevel * 0.6 + 0.1;
          final variation = _random.nextDouble() * 0.3 * _currentSoundLevel;
          _waveHeights[_waveHeights.length - 1] = (baseHeight + variation).clamp(0.08, 1.0);
        });
      }
    });
  }

  Future<void> _loadRemainingTime() async {
    try {
      final usageService = UsageService();
      final subService = SubscriptionService();
      _isPro = await subService.isPro();
      _remainingSeconds = await usageService.getRemainingSeconds(isPro: _isPro);
      if (mounted) setState(() {});
    } catch (e) {
      _remainingSeconds = 300;
    }
  }

  Future<void> _autoStopDueToLimit() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isPro
            ? 'Monthly limit reached. Recording stopped.'
            : 'Free limit reached (5 min). Upgrade for more!'),
          backgroundColor: const Color(0xFFF59E0B),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    await _stopRecording();
  }

  String _formatTime() {
    final minutes = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordingSeconds % 60).toString().padLeft(2, '0');
    final millis = (_recordingMilliseconds ~/ 100).toString();
    return '$minutes:$seconds.$millis';
  }
  
  void _updateWaveHeights(double soundLevel) {
    // Normalize sound level (typically -2 to 10, we want 0.1 to 1.0)
    final normalizedLevel = ((soundLevel.clamp(-2, 8) + 2) / 10).clamp(0.1, 1.0);
    
    // Shift existing waves to the left and add new one at the end
    setState(() {
      for (int i = 0; i < _waveHeights.length - 1; i++) {
        _waveHeights[i] = _waveHeights[i + 1];
      }
      // Add some randomness to make it look more natural
      _waveHeights[_waveHeights.length - 1] = 
          (normalizedLevel * 0.6 + 0.1 + _random.nextDouble() * 0.3).clamp(0.1, 1.0);
    });
  }
  
  Future<void> _startRecording() async {
    // Track recording started
    AnalyticsService().logRecordingStarted();

    try {
      if (!await _audioRecorder.hasPermission()) {
        print('No microphone permission');
        if (mounted) Navigator.pop(context);
        return;
      }

      final directory = await getTemporaryDirectory();
      _audioPath = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _audioPath!,
      );

      // Use AudioRecorder's amplitude for waveform (no speech_to_text conflict)
      _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        if (!_isPaused && mounted) {
          // Normalize amplitude: amp.current is typically -40 to 0 dB
          final normalized = ((amp.current + 40) / 40).clamp(0.1, 1.0);
          _targetSoundLevel = normalized;
        }
      });

      setState(() => _isRecording = true);
      _startTimer();
      _startWaveAnimation();
      print('Recording started: $_audioPath');
    } catch (e) {
      print('Error starting recording: $e');
      if (mounted) Navigator.pop(context);
    }
  }
  
  Future<void> _pauseRecording() async {
    if (_isPaused) {
      // Resume
      await _audioRecorder.resume();
      setState(() {
        _isPaused = false;
      });
    } else {
      // Pause
      await _audioRecorder.pause();
      setState(() {
        _isPaused = true;
      });
    }
  }
  
  Future<void> _cancelRecording() async {
    _timer?.cancel();
    _waveTimer?.cancel();
    await _audioRecorder.stop();

    if (mounted) {
      Navigator.pop(context);
    }
  }
  
  Future<void> _stopRecording() async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
    });
    
    _timer?.cancel();
    _waveTimer?.cancel();

    try {
      // Stop audio recording
      final path = await _audioRecorder.stop();

      if (path != null && path.isNotEmpty) {
        print('Recording stopped: $path');
        
        // Use Whisper API for final accurate transcription
        final audioFile = File(path);
        
        if (!await audioFile.exists()) {
          throw Exception('Audio file not found');
        }
        
        print('Transcribing audio file (${await audioFile.length()} bytes)...');
        final transcription = await _aiService.transcribeAudio(audioFile);
        
        if (transcription.isEmpty) {
          throw Exception('No transcription received from server');
        }
        
        // Update app state with Whisper result
        if (!mounted) return;
        context.read<AppStateProvider>().setTranscription(transcription);

        // Track STT usage for free/pro limits
        await FeatureGate.trackSTTUsage(_recordingSeconds);

        // Track recording completed
        AnalyticsService().logRecordingCompleted(
          durationSeconds: _recordingSeconds,
          presetId: 'voice_recording',
          language: 'en',
        );

        print('Final transcription: $transcription');
        
        // If in instructions mode, return transcription directly
        if (widget.isInstructionsMode) {
          if (mounted) {
            Navigator.pop(context, transcription);
          }
          return;
        }
        
        // Check if we're continuing from an existing item
        final appState = context.read<AppStateProvider>();
        final continueContext = appState.continueContext;

        if (continueContext != null && continueContext.singleItemId != null) {
          // CONTINUE FLOW: Append raw transcript to the original item
          final originalItem = appState.allRecordingItems.firstWhere(
            (item) => item.id == continueContext.singleItemId,
            orElse: () => appState.allRecordingItems.first,
          );

          if (originalItem.id == continueContext.singleItemId) {
            final appendedText = '${originalItem.finalText}\n\n$transcription';
            final updatedItem = originalItem.copyWith(
              finalText: appendedText,
              clearFormattedContent: true, // Force editor to reload from plain text
              editHistory: [...originalItem.editHistory, transcription],
            );
            await appState.updateRecording(updatedItem);
            debugPrint('✅ Appended transcript to original: ${continueContext.singleItemId}');
          }

          appState.clearContinueContext();

          // Go back to editor (it will rebuild with fresh content)
          if (mounted) {
            Navigator.pop(context);
          }
        } else {
          // NEW RECORDING: Save raw transcript as new item, go straight to editor
          final itemId = const Uuid().v4();
          final item = RecordingItem(
            id: itemId,
            rawTranscript: transcription,
            finalText: transcription,
            presetUsed: 'Raw Voice',
            outcomes: [],
            projectId: null,
            createdAt: DateTime.now(),
            editHistory: [],
            presetId: '',
            contentType: 'voice',
          );

          await appState.saveRecording(item);

          AnalyticsService().logCustomEvent(
            eventName: 'document_created',
            parameters: {
              'document_type': 'voice',
              'source': 'recording',
              'creation_method': 'voice_direct',
            },
          );

          debugPrint('✅ Saved raw transcript as new item: $itemId');

          // Navigate to editor for this new item
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => RecordingDetailScreen(recordingId: itemId),
              ),
            );
          }
        }
      } else {
        throw Exception('No audio recorded');
      }
    } catch (e) {
      print('Error stopping/transcribing: $e');

      AnalyticsService().logError(
        errorType: 'recording_failed',
        errorMessage: e.toString(),
        context: 'recording_screen_stop',
      );

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
      });

      // Show user-friendly error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: Color(0xFFF59E0B), size: 24),
              SizedBox(width: 10),
              Text('Connection Issue', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: const Text(
            'We couldn\'t process your recording right now. Please check your internet connection and try again.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back to home
              },
              child: const Text('Go Back', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
              },
              child: const Text('Try Again', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            // STT Time Remaining Display
            UsageDisplayCompact(),
            
            const SizedBox(height: 20),
            
            // Instructions mode banner (if applicable)
            if (widget.isInstructionsMode) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.mic, color: Color(0xFF3B82F6), size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Speak your instructions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
            
            // Waveform visualization
            Container(
              height: 120,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(_waveBarCount, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: 3,
                    height: (_isPaused ? 0.15 : _waveHeights[index]) * 100,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: _primaryBlue,
                    ),
                  );
                }),
              ),
            ),
            
            const Spacer(),
            
            // Recording label
            Text(
              _isPaused ? 'Paused' : (_isProcessing ? 'Processing...' : 'Recording'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            // Timer
            Text(
              _formatTime(),
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w300,
                color: Colors.white,
                letterSpacing: -2,
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Control buttons
            if (_isProcessing)
              // Processing indicator
              Column(
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation(_primaryBlue),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Getting perfect transcription',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Cancel button
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _cancelRecording,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF2A2A2A),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 32),
                  
                  // Stop button (blue circle with white square)
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _stopRecording,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _primaryBlue,
                          ),
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const SizedBox(height: 14), // Match spacing with other labels
                    ],
                  ),
                  const SizedBox(width: 32),
                  
                  // Pause button
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _pauseRecording,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF2A2A2A),
                          ),
                          child: Icon(
                            _isPaused ? Icons.play_arrow : Icons.pause,
                            color: _isPaused ? _primaryBlue : Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isPaused ? 'Resume' : 'Pause',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            
            const Spacer(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
