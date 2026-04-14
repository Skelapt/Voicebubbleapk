import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_state_provider.dart';
import '../../models/project.dart';
import '../../models/recording_item.dart';
import '../../services/analytics_service.dart';
import '../../services/project_service.dart';
import '../../services/continue_service.dart';
import '../../widgets/outcome_chip.dart';
import '../../widgets/multi_option_fab.dart';
import '../../constants/background_assets.dart';
import 'recording_screen.dart';
import 'recording_detail_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final _projectService = ProjectService();
  final _continueService = ContinueService();
  Project? _project;
  List<RecordingItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AnalyticsService().logScreenView(screenName: 'ProjectDetail');
    _loadProject();
  }

  Future<void> _loadProject() async {
    setState(() {
      _isLoading = true;
    });

    final projects = await _projectService.getAllProjects();
    final project = projects.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => projects.first,
    );

    final items = await _projectService.getProjectItems(widget.projectId);

    setState(() {
      _project = project;
      _items = items;
      _isLoading = false;
    });

    // Track project opened
    AnalyticsService().logProjectOpened(itemCount: items.length);
  }


  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final secondaryTextColor = const Color(0xFF94A3B8);
    final primaryColor = const Color(0xFF7C6AE8);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    if (_project == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Text(
            'Project not found',
            style: TextStyle(color: secondaryTextColor),
          ),
        ),
      );
    }

    final gradientColors = _getGradientColors(_project!.colorIndex ?? 0);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                      const Spacer(),
                      IconButton(
                        onPressed: () => _showProjectMenu(context),
                        icon: Icon(Icons.more_vert, color: textColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.folder,
                          color: textColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _project!.name,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            Text(
                              '${_project!.itemCount} items • ${_project!.formattedDate}',
                              style: TextStyle(
                                fontSize: 14,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_project!.description != null && _project!.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _project!.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryTextColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),


            // Continue Project Button
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GestureDetector(
                  onTap: _continueProject,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic, color: textColor, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'Continue Project',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Items Timeline
            _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 64,
                            color: secondaryTextColor.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No items in this project yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        return _buildItemCard(
                          _items[index],
                          surfaceColor,
                          textColor,
                          secondaryTextColor,
                          gradientColors,
                        );
                      },
                    ),
                  ),
          ],
        ),
        ),
      ),
      floatingActionButton: MultiOptionFab(
        onVoicePressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const RecordingScreen(),
            ),
          );
        },
        onTextPressed: () async {
          // Create empty text document within project
          final appState = Provider.of<AppStateProvider>(context, listen: false);
          final itemId = const Uuid().v4();
          final newItem = RecordingItem(
            id: itemId,
            rawTranscript: '',
            finalText: '',
            presetUsed: 'Text Document',
            outcomes: [],
            projectId: widget.projectId,
            createdAt: DateTime.now(),
            editHistory: [],
            presetId: 'text_document',
            tags: [],
            contentType: 'text',
          );
          await appState.saveRecording(newItem);
          await appState.addItemToProject(widget.projectId, itemId); // Add to project
          await _loadProject(); // Reload to show new item
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecordingDetailScreen(recordingId: newItem.id),
              ),
            );
          }
        },
        onNotePressed: () async {
          // Create empty quick note within project
          final appState = Provider.of<AppStateProvider>(context, listen: false);
          final itemId = const Uuid().v4();
          final newItem = RecordingItem(
            id: itemId,
            rawTranscript: '',
            finalText: '',
            presetUsed: 'Quick Note',
            outcomes: [],
            projectId: widget.projectId,
            createdAt: DateTime.now(),
            editHistory: [],
            presetId: 'quick_note',
            tags: [],
            contentType: 'text',
          );
          await appState.saveRecording(newItem);
          await appState.addItemToProject(widget.projectId, itemId); // Add to project
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecordingDetailScreen(recordingId: newItem.id),
              ),
            );
          }
        },
        onTodoPressed: () async {
          // Create empty todo within project
          final appState = Provider.of<AppStateProvider>(context, listen: false);
          final itemId = const Uuid().v4();
          final newItem = RecordingItem(
            id: itemId,
            rawTranscript: '',
            finalText: '',
            presetUsed: 'Todo List',
            outcomes: [],
            projectId: widget.projectId,
            createdAt: DateTime.now(),
            editHistory: [],
            presetId: 'todo_list',
            tags: [],
            contentType: 'todo',
          );
          await appState.saveRecording(newItem);
          await appState.addItemToProject(widget.projectId, itemId); // Add to project
          await _loadProject(); // Reload to show new item
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecordingDetailScreen(recordingId: newItem.id),
              ),
            );
          }
        },
        onImagePressed: () async {
          // Create empty image document within project
          final appState = Provider.of<AppStateProvider>(context, listen: false);
          final itemId = const Uuid().v4();
          final newItem = RecordingItem(
            id: itemId,
            rawTranscript: '', // Will store image path
            finalText: '',
            presetUsed: 'Image',
            outcomes: [],
            projectId: widget.projectId,
            createdAt: DateTime.now(),
            editHistory: [],
            presetId: 'image',
            tags: [],
            contentType: 'image',
          );
          await appState.saveRecording(newItem);
          await appState.addItemToProject(widget.projectId, itemId); // Add to project
          await _loadProject(); // Reload to show new item
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecordingDetailScreen(recordingId: newItem.id),
              ),
            );
          }
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildItemCard(
    RecordingItem item,
    Color surfaceColor,
    Color textColor,
    Color secondaryTextColor,
    List<Color> gradientColors,
  ) {
    final contentTypeColor = _getContentTypeColor(item.contentType);
    final contentTypeIcon = _getContentTypeIcon(item.contentType);
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RecordingDetailScreen(recordingId: item.id)),
        );
      },
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
              // Show background image if selected
              image: item.background != null && !_isBackgroundPaper(item.background!)
                  ? DecorationImage(
                      image: AssetImage(_getBackgroundAssetPath(item.background!)),
                      fit: BoxFit.cover,
                      opacity: 0.3,
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with content type indicator and date
                Row(
                  children: [
                    // Content type indicator
                    Container(
                      margin: const EdgeInsets.only(left: 4), // Push slightly right from edge
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: contentTypeColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            contentTypeIcon,
                            size: 12,
                            color: contentTypeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.contentType.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: contentTypeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Date/time
                    Text(
                      item.formattedDate,
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Title
                Text(
                  item.customTitle?.isNotEmpty == true 
                      ? item.customTitle! 
                      : item.finalText.split('\n').first,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                
                // Preview text (show content, but skip first line if we used it as title and no custom title)
                Text(
                  item.customTitle?.isNotEmpty == true 
                      ? item.finalText
                      : _getPreviewText(item.finalText),
                  style: TextStyle(
                    fontSize: 14,
                    color: secondaryTextColor,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _getGradientColors(int colorIndex) {
    final gradients = [
      [const Color(0xFF3B82F6), const Color(0xFF2563EB)],
      [const Color(0xFF9333EA), const Color(0xFFEC4899)],
      [const Color(0xFF10B981), const Color(0xFF14B8A6)],
      [const Color(0xFFF59E0B), const Color(0xFFF97316)],
      [const Color(0xFFEF4444), const Color(0xFFDC2626)],
      [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)],
    ];
    return gradients[colorIndex % gradients.length];
  }

  Future<void> _continueProject() async {
    try {
      AnalyticsService().logContinueFromProject();
      final context = await _continueService.buildContextFromProject(widget.projectId);
      if (mounted) {
        final appState = Provider.of<AppStateProvider>(this.context, listen: false);
        appState.setContinueContext(context);

        // Navigate to recording screen
        Navigator.push(
          this.context,
          MaterialPageRoute(
            builder: (context) => const RecordingScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _removeItemFromProject(String itemId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Remove from project?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This item will not be deleted, just removed from this project.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _projectService.removeItemFromProject(widget.projectId, itemId);
      await _loadProject();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from project'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    }
  }

  void _showProjectMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: Color(0xFFEF4444)),
                title: const Text('Delete Project', style: TextStyle(color: Color(0xFFEF4444))),
                onTap: () {
                  Navigator.pop(context);
                  _deleteProject();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteProject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete project?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'The items will not be deleted, only the project.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      await appState.deleteProject(widget.projectId);
      if (mounted) {
        Navigator.pop(context); // Go back to library
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project deleted'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    }
  }

  IconData _getContentTypeIcon(String contentType) {
    switch (contentType) {
      case 'text':
        return Icons.text_fields;
      case 'image':
        return Icons.image;
      case 'voice':
      default:
        return Icons.mic;
    }
  }

  Color _getContentTypeColor(String contentType) {
    switch (contentType) {
      case 'text':
        return const Color(0xFFF59E0B);
      case 'todo':
        return const Color(0xFF8B5CF6);
      case 'image':
        return const Color(0xFF10B981);
      case 'voice':
      default:
        return const Color(0xFFEF4444);
    }
  }

  bool _isBackgroundPaper(String backgroundId) {
    // Paper backgrounds start with 'paper_'
    return backgroundId.startsWith('paper_');
  }

  String _getBackgroundAssetPath(String backgroundId) {
    // Use BackgroundAssets registry to get correct path
    final background = BackgroundAssets.findById(backgroundId);
    return background?.assetPath ?? 'assets/backgrounds/abstract_waves.jpg';
  }

  String _getPreviewText(String text) {
    // Skip the first line (used as title) and return the rest
    final lines = text.split('\n');
    if (lines.length <= 1) return '';
    return lines.skip(1).join('\n').trim();
  }
}
