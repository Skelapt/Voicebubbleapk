import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import '../../services/native_overlay_service.dart';

class PermissionsScreen extends StatelessWidget {
  final VoidCallback onComplete;
  
  const PermissionsScreen({super.key, required this.onComplete});
  
  Future<void> _requestPermissions(BuildContext context) async {
    debugPrint('🔐 Starting permission request flow...');
    
    // Request microphone permission FIRST
    final micStatus = await Permission.microphone.request();
    debugPrint('🎤 Microphone permission: ${micStatus.isGranted}');
    
    if (!micStatus.isGranted) {
      // Show error dialog for microphone permission
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Microphone Permission Required'),
            content: const Text(
              'VoiceBubble needs microphone access to record your voice. Please enable it in settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return;
    }
    
    // Request overlay permission on Android
    if (Platform.isAndroid) {
      // Always open the system \"Display over other apps\" settings screen.
      // Some devices keep this permission across reinstalls, so we don't
      // try to be clever here – we just send the user to the right place.
      debugPrint('🚀 Opening overlay permission settings (always)...');
      await NativeOverlayService.requestPermission();
      debugPrint('⏳ Settings should be open now...');
    }
    
    // Complete onboarding - HomeScreen will handle service start when app resumes
    debugPrint('✅ Permissions flow complete, moving to home screen');
    onComplete();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D0D1A), // Pure black
              Color(0xFF0A0A0A),
              Color(0xFF1A1A2E),
            ],
          ),
        ),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Spacer(),
              // Content
              Column(
                children: [
                  // Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      size: 50,
                      color: Color(0xFF1E88E5),
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Title
                  const Text(
                    'Quick Setup',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.2,
                      letterSpacing: -1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // Description
                  Text(
                    'We need 2 permissions to work perfectly',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // Permission Cards
                  Column(
                    children: [
                      _buildPermissionCard(
                        Icons.mic_rounded,
                        'Microphone',
                        'To record your voice',
                        const Color(0xFF42A5F5),
                      ),
                      const SizedBox(height: 16),
                      _buildPermissionCard(
                        Icons.bubble_chart_rounded,
                        'Display Over Apps',
                        'To show the floating bubble',
                        const Color(0xFF42A5F5),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              // Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _requestPermissions(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C6AE8), // Blue button
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                        shadowColor: const Color(0xFF7C6AE8).withOpacity(0.5),
                      ),
                      child: const Text(
                        'Grant Permissions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onComplete,
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
  
  Widget _buildPermissionCard(
    IconData icon,
    String title,
    String description,
    Color color,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E), // Dark gray
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF7C6AE8).withOpacity(0.3), // Blue border
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C6AE8).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C6AE8), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
