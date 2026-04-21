import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform, File;
import 'package:file_picker/file_picker.dart';
import '../../providers/app_state_provider.dart';
import '../../constants/presets.dart';
import '../../constants/languages.dart';
import '../../models/preset.dart';
import '../../services/analytics_service.dart';
import '../../services/native_overlay_service.dart';
import '../../services/ai_service.dart';
import '../../widgets/continue_banner.dart';
import '../../widgets/language_selector_popup.dart';
import '../main/recording_screen.dart';
import '../main/preset_selection_screen.dart';
import '../settings/settings_screen.dart';
import '../paywall/paywall_screen.dart';
import '../../services/feature_gate.dart';
import '../../services/subscription_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _overlayEnabled = false;
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOverlayStatus();
    _initializeOverlay();
    _checkProStatus();
  }

  Future<void> _checkProStatus() async {
    final isPro = await SubscriptionService().isPro();
    if (mounted && isPro != _isPro) {
      setState(() => _isPro = isPro);
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkProStatus();
    }
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      // App resumed (user came back from settings)
      debugPrint('📱 App resumed, checking overlay status...');
      
      final isActive = await NativeOverlayService.isActive();
      final hasPermission = await NativeOverlayService.checkPermission();
      
      debugPrint('Service active: $isActive, Permission granted: $hasPermission');
      
      // If we have permission but service isn't running, start it
      if (hasPermission && !isActive) {
        debugPrint('🚀 Auto-starting service after permission grant...');
        final started = await NativeOverlayService.showOverlay();
        if (started && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Bubble activated! Look on the left side'),
              backgroundColor: Color(0xFF10B981),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      
      await _checkOverlayStatus();
    }
  }
  
  Future<void> _checkOverlayStatus() async {
    if (Platform.isAndroid) {
      // Check whether the overlay SERVICE is actually running, not just permission
      final isRunning = await NativeOverlayService.isActive();
      debugPrint('📊 Overlay service running: $isRunning');
      setState(() {
        _overlayEnabled = isRunning;
      });
    }
  }
  
  Future<void> _initializeOverlay() async {
    if (Platform.isAndroid) {
      // Check if overlay service is actually running
      final isRunning = await NativeOverlayService.isActive();
      debugPrint('📊 Initial overlay check - service running: $isRunning');
      setState(() {
        _overlayEnabled = isRunning;
      });
    }
  }
  
  Future<void> _toggleOverlay() async {
    if (!Platform.isAndroid) return;

    if (_overlayEnabled) {
      // Stop the overlay service
      debugPrint('🛑 Stopping overlay service...');
      await NativeOverlayService.hideOverlay();
      setState(() {
        _overlayEnabled = false;
      });
      // Track overlay deactivated
      AnalyticsService().logOverlayActivated(isEnabled: false);
      debugPrint('✅ Overlay service stopped');
    } else {
      // Check if we have overlay permission
      debugPrint('🔍 Checking overlay permission...');
      final hasPermission = await NativeOverlayService.checkPermission();
      debugPrint('Permission status: $hasPermission');
      
      if (!hasPermission) {
        // Request overlay permission
        debugPrint('📱 Requesting overlay permission...');
        
        // Show instruction dialog FIRST
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Enable Overlay Permission'),
              content: const Text(
                'To use the floating bubble:\n\n'
                '1. Find "VoiceBubble" in the list\n'
                '2. Turn ON "Allow display over other apps"\n'
                '3. Press back to return here\n\n'
                'Tap OK to open settings now.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        
        await NativeOverlayService.requestPermission();
        
        // Give user time to enable permission
        await Future.delayed(const Duration(seconds: 1));
        
        // Check if permission was granted
        final permissionGranted = await NativeOverlayService.checkPermission();
        debugPrint('Permission granted: $permissionGranted');
        
        if (permissionGranted && mounted) {
          // Start the overlay service
          debugPrint('🚀 Starting overlay service...');
          final started = await NativeOverlayService.showOverlay();
          debugPrint('Service started: $started');

          setState(() {
            _overlayEnabled = started;
          });

          if (started && mounted) {
            // Track overlay activated
            AnalyticsService().logOverlayActivated(isEnabled: true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✓ Bubble activated! Close and reopen app to refresh status.'),
                backgroundColor: Color(0xFF10B981),
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        // We have permission, start the overlay service
        debugPrint('🚀 Starting overlay service (permission already granted)...');
        final started = await NativeOverlayService.showOverlay();
        debugPrint('Service started: $started');

        setState(() {
          _overlayEnabled = started;
        });

        if (started && mounted) {
          // Track overlay activated
          AnalyticsService().logOverlayActivated(isEnabled: true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Bubble activated! Close and reopen app to refresh status.'),
              backgroundColor: Color(0xFF10B981),
              duration: Duration(seconds: 4),
            ),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Failed to start bubble service'),
              backgroundColor: Color(0xFFEF4444),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }
  
  /// Pick and upload audio file
  Future<void> _pickAudioFile() async {
    try {
      // Show file picker for audio files
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        
        if (!mounted) return;
        
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Transcribing audio...'),
                  ],
                ),
              ),
            ),
          ),
        );
        
        try {
          // Transcribe the audio file
          final aiService = AIService();
          final transcription = await aiService.transcribeAudio(file);
          
          if (!mounted) return;
          Navigator.pop(context); // Close loading dialog
          
          if (transcription.isEmpty) {
            throw Exception('No speech detected in audio file');
          }
          
          // Set transcription in app state
          final appState = context.read<AppStateProvider>();
          appState.setTranscription(transcription);

          // Track usage - estimate audio duration (rough: ~2.5 words/sec speech)
          final wordCount = transcription.split(RegExp(r'\s+')).length;
          final estimatedSeconds = (wordCount / 2.5).round().clamp(10, 300);
          await FeatureGate.trackSTTUsage(estimatedSeconds);

          // Track audio file upload
          AnalyticsService().logAudioFileUploaded(
            durationSeconds: estimatedSeconds,
            fileType: result.files.single.extension ?? 'unknown',
          );

          // Navigate to preset selection
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PresetSelectionScreen(fromRecording: true),
            ),
          );
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Transcribed: ${transcription.substring(0, transcription.length > 50 ? 50 : transcription.length)}...'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 3),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          Navigator.pop(context); // Close loading dialog
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to transcribe audio: ${e.toString()}'),
              backgroundColor: const Color(0xFFEF4444),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick file: ${e.toString()}'),
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = const Color(0xFF0D0D1A); // Always black
    final surfaceColor = const Color(0xFF1A1A2E); // Dark gray for cards
    final textColor = Colors.white; // Always white text
    final secondaryTextColor = const Color(0xFF94A3B8); // Light gray
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Continue Banner (if context exists)
            const ContinueBanner(),
            
            // Main Content
            Expanded(
              child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              // Header (stays at top)
              Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // VoiceBubble text with tagline (NO ICONS)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VoiceBubble',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Speak, AI Writes, Done',
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  // Premium & Settings Icons
                  Row(
                    children: [
                      if (_isPro)
                        // Pro badge
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: const Center(
                            child: Text('⭐', style: TextStyle(fontSize: 18)),
                          ),
                        )
                      else
                        // Upgrade/Paywall Icon
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
                      const SizedBox(width: 8),
                      // Settings Button
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          ),
                          icon: Icon(Icons.settings, color: textColor, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Add spacing before main content
            const SizedBox(height: 32),
            
            // Main content area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                    // Record Button
                    const SizedBox(height: 40),
                    GestureDetector(
                      onTap: () {
                        context.read<AppStateProvider>().reset();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RecordingScreen(),
                          ),
                        );
                      },
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.5),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.mic,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tap to speak',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Emails, texts & replies — in seconds',
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 80),
                    
                    // Language Selector with Plus Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      child: Consumer<AppStateProvider>(
                        builder: (context, appState, _) {
                          final language = appState.selectedLanguage;
                          final primaryColor = const Color(0xFF7C6AE8);
                          return Row(
                            children: [
                              // Language Selector (left)
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    await showDialog(
                                      context: context,
                                      builder: (context) => const LanguageSelectorPopup(),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: surfaceColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: primaryColor.withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          language.flagEmoji,
                                          style: const TextStyle(fontSize: 32),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Output Language',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: secondaryTextColor,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                language.name,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: textColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                          color: secondaryTextColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Plus Button (right) - shows menu with Upload Audio and Activate Bubble
                              GestureDetector(
                                onTap: () {
                                  _showOptionsMenu(context, surfaceColor, textColor);
                                },
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showOptionsMenu(BuildContext context, Color surfaceColor, Color textColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // ════════════════════════════════════════════════════
              // UPLOAD AUDIO - EXISTING (with Pro badge)
              // ════════════════════════════════════════════════════
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.upload_file, color: Color(0xFFF59E0B)),
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFD700),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.workspace_premium, size: 10, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
                title: Text(
                  'Upload Audio',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  'Pro feature - Transcribe audio files',
                  style: TextStyle(
                    color: textColor.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);

                  // Upload Audio is Pro-only - check Pro status first
                  final isPro = await FeatureGate.isPro();

                  if (!isPro) {
                    // Show paywall for free users
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => PaywallScreen(
                          onSubscribe: () => Navigator.pop(context),
                          onRestore: () => Navigator.pop(context),
                          onClose: () => Navigator.pop(context),
                        ),
                      );
                    }
                    return;
                  }

                  // Pro user - check if they have remaining time
                  final canUse = await FeatureGate.canUseSTT(context);
                  if (!canUse) {
                    return; // FeatureGate already showed dialog
                  }

                  _pickAudioFile();
                },
              ),
              Divider(height: 1, color: Colors.white.withOpacity(0.1)),

              // ════════════════════════════════════════════════════
              // ACTIVATE BUBBLE - EXISTING (Android only)
              // ════════════════════════════════════════════════════
              if (Platform.isAndroid)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (_overlayEnabled ? const Color(0xFF10B981) : const Color(0xFF3B82F6)).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.bubble_chart,
                      color: _overlayEnabled ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                    ),
                  ),
                  title: Text(
                    _overlayEnabled ? 'Deactivate Voice Bubble' : 'Activate Voice Bubble',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    _overlayEnabled
                        ? 'Bubble is active - Tap to disable'
                        : 'Floating record button',
                    style: TextStyle(
                      color: textColor.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _toggleOverlay();
                    await Future.delayed(const Duration(milliseconds: 500));
                    await _checkOverlayStatus();
                  },
                ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetCard(
    BuildContext context,
    Preset preset,
    Color surfaceColor,
    Color textColor,
  ) {
    final gradients = {
      'magic': [const Color(0xFF9333EA), const Color(0xFFEC4899)],
      'email_professional': [const Color(0xFF3B82F6), const Color(0xFF06B6D4)],
      'email_casual': [const Color(0xFF10B981), const Color(0xFF14B8A6)],
      'quick_reply': [const Color(0xFFF59E0B), const Color(0xFFF97316)],
      'dating_opener': [const Color(0xFFEC4899), const Color(0xFFEF4444)],
      'dating_reply': [const Color(0xFFF472B6), const Color(0xFFEC4899)],
      'social_viral_caption': [const Color(0xFFEF4444), const Color(0xFFF97316)],
      'social_viral_video': [const Color(0xFF8B5CF6), const Color(0xFFEC4899)],
      'rewrite_enhance': [const Color(0xFF06B6D4), const Color(0xFF3B82F6)],
      'shorten': [const Color(0xFF10B981), const Color(0xFF059669)],
      'expand': [const Color(0xFFF59E0B), const Color(0xFFD97706)],
      'formal_business': [const Color(0xFF1E40AF), const Color(0xFF3B82F6)],
    };
    
    final gradient = gradients[preset.id] ?? [const Color(0xFF9333EA), const Color(0xFFEC4899)];
    
    return GestureDetector(
      onTap: () {
        context.read<AppStateProvider>().setSelectedPreset(preset);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const RecordingScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                preset.icon,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              preset.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// Animated Feature Card with classy pulsing glow effect
class _AnimatedFeatureCard extends StatefulWidget {
  final IconData icon;
  final String text;
  final List<Color> gradientColors;

  const _AnimatedFeatureCard({
    required this.icon,
    required this.text,
    required this.gradientColors,
  });

  @override
  State<_AnimatedFeatureCard> createState() => _AnimatedFeatureCardState();
}

class _AnimatedFeatureCardState extends State<_AnimatedFeatureCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.white;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.gradientColors[0].withOpacity(0.15),
                widget.gradientColors[1].withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.gradientColors[0].withOpacity(0.3 * _pulseAnimation.value),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.gradientColors[0].withOpacity(0.15 * _pulseAnimation.value),
                blurRadius: 20 * _pulseAnimation.value,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              // Animated icon container with glow
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: widget.gradientColors[0].withOpacity(0.4 * _pulseAnimation.value),
                      blurRadius: 12 * _pulseAnimation.value,
                      spreadRadius: 2 * _pulseAnimation.value,
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
