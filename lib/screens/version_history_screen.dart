import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recording_item.dart';
import '../models/version_snapshot.dart';
import '../services/version_history_service.dart';
import '../providers/app_state_provider.dart';

class VersionHistoryScreen extends StatefulWidget {
  final RecordingItem note;

  const VersionHistoryScreen({
    super.key,
    required this.note,
  });

  @override
  State<VersionHistoryScreen> createState() => _VersionHistoryScreenState();
}

class _VersionHistoryScreenState extends State<VersionHistoryScreen> {
  final _versionService = VersionHistoryService();
  List<VersionSnapshot> _versions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    setState(() => _isLoading = true);
    
    final versions = await _versionService.getVersions(widget.note.id);
    
    setState(() {
      _versions = versions;
      _isLoading = false;
    });
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Version History',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            )
          : _versions.isEmpty
              ? _buildEmptyState(textColor, secondaryTextColor)
              : _buildVersionsList(
                  surfaceColor,
                  textColor,
                  secondaryTextColor,
                  primaryColor,
                ),
    );
  }

  Widget _buildEmptyState(Color textColor, Color secondaryTextColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: secondaryTextColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No version history yet',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Versions are saved automatically as you edit',
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionsList(
    Color surfaceColor,
    Color textColor,
    Color secondaryTextColor,
    Color primaryColor,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _versions.length,
      itemBuilder: (context, index) {
        final version = _versions[index];
        final isLatest = index == 0;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: isLatest
                  ? Border.all(color: primaryColor, width: 2)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isLatest) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: primaryColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Current',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  version.label,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              version.formattedDate,
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      if (!isLatest)
                        TextButton(
                          onPressed: () => _showRestoreDialog(version),
                          style: TextButton.styleFrom(
                            foregroundColor: primaryColor,
                          ),
                          child: const Text('Restore'),
                        ),
                    ],
                  ),
                ),
                
                // Content preview
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        version.contentPreview,
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Text(
                        '${version.content.split(RegExp(r'\s+')).length} words',
                        style: TextStyle(
                          color: secondaryTextColor.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRestoreDialog(VersionSnapshot version) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Restore Version?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will replace the current content with this version from ${version.formattedDate}.\n\nThe current version will be saved in history.',
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
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _restoreVersion(version);
            },
            child: const Text(
              'Restore',
              style: TextStyle(color: Color(0xFF3B82F6)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreVersion(VersionSnapshot version) async {
    try {
      final appState = context.read<AppStateProvider>();

      // Get FRESH note from appState, not widget.note which may be stale
      final freshNote = appState.allRecordingItems.firstWhere(
        (item) => item.id == widget.note.id,
        orElse: () => widget.note,
      );

      // Save current version before restoring
      await _versionService.saveVersion(freshNote, 'Before restore');

      // Update note with restored content
      final updatedNote = freshNote.copyWith(
        finalText: version.content,
        formattedContent: version.formattedContent,
      );

      await appState.updateRecording(updatedNote);

      if (mounted) {
        // Pop with result to tell detail screen to rebuild
        Navigator.pop(context, true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Version restored successfully'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore version: $e'),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
