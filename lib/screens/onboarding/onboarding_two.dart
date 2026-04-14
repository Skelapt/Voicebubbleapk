import 'package:flutter/material.dart';
import 'dart:math' as math;

class OnboardingTwo extends StatefulWidget {
  final VoidCallback onNext;
  
  const OnboardingTwo({super.key, required this.onNext});

  @override
  State<OnboardingTwo> createState() => _OnboardingTwoState();
}

class _OnboardingTwoState extends State<OnboardingTwo> with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _bubbleController;
  late AnimationController _globeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _bubbleController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();
    
    _globeController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat();
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _bubbleController.dispose();
    _globeController.dispose();
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
            colors: [
              Color(0xFF0D0D1A), // Pure black
              Color(0xFF0A0A0A),
              Color(0xFF1A1A2E),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fadeAnimation.value,
                      child: Transform.translate(
                        offset: Offset(0, _slideAnimation.value),
                        child: child,
                      ),
                    );
                  },
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(32, 60, 32, 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        // Title
                        const Text(
                          'Access Anywhere',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.2,
                            letterSpacing: -1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Floating bubble for rapid voice access',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withOpacity(0.8),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 80),
                        // Floating Bubble Animation
                        _buildFloatingBubbleDemo(),
                        const SizedBox(height: 80),
                        // Tagline
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF7C6AE8).withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Text(
                            'Works over WhatsApp, Gmail, Instagram,\nand any app where you type',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Button
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onNext,
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
                      'Continue',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBubbleDemo() {
    return AnimatedBuilder(
      animation: _bubbleController,
      builder: (context, child) {
        final floatOffset = math.sin(_bubbleController.value * 2 * math.pi) * 15;
        return Transform.translate(
          offset: Offset(0, floatOffset),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing background circle
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              // Main bubble
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF7C6AE8), // Blue
                      Color(0xFF2563EB),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C6AE8).withOpacity(0.6),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              // Orbiting language icons
              ..._buildOrbitingLanguages(),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildOrbitingLanguages() {
    final languages = ['🇺🇸', '🇪🇸', '🇫🇷', '🇩🇪', '🇯🇵', '🇨🇳'];
    return List.generate(languages.length, (index) {
      final angle = (index / languages.length) * 2 * math.pi;
      return AnimatedBuilder(
        animation: _globeController,
        builder: (context, child) {
          final rotationAngle = angle + (_globeController.value * 2 * math.pi);
          final x = math.cos(rotationAngle) * 110;
          final y = math.sin(rotationAngle) * 110;
          return Transform.translate(
            offset: Offset(x, y),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                languages[index],
                style: const TextStyle(fontSize: 20),
              ),
            ),
          );
        },
      );
    });
  }

}
