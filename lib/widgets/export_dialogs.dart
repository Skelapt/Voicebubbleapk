import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/recording_item.dart';
import '../services/export_service.dart';
import '../services/analytics_service.dart';

class ExportDialog extends StatelessWidget {
  final RecordingItem note;

  const ExportDialog({
    super.key,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xFF0D0D1A);
    final surfaceColor = const Color(0xFF1A1A2E);
    final textColor = Colors.white;
    final primaryColor = const Color(0xFF7C6AE8);

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'Export Note',
              style: TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'Choose format to export',
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Export options - MATCHING BATCH STYLE
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444)),
              title: const Text('PDF', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Professional document', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              onTap: () => _exportAs(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Color(0xFF3B82F6)),
              title: const Text('Markdown', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Plain text with formatting', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              onTap: () => _exportAs(context, 'markdown'),
            ),
            ListTile(
              leading: const Icon(Icons.language, color: Color(0xFFF97316)),
              title: const Text('HTML', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Web page format', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              onTap: () => _exportAs(context, 'html'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields, color: Color(0xFF10B981)),
              title: const Text('Plain Text', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Simple .txt file', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              onTap: () => _exportAs(context, 'text'),
            ),
            
            const SizedBox(height: 24),
            
            // Cancel button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: textColor.withOpacity(0.7),
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAs(BuildContext context, String format) async {
    Navigator.pop(context); // Close dialog

    AnalyticsService().logCustomEvent(
      eventName: 'document_exported',
      parameters: {
        'format': format,
        'source': 'export_dialog',
        'content_type': note.contentType,
      },
    );

    final exportService = ExportService();

    try {
      // Get content - prefer finalText, fallback to extracting from formattedContent
      String contentToExport = note.finalText;

      if (contentToExport.isEmpty && note.formattedContent != null && note.formattedContent!.isNotEmpty) {
        // Try to extract plain text from Quill delta JSON
        try {
          final deltaJson = jsonDecode(note.formattedContent!);
          if (deltaJson is List) {
            final buffer = StringBuffer();
            for (final op in deltaJson) {
              if (op is Map && op.containsKey('insert')) {
                buffer.write(op['insert']);
              }
            }
            contentToExport = buffer.toString();
          }
        } catch (e) {
          debugPrint('❌ Error parsing formattedContent: $e');
        }
      }

      debugPrint('📝 Exporting content: ${contentToExport.length} chars');

      if (contentToExport.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nothing to export - document is empty'),
              backgroundColor: Color(0xFFF59E0B),
            ),
          );
        }
        return;
      }

      // Create a note copy with the extracted content
      final noteToExport = RecordingItem(
        id: note.id,
        rawTranscript: note.rawTranscript,
        finalText: contentToExport,
        presetUsed: note.presetUsed,
        outcomes: note.outcomes,
        projectId: note.projectId,
        createdAt: note.createdAt,
        editHistory: note.editHistory,
        presetId: note.presetId,
        customTitle: note.customTitle,
        tags: note.tags,
        formattedContent: note.formattedContent,
        contentType: note.contentType,
      );

      // Show loading
      if (context.mounted) {
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
                Text('Exporting as ${format.toUpperCase()}...'),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF3B82F6),
          ),
        );
      }

      // Export based on format
      late final file;
      switch (format) {
        case 'pdf':
          file = await exportService.exportAsPdf(noteToExport);
          break;
        case 'markdown':
          file = await exportService.exportAsMarkdown(noteToExport);
          break;
        case 'html':
          file = await exportService.exportAsHtml(noteToExport);
          break;
        case 'text':
          file = await exportService.exportAsText(noteToExport);
          break;
      }

      // Share the file
      await exportService.shareFile(file);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export complete!'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Export error: $e');
      if (context.mounted) {
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

