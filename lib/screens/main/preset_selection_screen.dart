import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../constants/presets.dart';
import '../../models/preset.dart';
import '../../services/analytics_service.dart';
import '../../services/preset_favorites_service.dart';
import 'recording_screen.dart';
import 'result_screen.dart';

class PresetSelectionScreen extends StatefulWidget {
  final bool fromRecording;
  final String? continueFromItemId;

  const PresetSelectionScreen({
    super.key,
    this.fromRecording = false,
    this.continueFromItemId,
  });

  @override
  State<PresetSelectionScreen> createState() => _PresetSelectionScreenState();
}

class _PresetSelectionScreenState extends State<PresetSelectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final PresetFavoritesService _favoritesService = PresetFavoritesService();
  Set<String> _favoritePresetIds = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
  }

  Future<void> _loadFavorites() async {
    final favorites = await _favoritesService.getFavorites();
    setState(() {
      _favoritePresetIds = favorites.toSet();
    });
  }

  Future<void> _toggleFavorite(String presetId) async {
    HapticFeedback.lightImpact();
    await _favoritesService.toggleFavorite(presetId);
    await _loadFavorites();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handlePresetSelection(BuildContext context, Preset preset) {
    HapticFeedback.lightImpact();
    AnalyticsService().logPresetSelected(
      presetId: preset.id,
      presetName: preset.name,
    );

    final appState = context.read<AppStateProvider>();
    appState.setSelectedPreset(preset);

    if (widget.fromRecording && appState.transcription.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const ResultScreen(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const RecordingScreen(),
        ),
      );
    }
  }

  /// Build the ordered list of sections: favorites (if any), then categories
  List<Widget> _buildSections() {
    final sections = <Widget>[];

    // Collect all favorited presets across all categories
    if (_favoritePresetIds.isNotEmpty) {
      final allPresets = AppPresets.allPresets;
      final favoritePresets = allPresets
          .where((p) => _favoritePresetIds.contains(p.id))
          .toList();

      if (favoritePresets.isNotEmpty) {
        sections.add(_buildSectionLabel('FAVOURITES'));
        for (final preset in favoritePresets) {
          sections.add(_buildPresetTile(preset));
        }
        sections.add(const SizedBox(height: 8));
      }
    }

    // Then each category
    for (final category in AppPresets.categories) {
      // Section label (skip for Magic which has empty name)
      if (category.name.isNotEmpty) {
        sections.add(_buildSectionLabel(category.name.toUpperCase()));
      }

      for (final preset in category.presets) {
        sections.add(_buildPresetTile(preset));
      }
      sections.add(const SizedBox(height: 8));
    }

    return sections;
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white.withOpacity(0.3),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildPresetTile(Preset preset) {
    final isFavorite = _favoritePresetIds.contains(preset.id);
    final presetColor = preset.color ?? const Color(0xFF3B82F6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _PresetTile(
        preset: preset,
        presetColor: presetColor,
        isFavorite: isFavorite,
        onTap: () => _handlePresetSelection(context, preset),
        onToggleFavorite: () => _toggleFavorite(preset.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOut,
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(36),
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                    const Text(
                      'Choose Style',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 36),
                  ],
                ),
              ),

              // Preset list
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  children: _buildSections(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin, clean preset tile with icon, name, description, star, and chevron.
class _PresetTile extends StatefulWidget {
  final Preset preset;
  final Color presetColor;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const _PresetTile({
    required this.preset,
    required this.presetColor,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.presetColor.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.presetColor.withOpacity(0.85),
                      widget.presetColor.withOpacity(0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.preset.icon,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              // Name and description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.preset.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.preset.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.4),
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Favorite star
              GestureDetector(
                onTap: widget.onToggleFavorite,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    widget.isFavorite ? Icons.star : Icons.star_border,
                    size: 22,
                    color: widget.isFavorite
                        ? const Color(0xFFFBBF24)
                        : Colors.white.withOpacity(0.2),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.white.withOpacity(0.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
