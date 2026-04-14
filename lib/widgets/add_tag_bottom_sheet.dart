import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tag.dart';
import '../services/tag_service.dart';
import '../providers/app_state_provider.dart';
import '../widgets/create_tag_dialog.dart';

class AddTagBottomSheet extends StatefulWidget {
  final String recordingId;
  final List<String> currentTags; // Tag IDs already assigned

  const AddTagBottomSheet({
    super.key,
    required this.recordingId,
    required this.currentTags,
  });

  @override
  State<AddTagBottomSheet> createState() => _AddTagBottomSheetState();
}

class _AddTagBottomSheetState extends State<AddTagBottomSheet> {
  final TagService _tagService = TagService();
  List<Tag> _allTags = [];
  Set<String> _selectedTags = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedTags = Set.from(widget.currentTags);
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _tagService.getAllTags();
    setState(() {
      _allTags = tags;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF1A1A1A);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF7C6AE8);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Icon(Icons.label, color: primaryColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add Tags',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: secondaryTextColor),
                  ),
                ],
              ),
            ),

            // Create new tag button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (context) => const CreateTagDialog(),
                    );
                    if (result == true) {
                      _loadTags();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(color: primaryColor, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Create New Tag',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Tags list
            Flexible(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: primaryColor),
                    )
                  : _allTags.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.label_outline,
                                  size: 48,
                                  color: secondaryTextColor.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No tags yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Create a tag to get started',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondaryTextColor.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _allTags.length,
                          itemBuilder: (context, index) {
                            final tag = _allTags[index];
                            final isSelected = _selectedTags.contains(tag.id);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedTags.remove(tag.id);
                                    } else {
                                      _selectedTags.add(tag.id);
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Color(tag.color).withOpacity(0.2)
                                        : const Color(0xFF2A2A2A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: isSelected
                                        ? Border.all(
                                            color: Color(tag.color),
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      // Color circle
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: Color(tag.color),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Tag name
                                      Expanded(
                                        child: Text(
                                          tag.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                      // Checkmark
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle,
                                          color: Color(tag.color),
                                          size: 24,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Save button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await _saveTags();
                    if (mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save Tags',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveTags() async {
    final appState = context.read<AppStateProvider>();
    
    // Remove tags that were unchecked
    for (final tagId in widget.currentTags) {
      if (!_selectedTags.contains(tagId)) {
        await appState.removeTagFromRecording(widget.recordingId, tagId);
      }
    }
    
    // Add tags that were checked
    for (final tagId in _selectedTags) {
      if (!widget.currentTags.contains(tagId)) {
        await appState.addTagToRecording(widget.recordingId, tagId);
      }
    }
  }
}
