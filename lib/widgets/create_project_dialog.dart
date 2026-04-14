import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/app_state_provider.dart';
import '../models/project.dart';
import '../services/analytics_service.dart';

class CreateProjectDialog extends StatefulWidget {
  const CreateProjectDialog({super.key});

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  int _selectedColorIndex = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<List<Color>> get _gradients => [
        [const Color(0xFF3B82F6), const Color(0xFF2563EB)], // Blue
        [const Color(0xFF9333EA), const Color(0xFFEC4899)], // Purple-Pink
        [const Color(0xFF10B981), const Color(0xFF14B8A6)], // Green-Teal
        [const Color(0xFFF59E0B), const Color(0xFFF97316)], // Orange
        [const Color(0xFFEF4444), const Color(0xFFDC2626)], // Red
        [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)], // Violet
      ];

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF7C6AE8);

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Project',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 24),

            // Project Name
            Text(
              'Project Name *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _nameController,
                style: TextStyle(color: textColor, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Enter project name',
                  hintStyle: TextStyle(color: secondaryTextColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Description
            Text(
              'Description (optional)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _descriptionController,
                style: TextStyle(color: textColor, fontSize: 16),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter description',
                  hintStyle: TextStyle(color: secondaryTextColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Color Picker
            Text(
              'Color',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: List.generate(_gradients.length, (index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColorIndex = index;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _gradients[index],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _selectedColorIndex == index
                            ? textColor
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: _selectedColorIndex == index
                        ? Icon(Icons.check, color: textColor, size: 20)
                        : null,
                  ),
                );
              }),
            ),

            const SizedBox(height: 32),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 16,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _createProject,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Create',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _createProject() async {
    debugPrint('🏗️ _createProject called');
    
    final name = _nameController.text.trim();
    debugPrint('🏗️ Project name: "$name"');
    
    if (name.isEmpty) {
      debugPrint('❌ Name is empty, showing error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a project name'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final description = _descriptionController.text.trim();
    debugPrint('🏗️ Description: "$description"');
    debugPrint('🏗️ Selected color index: $_selectedColorIndex');
    
    final appState = context.read<AppStateProvider>();

    final now = DateTime.now();
    final project = Project(
      id: const Uuid().v4(),
      name: name,
      itemIds: [],
      createdAt: now,
      updatedAt: now,
      description: description.isEmpty ? null : description,
      colorIndex: _selectedColorIndex,
    );

    debugPrint('🏗️ Created project object: ${project.id}');
    debugPrint('🏗️ Calling appState.saveProject...');
    
    try {
      await appState.saveProject(project);
      debugPrint('✅ Project saved successfully!');

      // Track project creation
      AnalyticsService().logProjectCreated();

      if (mounted) {
        Navigator.pop(context, project);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created "$name"'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ERROR saving project: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating project: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }
}
