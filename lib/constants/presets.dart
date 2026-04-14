import 'package:flutter/material.dart';
import '../models/preset.dart';

class AppPresets {
  // Define all preset categories with their presets
  static final List<PresetCategory> categories = [
    // Magic sits alone at the top — no group label
    PresetCategory(
      name: '',
      presets: [
        Preset(
          id: 'magic',
          icon: Icons.auto_awesome,
          name: 'Magic',
          description: 'AI chooses the perfect format for you',
          category: '',
          color: const Color(0xFF9333EA),
        ),
      ],
    ),

    // GROUP: Personal
    PresetCategory(
      name: 'Personal',
      presets: [
        Preset(
          id: 'email_professional',
          icon: Icons.mail,
          name: 'Email \u2013 Professional',
          description: 'Clear professional email',
          category: 'Personal',
          color: const Color(0xFFDC2626),
        ),
        Preset(
          id: 'email_casual',
          icon: Icons.chat_bubble,
          name: 'Email \u2013 Casual',
          description: 'Friendly informal email',
          category: 'Personal',
          color: const Color(0xFF10B981),
        ),
        Preset(
          id: 'quick_reply',
          icon: Icons.flash_on,
          name: 'Quick Reply',
          description: 'Fast, concise response',
          category: 'Personal',
          color: const Color(0xFF0EA5E9),
        ),
        Preset(
          id: 'casual_friendly',
          icon: Icons.emoji_emotions,
          name: 'Make Casual',
          description: 'Friendly conversational tone',
          category: 'Personal',
          color: const Color(0xFFA3E635),
        ),
        Preset(
          id: 'formal_business',
          icon: Icons.business_center,
          name: 'Make Formal',
          description: 'Professional business tone',
          category: 'Personal',
          color: const Color(0xFF0891B2),
        ),
        Preset(
          id: 'shorten',
          icon: Icons.content_cut,
          name: 'Shorten',
          description: 'Reduce length, keep meaning',
          category: 'Personal',
          color: const Color(0xFF8B5CF6),
        ),
        Preset(
          id: 'expand',
          icon: Icons.add_circle,
          name: 'Expand',
          description: 'Add detail and depth',
          category: 'Personal',
          color: const Color(0xFFFB923C),
        ),
      ],
    ),

    // GROUP: Tools
    PresetCategory(
      name: 'Tools',
      presets: [
        Preset(
          id: 'summary',
          icon: Icons.summarize,
          name: 'Summary',
          description: 'Condense into key takeaways',
          category: 'Tools',
          color: const Color(0xFF06B6D4),
        ),
        Preset(
          id: 'meeting_notes',
          icon: Icons.event_note,
          name: 'Meeting Notes',
          description: 'Structured meeting summary',
          category: 'Tools',
          color: const Color(0xFF6366F1),
        ),
        Preset(
          id: 'to_do',
          icon: Icons.check_circle,
          name: 'To-Do List',
          description: 'Convert thoughts to action items',
          category: 'Tools',
          color: const Color(0xFF84CC16),
        ),
        Preset(
          id: 'bullet_points',
          icon: Icons.format_list_bulleted_rounded,
          name: 'Bullet Points',
          description: 'Break down into clear bullet points',
          category: 'Tools',
          color: const Color(0xFF64748B),
        ),
      ],
    ),

    // GROUP: Social
    PresetCategory(
      name: 'Social',
      presets: [
        Preset(
          id: 'instagram_caption',
          icon: Icons.camera_alt,
          name: 'Instagram Caption',
          description: 'Perfect caption with hashtags',
          category: 'Social',
          color: const Color(0xFFD946EF),
        ),
        Preset(
          id: 'instagram_hook',
          icon: Icons.catching_pokemon,
          name: 'Instagram Hook',
          description: 'Attention-grabbing first line',
          category: 'Social',
          color: const Color(0xFFFBBF24),
        ),
        Preset(
          id: 'linkedin_post',
          icon: Icons.work,
          name: 'LinkedIn Post',
          description: 'Professional thought leadership',
          category: 'Social',
          color: const Color(0xFF14B8A6),
        ),
        Preset(
          id: 'x_post',
          icon: Icons.chat,
          name: 'X Post',
          description: 'Viral single post',
          category: 'Social',
          color: const Color(0xFFEC4899),
        ),
        Preset(
          id: 'x_thread',
          icon: Icons.format_list_bulleted,
          name: 'X Thread',
          description: 'Engaging thread with hooks',
          category: 'Social',
          color: const Color(0xFFF97316),
        ),
        Preset(
          id: 'facebook_post',
          icon: Icons.public,
          name: 'Facebook Post',
          description: 'Engaging Facebook content',
          category: 'Social',
          color: const Color(0xFF1E40AF),
        ),
      ],
    ),

    // GROUP: Creative
    PresetCategory(
      name: 'Creative',
      presets: [
        Preset(
          id: 'story_novel',
          icon: Icons.menu_book,
          name: 'Story / Novel',
          description: 'Transform into narrative prose',
          category: 'Creative',
          color: const Color(0xFFF43F5E),
        ),
        Preset(
          id: 'script_dialogue',
          icon: Icons.theater_comedy,
          name: 'Script / Dialogue',
          description: 'Movie or play script format',
          category: 'Creative',
          color: const Color(0xFF06B6D4),
        ),
        Preset(
          id: 'poem',
          icon: Icons.auto_stories,
          name: 'Poem',
          description: 'Create poetic verse',
          category: 'Creative',
          color: const Color(0xFFF59E0B),
        ),
      ],
    ),
  ];

  // Quick access presets for the main screen (show top 4)
  static final List<Preset> quickPresets = [
    Preset(
      id: 'magic',
      icon: Icons.auto_awesome,
      name: 'Magic',
      description: 'AI chooses the perfect format',
      category: '',
      color: const Color(0xFF9333EA),
    ),
    Preset(
      id: 'quick_reply',
      icon: Icons.flash_on,
      name: 'Quick Reply',
      description: 'Fast, concise response',
      category: 'Personal',
      color: const Color(0xFF0EA5E9),
    ),
    Preset(
      id: 'instagram_caption',
      icon: Icons.camera_alt,
      name: 'Instagram Caption',
      description: 'Perfect caption with hashtags',
      category: 'Social',
      color: const Color(0xFFD946EF),
    ),
    Preset(
      id: 'x_thread',
      icon: Icons.format_list_bulleted,
      name: 'X Thread',
      description: 'Engaging Twitter thread',
      category: 'Social',
      color: const Color(0xFFF97316),
    ),
  ];

  // Get all presets as a flat list
  static List<Preset> get allPresets {
    return categories.expand((category) => category.presets).toList();
  }

  // Find preset by ID
  static Preset? findById(String id) {
    try {
      return allPresets.firstWhere((preset) => preset.id == id);
    } catch (e) {
      return null;
    }
  }
}
