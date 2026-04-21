import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF5F5F7);
    final surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1F2937);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    final primaryColor = isDark ? const Color(0xFFA855F7) : const Color(0xFF9333EA);
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
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
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: textColor, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Help & Support',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  _buildFAQItem(
                    'How do I use VoiceBubble?',
                    'Simply tap the microphone button, speak naturally, and then choose a writing style. VoiceBubble will transform your speech into perfectly written text.',
                    textColor,
                    secondaryTextColor,
                    surfaceColor,
                  ),
                  
                  _buildFAQItem(
                    'How does the floating overlay work?',
                    'On Android, VoiceBubble shows a floating bubble when your keyboard is open. Tap it to quickly record and insert text into any app.',
                    textColor,
                    secondaryTextColor,
                    surfaceColor,
                  ),
                  
                  _buildFAQItem(
                    'What languages are supported?',
                    'Currently, VoiceBubble supports English (US). We\'re working on adding more languages in future updates.',
                    textColor,
                    secondaryTextColor,
                    surfaceColor,
                  ),
                  
                  _buildFAQItem(
                    'Is my voice data secure?',
                    'Yes! Your voice recordings are processed in real-time and immediately deleted. We never permanently store your voice data. Read our Privacy Policy for more details.',
                    textColor,
                    secondaryTextColor,
                    surfaceColor,
                  ),
                  
                  _buildFAQItem(
                    'Can I use VoiceBubble offline?',
                    'VoiceBubble requires an internet connection to process voice recordings and generate text using AI. An offline mode is planned for future updates.',
                    textColor,
                    secondaryTextColor,
                    surfaceColor,
                  ),
                  
                  _buildFAQItem(
                    'What\'s the difference between Free and Pro?',
                    'Free plan includes 10 minutes of STT & AI per month. Pro plan offers 90 minutes monthly, premium AI quality, and exclusive features.',
                    textColor,
                    secondaryTextColor,
                    surfaceColor,
                  ),
                  
                  _buildFAQItem(
                    'How do I cancel my subscription?',
                    'You can cancel anytime in your device\'s subscription settings. Your Pro features will remain active until the end of the billing period.',
                    textColor,
                    secondaryTextColor,
                    surfaceColor,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Contact Section
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.support_agent,
                          size: 48,
                          color: primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Need More Help?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Our support team is here to help',
                          style: TextStyle(
                            fontSize: 14,
                            color: secondaryTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () async {
                            final Uri emailUri = Uri(
                              scheme: 'mailto',
                              path: 'info@voice-bubble.com',
                              query: 'subject=VoiceBubble Support Request',
                            );
                            try {
                              if (await canLaunchUrl(emailUri)) {
                                await launchUrl(emailUri);
                              }
                            } catch (e) {
                              debugPrint('Error opening email: $e');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                          ),
                          child: const Text('Contact Support'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'info@voice-bubble.com',
                          style: TextStyle(
                            fontSize: 14,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFAQItem(
    String question,
    String answer,
    Color textColor,
    Color secondaryTextColor,
    Color surfaceColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              answer,
              style: TextStyle(
                fontSize: 14,
                color: secondaryTextColor,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

