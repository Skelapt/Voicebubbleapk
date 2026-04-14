import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/languages.dart';
import '../services/language_service.dart';
import '../providers/app_state_provider.dart';

class LanguageSelectorPopup extends StatefulWidget {
  const LanguageSelectorPopup({super.key});

  @override
  State<LanguageSelectorPopup> createState() => _LanguageSelectorPopupState();
}

class _LanguageSelectorPopupState extends State<LanguageSelectorPopup> {
  String _searchQuery = '';
  List<String> _favoriteLanguages = [];
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final favorites = await LanguageService.getFavoriteLanguages();
    final selected = await LanguageService.getSelectedLanguage();
    setState(() {
      _favoriteLanguages = favorites;
      _selectedLanguage = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF7C6AE8);

    // Filter languages based on search
    final filteredLanguages = _searchQuery.isEmpty
        ? AppLanguages.all
        : AppLanguages.all.where((lang) {
            final query = _searchQuery.toLowerCase();
            return lang.name.toLowerCase().contains(query) ||
                lang.nativeName.toLowerCase().contains(query) ||
                lang.code.toLowerCase().contains(query);
          }).toList();

    // Separate favorites and non-favorites
    final favoritesList = filteredLanguages
        .where((lang) => _favoriteLanguages.contains(lang.code))
        .toList();
    
    final regularList = filteredLanguages
        .where((lang) => !_favoriteLanguages.contains(lang.code))
        .toList();

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.language, color: primaryColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Language',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        Text(
                          'Which language should AI write in?',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: secondaryTextColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  style: TextStyle(color: textColor, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search languages...',
                    hintStyle: TextStyle(color: secondaryTextColor),
                    prefixIcon: Icon(Icons.search, color: secondaryTextColor),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Language List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // Favorites Section
                  if (favoritesList.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 8),
                          Text(
                            'FAVORITES',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...favoritesList.map((lang) => _buildLanguageItem(
                          lang,
                          surfaceColor,
                          textColor,
                          secondaryTextColor,
                          primaryColor,
                        )),
                    const SizedBox(height: 16),
                  ],

                  // All Languages Section
                  if (regularList.isNotEmpty) ...[
                    if (favoritesList.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'ALL LANGUAGES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                    ...regularList.map((lang) => _buildLanguageItem(
                          lang,
                          surfaceColor,
                          textColor,
                          secondaryTextColor,
                          primaryColor,
                        )),
                  ],

                  // No results
                  if (filteredLanguages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 48,
                              color: secondaryTextColor.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No languages found',
                              style: TextStyle(
                                fontSize: 16,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageItem(
    Language lang,
    Color surfaceColor,
    Color textColor,
    Color secondaryTextColor,
    Color primaryColor,
  ) {
    final isSelected = lang.code == _selectedLanguage;
    final isFavorite = _favoriteLanguages.contains(lang.code);

    return GestureDetector(
      onTap: () async {
        await LanguageService.saveSelectedLanguage(lang.code);
        if (mounted) {
          final appState = context.read<AppStateProvider>();
          appState.setSelectedLanguage(lang);
          Navigator.pop(context, lang);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Language set to ${lang.name}'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withOpacity(0.2)
              : surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // Flag Emoji
            Text(
              lang.flagEmoji,
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(width: 16),
            
            // Language Names
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lang.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  if (lang.nativeName != lang.name)
                    Text(
                      lang.nativeName,
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryTextColor,
                      ),
                    ),
                ],
              ),
            ),

            // Star button
            IconButton(
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? Colors.amber : secondaryTextColor,
                size: 24,
              ),
              onPressed: () async {
                await LanguageService.toggleFavorite(lang.code);
                setState(() {
                  if (isFavorite) {
                    _favoriteLanguages.remove(lang.code);
                  } else {
                    _favoriteLanguages.add(lang.code);
                  }
                });
              },
            ),

            // Checkmark if selected
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: primaryColor,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
