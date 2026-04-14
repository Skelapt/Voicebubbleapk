import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// VOICEBUBBLE ONBOARDING - THE MASTERPIECE
/// ═══════════════════════════════════════════════════════════════════════════

class FeatureShowcaseScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const FeatureShowcaseScreen({super.key, required this.onComplete});
  
  @override
  State<FeatureShowcaseScreen> createState() => _FeatureShowcaseScreenState();
}

class _FeatureShowcaseScreenState extends State<FeatureShowcaseScreen> with TickerProviderStateMixin {
  late AnimationController _loopController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _loopController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _fadeController.forward();
  }

  @override
  void dispose() {
    _loopController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0D1A), Color(0xFF0A0A0A), Color(0xFF0A0A0A)],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) => Opacity(opacity: _fadeAnimation.value, child: child),
            child: Column(
              children: [
                Expanded(
                  child: _Page1Voice(loopController: _loopController),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.onComplete();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C6AE8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
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

// ═══════════════════════════════════════════════════════════════════════════
// PAGE 1: SPEAK. AI WRITES. DONE.
// ═══════════════════════════════════════════════════════════════════════════

class _Page1Voice extends StatelessWidget {
  final AnimationController loopController;
  const _Page1Voice({required this.loopController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loopController,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ...List.generate(3, (i) {
                      final delay = i * 0.33;
                      final progress = (loopController.value + delay) % 1.0;
                      final scale = 1.0 + (progress * 0.6);
                      final opacity = (1.0 - progress) * 0.4;
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 130, height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF7C6AE8).withOpacity(opacity), width: 2),
                          ),
                        ),
                      );
                    }),
                    Container(
                      width: 160, height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFF7C6AE8).withOpacity(0.5), blurRadius: 50, spreadRadius: 15)],
                      ),
                    ),
                    Container(
                      width: 130, height: 130,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C6AE8), Color(0xFF2563EB)]),
                      ),
                      child: const Icon(Icons.mic, size: 60, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 50),
              const Text('Speak.', style: TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
              const Text('AI Writes.', style: TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
              const Text('Done.', style: TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
              const SizedBox(height: 24),
              Text('Stop typing. Just talk.\nPerfectly written messages in seconds.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18, fontWeight: FontWeight.w400, height: 1.5)),
            ],
          ),
        );
      },
    );
  }
}

