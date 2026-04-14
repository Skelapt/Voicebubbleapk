import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recording_item.dart';
import '../models/project.dart';
import '../services/batch_operations_service.dart';
import '../providers/app_state_provider.dart';
import '../services/export_service.dart';
import '../services/project_service.dart';
import '../widgets/create_project_dialog.dart';
import '../widgets/create_tag_dialog.dart';
import '../services/analytics_service.dart';

class BatchOperationsScreen extends StatefulWidget {
  final List<RecordingItem> allNotes;
  final Function(List<RecordingItem>) onComplete;

  const BatchOperationsScreen({
    super.key,
    required this.allNotes,
    required this.onComplete,
  });

  @override
  State<BatchOperationsScreen> createState() => _BatchOperationsScreenState();
}

class _BatchOperationsScreenState extends State<BatchOperationsScreen> {
  final Set<String> _selectedIds = {};
  final _batchService = BatchOperationsService();
  final _exportService = ExportService();
  final _projectService = ProjectService();

  bool get _hasSelection => _selectedIds.isNotEmpty;
  bool get _allSelected => _selectedIds.length == widget.allNotes.length;

  List<RecordingItem> get _selectedNotes {
    return widget.allNotes.where((n) => _selectedIds.contains(n.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF7C6AE8);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () {
            widget.onComplete(_selectedNotes);
            Navigator.pop(context);
          },
        ),
        title: Text(
          _hasSelection
              ? '${_selectedIds.length} selected'
              : 'Select Notes',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _toggleSelectAll,
            child: Text(
              _allSelected ? 'Deselect All' : 'Select All',
              style: TextStyle(color: primaryColor),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Notes list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.allNotes.length,
              itemBuilder: (context, index) {
                final note = widget.allNotes[index];
                final isSelected = _selectedIds.contains(note.id);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => _toggleSelection(note.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? primaryColor
                              : Colors.white.withOpacity(0.1),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Checkbox
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected ? primaryColor : Colors.transparent,
                              border: Border.all(
                                color: isSelected ? primaryColor : secondaryTextColor,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),

                          const SizedBox(width: 16),

                          // Note info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note.customTitle ?? _getPreviewText(note.finalText),
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  note.formattedDate,
                                  style: TextStyle(
                                    color: secondaryTextColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Action bar
          if (_hasSelection)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _ActionButton(
                          icon: Icons.delete,
                          label: 'Delete',
                          color: const Color(0xFFEF4444),
                          onTap: _showDeleteConfirmation,
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.local_offer,
                          label: 'Tag',
                          color: primaryColor,
                          onTap: _showTagSelection,
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.folder,
                          label: 'Project',
                          color: const Color(0xFF8B5CF6),
                          onTap: _showProjectSelection,
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          icon: Icons.download,
                          label: 'Export',
                          color: const Color(0xFF10B981),
                          onTap: _showExportOptions,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(widget.allNotes.map((n) => n.id));
      }
    });
  }

  String _getPreviewText(String text) {
    if (text.isEmpty) return 'Untitled';
    final firstLine = text.split('\n').first.trim();
    return firstLine.length > 50 ? '${firstLine.substring(0, 47)}...' : firstLine;
  }

  // DELETE
  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Delete Notes?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedIds.length} note(s)? This cannot be undone.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteSelected();
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final appState = context.read<AppStateProvider>();
    await _batchService.deleteNotes(_selectedNotes, appState);

    setState(() {
      _selectedIds.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notes deleted'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      widget.onComplete([]);
      Navigator.pop(context);
    }
  }

  // TAG SELECTION
  void _showTagSelection() async {
    final appState = context.read<AppStateProvider>();

    // Always refresh tags first to get latest
    await appState.refreshTags();

    var availableTags = appState.tags;

    // If no tags, offer to create one
    if (availableTags.isEmpty) {
      // Show create tag option instead of just error message
      final shouldCreate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'No Tags Available',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'You don\'t have any tags yet. Would you like to create one now?',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Create Tag',
                style: TextStyle(color: Color(0xFF3B82F6)),
              ),
            ),
          ],
        ),
      );

      if (shouldCreate == true && mounted) {
        // Show create tag dialog
        await showDialog(
          context: context,
          builder: (context) => const CreateTagDialog(),
        );
        
        // Wait a moment for state to update, then check tags
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (mounted) {
          final updatedAppState = context.read<AppStateProvider>();
          final updatedTags = updatedAppState.tags;
          
          // If we now have tags, show selection dialog directly (no recursion)
          if (updatedTags.isNotEmpty) {
            final selectedTagId = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                title: const Text(
                  'Add Tag to Notes',
                  style: TextStyle(color: Colors.white),
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: updatedTags.length,
                    itemBuilder: (context, index) {
                      final tag = updatedTags[index];
                      return ListTile(
                        leading: const Icon(Icons.local_offer, color: Color(0xFF3B82F6)),
                        title: Text(
                          tag.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () => Navigator.pop(context, tag.id),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ),
            );

            if (selectedTagId != null && mounted) {
              await _batchService.addTagToNotes(_selectedNotes, selectedTagId, updatedAppState);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tag added to selected notes'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
                widget.onComplete(_selectedNotes);
                Navigator.pop(context);
              }
            }
          }
        }
      }
      return;
    }

    final selectedTagId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Add Tag to Notes',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableTags.length,
            itemBuilder: (context, index) {
              final tag = availableTags[index];
              return ListTile(
                leading: const Icon(Icons.local_offer, color: Color(0xFF3B82F6)),
                title: Text(
                  tag.name,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, tag.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );

    if (selectedTagId != null) {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adding tag to ${_selectedNotes.length} notes...'),
            backgroundColor: const Color(0xFF3B82F6),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      final appState = context.read<AppStateProvider>();
      await _batchService.addTagToNotes(_selectedNotes, selectedTagId, appState);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tag added to ${_selectedNotes.length} notes!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        setState(() => _selectedIds.clear());
      }
    }
  }

  // PROJECT SELECTION
  void _showProjectSelection() async {
    final appState = context.read<AppStateProvider>();

    // Use appState.projects for reactive updates
    final projects = appState.projects;

    if (projects.isEmpty) {
      // Show create project option instead of just error message
      final shouldCreate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'No Projects Available',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'You don\'t have any projects yet. Would you like to create one now?',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Create Project',
                style: TextStyle(color: Color(0xFF8B5CF6)),
              ),
            ),
          ],
        ),
      );

      if (shouldCreate == true && mounted) {
        // Show create project dialog
        await showDialog(
          context: context,
          builder: (context) => const CreateProjectDialog(),
        );
        // After creating, try showing project selection again (appState will have updated)
        if (mounted && context.read<AppStateProvider>().projects.isNotEmpty) {
          _showProjectSelection();
        }
      }
      return;
    }

    final selectedProjectId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Add to Project',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFF8B5CF6)),
                title: Text(
                  project.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${project.itemIds.length} items',
                  style: const TextStyle(color: Color(0xFF94A3B8)),
                ),
                onTap: () => Navigator.pop(context, project.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );

    if (selectedProjectId != null) {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adding ${_selectedNotes.length} notes to project...'),
            backgroundColor: const Color(0xFF3B82F6),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // FIX: Use appState.addItemToProject directly for reactive UI updates
      for (final note in _selectedNotes) {
        await appState.addItemToProject(selectedProjectId, note.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedNotes.length} notes added to project!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
        setState(() => _selectedIds.clear());
      }
    }
  }

  // EXPORT OPTIONS
  void _showExportOptions() async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Export Format',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444)),
              title: const Text('PDF', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Professional document', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Color(0xFF3B82F6)),
              title: const Text('Markdown', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Plain text with formatting', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              onTap: () => Navigator.pop(context, 'markdown'),
            ),
            ListTile(
              leading: const Icon(Icons.language, color: Color(0xFFF97316)),
              title: const Text('HTML', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Web page format', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              onTap: () => Navigator.pop(context, 'html'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields, color: Color(0xFF10B981)),
              title: const Text('Plain Text', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Simple .txt file', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              onTap: () => Navigator.pop(context, 'text'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );

    if (format != null) {
      await _exportMultipleNotes(format);
    }
  }

  Future<void> _exportMultipleNotes(String format) async {
    AnalyticsService().logCustomEvent(
      eventName: 'batch_export_started',
      parameters: {
        'format': format,
        'item_count': _selectedNotes.length,
      },
    );

    // Show loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Text('Exporting ${_selectedNotes.length} notes as ${format.toUpperCase()}...'),
            ],
          ),
          backgroundColor: const Color(0xFF3B82F6),
          duration: const Duration(seconds: 30),
        ),
      );
    }

    try {
      // Export each note
      for (var i = 0; i < _selectedNotes.length; i++) {
        final note = _selectedNotes[i];
        
        // Debug: Check if note has content
        debugPrint('🔍 Exporting note ${i+1}: finalText="${note.finalText}", formattedContent="${note.formattedContent}"');
        
        late final file;
        switch (format) {
          case 'pdf':
            file = await _exportService.exportAsPdf(note);
            break;
          case 'markdown':
            file = await _exportService.exportAsMarkdown(note);
            break;
          case 'html':
            file = await _exportService.exportAsHtml(note);
            break;
          case 'text':
            file = await _exportService.exportAsText(note);
            break;
        }
        
        // Share each file
        await _exportService.shareFile(file);
        
        // Small delay between exports to avoid overwhelming the share dialog
        if (i < _selectedNotes.length - 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully exported ${_selectedNotes.length} notes!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() => _selectedIds.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
