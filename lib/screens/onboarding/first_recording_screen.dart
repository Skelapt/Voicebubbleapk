import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../services/ai_service.dart';
import '../../services/analytics_service.dart';
import '../../services/feature_gate.dart';
import '../../services/usage_service.dart';

/// Forced first recording screen during onboarding.
/// Full black, glowing record button, no skip option.
/// User must record and get output to proceed.
class FirstRecordingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const FirstRecordingScreen({super.key, required this.onComplete});

  @override
  State<FirstRecordingScreen> createState() => _FirstRecordingScreenState();
}

class _FirstRecordingScreenState extends State<FirstRecordingScreen>
    with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _pulseController;

  // Recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AIService _aiService = AIService();
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _audioPath;

  // Timer
  Timer? _timer;
  Timer? _waveTimer;
  int _recordingSeconds = 0;
  int _recordingMilliseconds = 0;

  // Waveform
  final int _waveBarCount = 50;
  List<double> _waveHeights = [];
  double _currentSoundLevel = 0.0;
  double _targetSoundLevel = 0.3;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _waveHeights = List.generate(_waveBarCount, (i) => 0.1 + _random.nextDouble() * 0.2);

    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _glowController.dispose();
    _pulseController.dispose();
    _timer?.cancel();
    _waveTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  String _formatTime() {
    final minutes = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordingSeconds % 60).toString().padLeft(2, '0');
    final millis = (_recordingMilliseconds ~/ 100).toString();
    return '$minutes:$seconds.$millis';
  }

  Future<void> _startRecording() async {
    HapticFeedback.heavyImpact();
    AnalyticsService().logRecordingStarted();

    try {
      if (!await _audioRecorder.hasPermission()) {
        debugPrint('No microphone permission');
        return;
      }

      final directory = await getTemporaryDirectory();
      _audioPath = '${directory.path}/onboarding_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _audioPath!,
      );

      _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        if (_isRecording && mounted) {
          final normalized = ((amp.current + 40) / 40).clamp(0.1, 1.0);
          _targetSoundLevel = normalized;
        }
      });

      setState(() => _isRecording = true);
      _startTimer();
      _startWaveAnimation();
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _recordingMilliseconds += 100;
        if (_recordingMilliseconds >= 1000) {
          _recordingMilliseconds = 0;
          _recordingSeconds++;
        }
      });
    });
  }

  void _startWaveAnimation() {
    _waveTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_isRecording && mounted) {
        setState(() {
          _currentSoundLevel = _currentSoundLevel * 0.7 + _targetSoundLevel * 0.3;
          for (int i = 0; i < _waveHeights.length - 1; i++) {
            _waveHeights[i] = _waveHeights[i + 1];
          }
          final baseHeight = _currentSoundLevel * 0.6 + 0.1;
          final variation = _random.nextDouble() * 0.3 * _currentSoundLevel;
          _waveHeights[_waveHeights.length - 1] = (baseHeight + variation).clamp(0.08, 1.0);
        });
      }
    });
  }

  Future<void> _stopRecording() async {
    if (_isProcessing) return;

    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);
    _timer?.cancel();
    _waveTimer?.cancel();

    try {
      final path = await _audioRecorder.stop();

      if (path != null && path.isNotEmpty) {
        final audioFile = File(path);
        if (!await audioFile.exists()) {
          throw Exception('Audio file not found');
        }

        final transcription = await _aiService.transcribeAudio(audioFile);
        if (transcription.isEmpty) {
          throw Exception('No transcription received');
        }

        if (!mounted) return;
        context.read<AppStateProvider>().setTranscription(transcription);

        // Track usage
        await FeatureGate.trackSTTUsage(_recordingSeconds);
        AnalyticsService().logRecordingCompleted(
          durationSeconds: _recordingSeconds,
          presetId: 'onboarding_first_recording',
          language: 'en',
        );

        // Grant the 10 extra free minutes bonus
        await UsageService().claimOnboardingBonus();

        // Recording complete with output — onboarding done, go to home
        if (mounted) {
          widget.onComplete();
        }
      } else {
        throw Exception('No audio recorded');
      }
    } catch (e) {
      debugPrint('Error in first recording: $e');
      if (!mounted) return;

      setState(() => _isProcessing = false);

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
            'We couldn\'t process your recording. Please check your internet connection and try again.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isRecording || _isProcessing ? _buildRecordingView() : _buildIdleView(),
      ),
    );
  }

  Widget _buildIdleView() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        final glowIntensity = 0.3 + (_glowController.value * 0.4);
        return Column(
          children: [
            const Spacer(flex: 3),
            // Title text
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Try it now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                  letterSpacing: -1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'earn 10 extra free minutes.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(flex: 2),
            // Glowing record button
            GestureDetector(
              onTap: _startRecording,
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow rings
                    ...List.generate(3, (i) {
                      final ringOpacity = glowIntensity * (0.3 - (i * 0.08));
                      final ringSize = 160.0 + (i * 30.0);
                      return Container(
                        width: ringSize,
                        height: ringSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF3B82F6).withOpacity(ringOpacity.clamp(0.0, 1.0)),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                    // Glow shadow
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF3B82F6).withOpacity(glowIntensity),
                            blurRadius: 60,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                    ),
                    // Button
                    Container(
                      width: 120,
                      height: 120,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                        ),
                      ),
                      child: const Icon(Icons.mic, size: 56, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(flex: 2),
            // Tap to record hint
            Text(
              'Tap to record',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(flex: 1),
          ],
        );
      },
    );
  }

  Widget _buildRecordingView() {
    return Column(
      children: [
        const SizedBox(height: 40),
        // Waveform
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
                height: (_isProcessing ? 0.15 : _waveHeights[index]) * 100,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: const Color(0xFF3B82F6),
                ),
              );
            }),
          ),
        ),
        const Spacer(),
        // Status label
        Text(
          _isProcessing ? 'Processing...' : 'Recording',
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
        // Stop button or processing indicator
        if (_isProcessing)
          Column(
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Getting perfect transcription',
                style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              ),
            ],
          )
        else
          GestureDetector(
            onTap: _stopRecording,
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF3B82F6),
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
        const Spacer(),
        const SizedBox(height: 40),
      ],
    );
  }
}
