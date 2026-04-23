import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/app_state_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/refinement_service.dart';
import '../services/ai_service.dart';
import '../services/feature_gate.dart';
import '../services/preset_favorites_service.dart';
import '../models/outcome_type.dart';
import '../models/preset.dart';
import '../constants/background_assets.dart';
import '../constants/presets.dart';
import './outcome_chip.dart';
import './background_picker.dart';

// ============================================================
//        LINED PAPER PAINTER (for coded lined paper)
// ============================================================

class LinedPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9E9E9E) // DARKER grey lines (more visible)
      ..strokeWidth = 1.5; // Slightly thicker

    const lineSpacing = 32.0; // Space between lines
    for (double y = lineSpacing; y < size.height; y += lineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================
//        CUSTOM EMBED BUILDERS FOR IMAGES AND AUDIO
// ============================================================

/// Custom embed builder for displaying images in the Quill editor
class CustomImageEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'image';

  @override
  Widget build(
    BuildContext context,
    quill.QuillController controller,
    quill.Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final imageUrl = node.value.data as String;
    return _ResizableImage(imageUrl: imageUrl);
  }
}

/// Resizable image widget
class _ResizableImage extends StatefulWidget {
  final String imageUrl;

  const _ResizableImage({required this.imageUrl});

  @override
  State<_ResizableImage> createState() => _ResizableImageState();
}

class _ResizableImageState extends State<_ResizableImage> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _isExpanded
                  // EXPANDED: Full image, natural aspect ratio, no cropping
                  ? Image.file(
                      File(widget.imageUrl),
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildErrorWidget();
                      },
                    )
                  // COLLAPSED: Fixed height preview with cover crop
                  : Image.file(
                      File(widget.imageUrl),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildErrorWidget();
                      },
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                _isExpanded ? Icons.unfold_less : Icons.unfold_more,
                color: Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                _isExpanded ? 'Tap to minimize' : 'Tap to expand',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.broken_image, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Image not found: ${widget.imageUrl.split('/').last}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom embed builder for displaying audio/voice notes in the Quill editor
class CustomAudioEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'audio';

  @override
  Widget build(
    BuildContext context,
    quill.QuillController controller,
    quill.Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final audioPath = node.value.data as String;
    return _PlayableAudioWidget(audioPath: audioPath);
  }
}

/// Playable audio widget with play/pause functionality
class _PlayableAudioWidget extends StatefulWidget {
  final String audioPath;

  const _PlayableAudioWidget({required this.audioPath});

  @override
  State<_PlayableAudioWidget> createState() => _PlayableAudioWidgetState();
}

class _PlayableAudioWidgetState extends State<_PlayableAudioWidget> {
  bool _isPlaying = false;
  late final AudioPlayer _audioPlayer;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setFilePath(widget.audioPath);
      _audioPlayer.durationStream.listen((duration) {
        if (mounted && duration != null) {
          setState(() {
            _duration = duration;
          });
        }
      });
      _audioPlayer.positionStream.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });
      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
          });
          // Auto-reset when finished
          if (state.processingState == ProcessingState.completed) {
            _audioPlayer.seek(Duration.zero);
            _audioPlayer.pause();
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Error loading audio: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _togglePlayback() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } catch (e) {
      debugPrint('❌ Error toggling playback: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isPlaying 
                ? const Color(0xFFF59E0B) 
                : Colors.white.withOpacity(0.1),
            width: _isPlaying ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _togglePlayback,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: const Color(0xFFF59E0B),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isPlaying ? 'Playing...' : 'Voice Note',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.mic,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (_duration.inSeconds > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _duration.inSeconds > 0 ? _position.inSeconds / _duration.inSeconds : 0,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                  minHeight: 4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
//        RICH TEXT EDITOR WIDGET — WITH AI SELECTION MENU
// ============================================================

class SaveIntent extends Intent {}
class BoldIntent extends Intent {}
class ItalicIntent extends Intent {}
class UnderlineIntent extends Intent {}
class UndoIntent extends Intent {}
class RedoIntent extends Intent {}

class RichTextEditor extends StatefulWidget {
  final String? initialFormattedContent;
  final String? initialPlainText;
  final Function(String plainText, String deltaJson) onSave;
  final bool readOnly;
  
  // Context-aware features
  final bool showOutcomeChips;
  final OutcomeType? initialOutcomeType;
  final Function(OutcomeType)? onOutcomeChanged;
  
  final bool showReminderButton;
  final DateTime? initialReminder;
  final Function(DateTime?)? onReminderChanged;
  
  final bool showCompletionCheckbox;
  final bool initialCompletion;
  final Function(bool)? onCompletionChanged;
  
  final bool showImageSection;
  final String? initialImagePath;
  final Function(String?)? onImageChanged;
  
  // Top toolbar actions (Google Keep style)
  final bool showTopToolbar;
  final bool isPinned;
  final Function(bool)? onPinChanged;
  final Function(String)? onVoiceNoteAdded;
  
  // Background support
  final String? backgroundId;
  final Function(String?)? onBackgroundChanged;

  // Continue recording callback
  final VoidCallback? onContinuePressed;

  // Content type for auto-initialization (e.g., 'todo' to auto-add checkboxes)
  final String? contentType;

  const RichTextEditor({
    super.key,
    this.initialFormattedContent,
    this.initialPlainText,
    required this.onSave,
    this.readOnly = false,
    this.showOutcomeChips = false,
    this.initialOutcomeType,
    this.onOutcomeChanged,
    this.showReminderButton = false,
    this.initialReminder,
    this.onReminderChanged,
    this.showCompletionCheckbox = false,
    this.initialCompletion = false,
    this.onCompletionChanged,
    this.showImageSection = false,
    this.initialImagePath,
    this.onImageChanged,
    this.backgroundId,
    this.onBackgroundChanged,
    this.onContinuePressed,
    this.showTopToolbar = true,
    this.isPinned = false,
    this.onPinChanged,
    this.onVoiceNoteAdded,
    this.contentType,
  });

  @override
  State<RichTextEditor> createState() => RichTextEditorState();
}

class RichTextEditorState extends State<RichTextEditor> with TickerProviderStateMixin {
  late quill.QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  Timer? _saveTimer;
  Timer? _selectionTimer;
  late AnimationController _saveIndicatorController;
  late Animation<double> _saveIndicatorAnimation;
  int _wordCount = 0;
  int _characterCount = 0;

  // First-open bubble — shows once, hints that Rewrite = magic
  static const String _firstOpenBubbleKey = 'editor_first_open_bubble_dismissed';
  bool _showFirstOpenBubble = false;
  bool _hasUnsavedChanges = false;
  bool _showSaved = false;
  
  // Selection tracking
  bool _hasSelection = false;
  String _selectedText = '';
  int _selectionStart = 0;
  int _selectionEnd = 0;
  
  // Context-aware state
  OutcomeType? _selectedOutcomeType;
  DateTime? _reminderDateTime;
  bool _isCompleted = false;
  File? _selectedImage;
  String? _imagePath;
  final ImagePicker _picker = ImagePicker();

  // Top toolbar state (Google Keep style)
  bool _isPinned = false;
  bool _isRecordingVoiceNote = false;
  String? _currentRecordingPath;
  bool _isImageExpanded = false;
  final AudioRecorder _audioRecorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    _initializeController();
    _controller.addListener(_onControllerChanged);
    
    // Initialize context-aware state
    _selectedOutcomeType = widget.initialOutcomeType;
    _reminderDateTime = widget.initialReminder;
    _isCompleted = widget.initialCompletion;
    _imagePath = widget.initialImagePath;
    _isPinned = widget.isPinned;
    
    _saveIndicatorController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _saveIndicatorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _saveIndicatorController, curve: Curves.easeInOut),
    );

    // Immediate save for new items that have plain text but no formatted content
    // This ensures the delta JSON is persisted right away
    if (widget.initialFormattedContent == null || widget.initialFormattedContent!.isEmpty) {
      if (widget.initialPlainText != null && widget.initialPlainText!.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _saveContent();
        });
      }
    }

    _maybeShowFirstOpenBubble();
  }

  Future<void> _maybeShowFirstOpenBubble() async {
    if (widget.readOnly) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool(_firstOpenBubbleKey) ?? false;
      if (!dismissed && mounted) {
        // Small delay so it appears after the editor settles in
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) setState(() => _showFirstOpenBubble = true);
      }
    } catch (_) {}
  }

  Future<void> _dismissFirstOpenBubble() async {
    if (!_showFirstOpenBubble) return;
    setState(() => _showFirstOpenBubble = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_firstOpenBubbleKey, true);
    } catch (_) {}
  }

  void _initializeController() {
    quill.Document doc;
    
    if (widget.initialFormattedContent != null && widget.initialFormattedContent!.isNotEmpty) {
      try {
        final deltaJson = jsonDecode(widget.initialFormattedContent!);
        doc = quill.Document.fromJson(deltaJson);
      } catch (e) {
        doc = quill.Document()..insert(0, widget.initialPlainText ?? '');
      }
    } else if (widget.initialPlainText != null && widget.initialPlainText!.isNotEmpty) {
      doc = quill.Document()..insert(0, widget.initialPlainText!);
    } else {
      // Empty document - check if we need to auto-populate
      doc = quill.Document();
      
      // Auto-add 3 checkboxes for TODO content type
      if (widget.contentType == 'todo') {
        // Insert text first, then format as checkboxes
        doc.insert(0, '\n\n\n');
        // Format each line as unchecked
        doc.format(0, 1, quill.Attribute.unchecked);
        doc.format(1, 1, quill.Attribute.unchecked);
        doc.format(2, 1, quill.Attribute.unchecked);
      }
    }

    _controller = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  @override
  void dispose() {
    // Save before disposing if there are unsaved changes
    if (_hasUnsavedChanges) {
      _saveContent();
    }
    
    _saveTimer?.cancel();
    _selectionTimer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    _saveIndicatorController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.readOnly) return;
    
    // Update word/character count
    final plainText = _controller.document.toPlainText();
    final words = plainText.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    
    setState(() {
      _hasUnsavedChanges = true;
      _showSaved = false;
      _wordCount = words;
      _characterCount = plainText.length;
    });

    // Check selection with debounce
    _selectionTimer?.cancel();
    _selectionTimer = Timer(const Duration(milliseconds: 200), _checkSelection);

    // Debounced auto-save - saves 1.5 seconds after user stops typing
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _hasUnsavedChanges) {
        _saveContent();
      }
    });
  }

  void _checkSelection() {
    if (!mounted) return;
    
    final selection = _controller.selection;
    final plainText = _controller.document.toPlainText();
    
    if (selection.baseOffset != selection.extentOffset) {
      final start = selection.start;
      final end = selection.end;
      
      if (end <= plainText.length) {
        final text = plainText.substring(start, end);
        if (text.trim().length > 1) {
          setState(() {
            _hasSelection = true;
            _selectedText = text;
            _selectionStart = start;
            _selectionEnd = end;
          });
          return;
        }
      }
    }
    
    if (_hasSelection) {
      setState(() {
        _hasSelection = false;
        _selectedText = '';
      });
    }
  }

  Future<void> _saveContent() async {
    if (!mounted) return;

    try {
      final deltaJson = jsonEncode(_controller.document.toDelta().toJson());
      final plainText = _controller.document.toPlainText().trim();

      await widget.onSave(plainText, deltaJson);

      if (mounted) {
        // Just save, no indicators
        _saveIndicatorController.forward().then((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _saveIndicatorController.reverse();
            }
          });
        });
      }
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  /// Public method to force save - called before continue flow
  Future<void> forceSave() async {
    await _saveContent();
  }

  Future<void> _showAIMenu() async {
    // Use selected text if available, otherwise use full document
    final textToRewrite = _hasSelection
        ? _selectedText
        : _controller.document.toPlainText().trim();

    if (textToRewrite.isEmpty) return;

    // Dismiss the first-open hint when user actually engages with Rewrite
    _dismissFirstOpenBubble();

    HapticFeedback.mediumImpact();

    if (!mounted) return;

    // Capture the provider here so the sheet can always read the latest
    // language at the moment the user taps a preset — EXACTLY like the old
    // ResultScreen._generateRewrite() did: appState.selectedLanguage.code
    // read fresh at AI-call time (not at sheet-open time).
    final appStateProvider = Provider.of<AppStateProvider>(context, listen: false);

    // Show full AI presets bottom sheet (Letterly-style Rewrite)
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RewritePresetSheet(
        textToRewrite: textToRewrite,
        appState: appStateProvider,
        onResult: (newText) {
          Navigator.pop(ctx);
          if (_hasSelection) {
            _replaceSelection(newText);
          } else {
            // Replace full document
            final length = _controller.document.length;
            _controller.replaceText(0, length - 1, newText, null);
            setState(() {
              _hasSelection = false;
              _selectedText = '';
            });
          }
        },
      ),
    );
  }

  void _replaceSelection(String newText) {
    _controller.replaceText(
      _selectionStart,
      _selectionEnd - _selectionStart,
      newText,
      null,
    );
    
    setState(() {
      _hasSelection = false;
      _selectedText = '';
    });
    
    HapticFeedback.mediumImpact();
  }

  // Context-aware helper methods
  
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(path.join(appDir.path, 'images'));
        
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        
        final fileName = '${const Uuid().v4()}.jpg';
        final savedImage = File(path.join(imagesDir.path, fileName));
        await File(image.path).copy(savedImage.path);
        
        setState(() {
          _selectedImage = savedImage;
          _imagePath = savedImage.path;
        });
        
        widget.onImageChanged?.call(savedImage.path);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }
  
  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(path.join(appDir.path, 'images'));
        
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        
        final fileName = '${const Uuid().v4()}.jpg';
        final savedImage = File(path.join(imagesDir.path, fileName));
        await File(image.path).copy(savedImage.path);
        
        setState(() {
          _selectedImage = savedImage;
          _imagePath = savedImage.path;
        });
        
        widget.onImageChanged?.call(savedImage.path);
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
    }
  }
  
  void _showImageSourceDialog() {
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
                leading: const Icon(Icons.photo_library, color: Color(0xFF10B981)),
                title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF3B82F6)),
                title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
              if (_imagePath != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Color(0xFFEF4444)),
                  title: const Text('Remove Image', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedImage = null;
                      _imagePath = null;
                    });
                    widget.onImageChanged?.call(null);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
  
  Future<void> _showReminderPicker() async {
    final selectedDateTime = await showDatePicker(
      context: context,
      initialDate: _reminderDateTime ?? DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF3B82F6),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDateTime != null && mounted) {
      final selectedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          _reminderDateTime ?? DateTime.now().add(const Duration(hours: 1)),
        ),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF3B82F6),
                onPrimary: Colors.white,
                surface: Color(0xFF1A1A1A),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );

      if (selectedTime != null && mounted) {
        final newReminder = DateTime(
          selectedDateTime.year,
          selectedDateTime.month,
          selectedDateTime.day,
          selectedTime.hour,
          selectedTime.minute,
        );
        setState(() {
          _reminderDateTime = newReminder;
        });
        widget.onReminderChanged?.call(newReminder);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOP TOOLBAR HELPER METHODS (Google Keep style)
  // ═══════════════════════════════════════════════════════════════════════════

  void _togglePin() {
    setState(() {
      _isPinned = !_isPinned;
    });
    widget.onPinChanged?.call(_isPinned);
  }

  Future<void> _insertImageAtCursor() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        // Save image permanently
        final appDir = await getApplicationDocumentsDirectory();
        final String fileName = '${const Uuid().v4()}.jpg';
        final String permanentPath = '${appDir.path}/images/$fileName';

        await Directory('${appDir.path}/images').create(recursive: true);
        await File(image.path).copy(permanentPath);

        // Insert ACTUAL image embed into Quill document (not text!)
        final index = _controller.selection.baseOffset;
        _controller.document.insert(index, quill.BlockEmbed.image(permanentPath));
        _controller.updateSelection(
          TextSelection.collapsed(offset: index + 1),
          quill.ChangeSource.local,
        );
        
        // Add newline after image for spacing
        _controller.document.insert(index + 1, '\n');
      }
    } catch (e) {
      debugPrint('❌ Error inserting image: $e');
    }
  }

  Future<void> _takePhotoAtCursor() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        // Save image permanently
        final appDir = await getApplicationDocumentsDirectory();
        final String fileName = '${const Uuid().v4()}.jpg';
        final String permanentPath = '${appDir.path}/images/$fileName';

        await Directory('${appDir.path}/images').create(recursive: true);
        await File(image.path).copy(permanentPath);

        // Insert ACTUAL image embed into Quill document (not text!)
        final index = _controller.selection.baseOffset;
        _controller.document.insert(index, quill.BlockEmbed.image(permanentPath));
        _controller.updateSelection(
          TextSelection.collapsed(offset: index + 1),
          quill.ChangeSource.local,
        );
        
        // Add newline after image for spacing
        _controller.document.insert(index + 1, '\n');
      }
    } catch (e) {
      debugPrint('❌ Error taking photo: $e');
    }
  }

  Future<void> _toggleVoiceNoteRecording() async {
    if (_isRecordingVoiceNote) {
      // Stop recording
      final recordingPath = await _audioRecorder.stop();
      if (recordingPath != null && mounted) {
        // Insert audio player embed at cursor (using custom audio embed)
        final index = _controller.selection.baseOffset;
        
        // For now, insert as a custom block with audio icon + path
        // This will display as a clickable audio player
        _controller.document.insert(index, '\n🎤 ');
        _controller.document.insert(index + 3, quill.BlockEmbed.custom(
          quill.CustomBlockEmbed('audio', recordingPath),
        ));
        _controller.document.insert(index + 4, '\n');
        _controller.updateSelection(
          TextSelection.collapsed(offset: index + 5),
          quill.ChangeSource.local,
        );
        
        widget.onVoiceNoteAdded?.call(recordingPath);
      }
      setState(() {
        _isRecordingVoiceNote = false;
        _currentRecordingPath = null;
      });
    } else {
      // Start recording
      if (await _audioRecorder.hasPermission()) {
        final appDir = await getApplicationDocumentsDirectory();
        final String fileName = '${const Uuid().v4()}.m4a';
        final String recordPath = '${appDir.path}/voice_notes/$fileName';

        await Directory('${appDir.path}/voice_notes').create(recursive: true);

        await _audioRecorder.start(RecordConfig(), path: recordPath);
        setState(() {
          _isRecordingVoiceNote = true;
          _currentRecordingPath = recordPath;
        });
      }
    }
  }

  void _showVoiceRecordingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing mic icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic,
                color: Color(0xFFEF4444),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Recording Voice Note...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap Stop when finished',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // Close overlay
                _toggleVoiceNoteRecording(); // Stop recording
              },
              icon: const Icon(Icons.stop, color: Colors.white),
              label: const Text('Stop Recording', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _insertCheckboxAtCursor() {
    final index = _controller.selection.baseOffset;
    // Use Quill's built-in checkbox attribute
    _controller.document.insert(index, '\n');
    _controller.formatText(index, 1, quill.Attribute.unchecked);
    _controller.updateSelection(
      TextSelection.collapsed(offset: index + 1),
      quill.ChangeSource.local,
    );
  }

  void _showAddContentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.image_outlined, color: Color(0xFF10B981)),
                  title: const Text('Add Image from Gallery', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _insertImageAtCursor();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF3B82F6)),
                  title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _takePhotoAtCursor();
                  },
                ),
                ListTile(
                  leading: Icon(
                    _isRecordingVoiceNote ? Icons.stop_circle : Icons.mic_outlined,
                    color: _isRecordingVoiceNote ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                  ),
                  title: Text(
                    _isRecordingVoiceNote ? 'Stop Voice Recording' : 'Record Voice Note',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    // DON'T close menu - keep it open during recording
                    await _toggleVoiceNoteRecording();
                    // Update the modal state to reflect recording changes
                    setModalState(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.check_box_outlined, color: Color(0xFF8B5CF6)),
                  title: const Text('Add Checkbox', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _insertCheckboxAtCursor();
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditorOptionsMenu() {
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
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Color(0xFF3B82F6)),
                title: const Text('Add Content', style: TextStyle(color: Colors.white)),
                subtitle: Text('Image, voice note, checkbox', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showAddContentMenu();
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined, color: Color(0xFF8B5CF6)),
                title: const Text('Change Background', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showBackgroundPicker();
                },
              ),
              ListTile(
                leading: Icon(
                  _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _isPinned ? const Color(0xFFF59E0B) : Colors.white70,
                ),
                title: Text(
                  _isPinned ? 'Unpin Note' : 'Pin Note',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _togglePin();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showBackgroundPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackgroundPicker(
          currentBackgroundId: widget.backgroundId,
          onBackgroundSelected: (id) {
            widget.onBackgroundChanged?.call(id);
          },
        );
      },
    );
  }

  Widget _buildBackgroundWidget() {
    if (widget.backgroundId == null) {
      return const SizedBox.shrink();
    }

    final background = BackgroundAssets.findById(widget.backgroundId!);
    if (background == null) {
      return Container(color: const Color(0xFF1E1E1E));
    }

    // PAPER TYPES
    if (background.isPaper) {
      if (background.id == 'paper_plain') {
        // CODED: Plain white paper
        return Container(color: const Color(0xFFFFFFFF));
      } else if (background.id == 'paper_lined') {
        // IMAGE: Lined paper (user adds)
        if (background.assetPath != null) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                background.assetPath!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback if image missing
                  return CustomPaint(
                    painter: LinedPaperPainter(),
                    child: Container(color: const Color(0xFFFAFAFA)),
                  );
                },
              ),
            ],
          );
        } else {
          return CustomPaint(
            painter: LinedPaperPainter(),
            child: Container(color: const Color(0xFFFAFAFA)),
          );
        }
      } else if (background.assetPath != null) {
        // IMAGE: Vintage or other papers
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              background.assetPath!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: background.fallbackColor);
              },
            ),
            Container(color: Colors.black.withOpacity(0.05)),
          ],
        );
      } else {
        return Container(color: background.fallbackColor);
      }
    }

    // IMAGE BACKGROUNDS (nature, space, etc.)
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          background.assetPath!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(color: background.fallbackColor);
          },
        ),
        Container(color: Colors.black.withOpacity(0.40)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const surfaceColor = Color(0xFF1A1A1A);

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): SaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyB): BoldIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyI): ItalicIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyU): UnderlineIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ): UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyY): RedoIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SaveIntent: CallbackAction<SaveIntent>(onInvoke: (_) => _saveContent()),
          BoldIntent: CallbackAction<BoldIntent>(onInvoke: (_) => _controller.formatSelection(quill.Attribute.bold)),
          ItalicIntent: CallbackAction<ItalicIntent>(onInvoke: (_) => _controller.formatSelection(quill.Attribute.italic)),
          UnderlineIntent: CallbackAction<UnderlineIntent>(onInvoke: (_) => _controller.formatSelection(quill.Attribute.underline)),
          UndoIntent: CallbackAction<UndoIntent>(onInvoke: (_) => _controller.undo()),
          RedoIntent: CallbackAction<RedoIntent>(onInvoke: (_) => _controller.redo()),
        },
        child: Stack(
          children: [
            Column(
              children: [
                // Outcome chips section (for outcomes tab) - FIXED
                if (widget.showOutcomeChips)
                  Container(
                    color: surfaceColor,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Outcome Type',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: OutcomeType.values.map((outcomeType) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: OutcomeChip(
                                  outcomeType: outcomeType,
                                  isSelected: _selectedOutcomeType == outcomeType,
                                  onTap: () {
                                    setState(() {
                                      _selectedOutcomeType = outcomeType;
                                    });
                                    widget.onOutcomeChanged?.call(outcomeType);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // Reminder and completion controls (for outcomes/todos) - FIXED
                if (widget.showReminderButton || widget.showCompletionCheckbox)
                  Container(
                    color: surfaceColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        // Completion checkbox
                        if (widget.showCompletionCheckbox)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isCompleted = !_isCompleted;
                              });
                              widget.onCompletionChanged?.call(_isCompleted);
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isCompleted ? const Color(0xFF10B981) : Colors.transparent,
                                border: Border.all(
                                  color: const Color(0xFF10B981),
                                  width: 2,
                                ),
                              ),
                              child: _isCompleted
                                  ? const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        if (widget.showCompletionCheckbox)
                          const SizedBox(width: 8),
                        if (widget.showCompletionCheckbox)
                          const Text(
                            'Completed',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        
                        const Spacer(),
                        
                        // Reminder button
                        if (widget.showReminderButton)
                          GestureDetector(
                            onTap: _showReminderPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _reminderDateTime != null 
                                    ? const Color(0xFF3B82F6).withOpacity(0.2)
                                    : const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(8),
                                border: _reminderDateTime != null
                                    ? Border.all(color: const Color(0xFF3B82F6))
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _reminderDateTime != null ? Icons.alarm : Icons.alarm_add,
                                    size: 16,
                                    color: _reminderDateTime != null 
                                        ? const Color(0xFF3B82F6)
                                        : Colors.white.withOpacity(0.7),
                                  ),
                                  if (_reminderDateTime != null) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_reminderDateTime!.day}/${_reminderDateTime!.month} ${_reminderDateTime!.hour.toString().padLeft(2, '0')}:${_reminderDateTime!.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        color: Color(0xFF3B82F6),
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _reminderDateTime = null;
                                        });
                                        widget.onReminderChanged?.call(null);
                                      },
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Color(0xFF3B82F6),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                
                // Outcome chips section (for outcomes tab) - FIXED
                Expanded(
                  child: Stack(
                    children: [
                      // Background layer - FULL SCREEN below header/toolbar
                      if (widget.backgroundId != null)
                        Positioned.fill(
                          child: _buildBackgroundWidget(),
                        ),
                      
                      // Content layer (scrollable)
                      SingleChildScrollView(
                        child: Container(
                          // Clean navy background - matches app
                          color: widget.backgroundId == null ? const Color(0xFF0D0D1A) : Colors.transparent,
                          padding: const EdgeInsets.all(16),
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.of(context).size.height - 100,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Image section — INSIDE scroll area (image docs only)
                              if (widget.showImageSection) ...[
                                Container(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Image',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _showImageSourceDialog,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF3B82F6),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    _imagePath != null ? Icons.edit : Icons.add_photo_alternate,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _imagePath != null ? 'Change' : 'Add',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_imagePath != null && File(_imagePath!).existsSync()) ...[
                                        const SizedBox(height: 8),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _isImageExpanded = !_isImageExpanded;
                                            });
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: _isImageExpanded
                                                ? Image.file(
                                                    File(_imagePath!),
                                                    width: double.infinity,
                                                    fit: BoxFit.fitWidth,
                                                  )
                                                : Image.file(
                                                    File(_imagePath!),
                                                    width: double.infinity,
                                                    height: 200,
                                                    fit: BoxFit.cover,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              _isImageExpanded ? Icons.unfold_less : Icons.unfold_more,
                                              color: Colors.white54,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _isImageExpanded ? 'Tap to minimize' : 'Tap to expand',
                                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              // Let QuillEditor expand naturally - no fixed height SizedBox
                              Theme(
                                data: ThemeData.dark().copyWith(
                                  scaffoldBackgroundColor: Colors.transparent,
                                  canvasColor: Colors.transparent,
                                  cardColor: Colors.transparent,
                                ),
                                child: quill.QuillEditor.basic(
                                  focusNode: _focusNode,
                                  configurations: quill.QuillEditorConfigurations(
                                    controller: _controller,
                                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 400),
                                    autoFocus: !widget.readOnly,
                                    expands: false,
                                    placeholder: 'Start writing...',
                                    readOnly: widget.readOnly,
                                    scrollPhysics: const ClampingScrollPhysics(),
                                    embedBuilders: [
                                      CustomImageEmbedBuilder(),
                                      CustomAudioEmbedBuilder(),
                                    ],
                                    customStyles: quill.DefaultStyles(
                                      h1: quill.DefaultTextBlockStyle(
                                        TextStyle(
                                          color: widget.backgroundId != null && BackgroundAssets.findById(widget.backgroundId!)?.isPaper == true
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          height: 1.3,
                                        ),
                                        const quill.VerticalSpacing(16, 8),
                                        const quill.VerticalSpacing(0, 0),
                                        null,
                                      ),
                                      paragraph: quill.DefaultTextBlockStyle(
                                        TextStyle(
                                          color: widget.backgroundId != null && BackgroundAssets.findById(widget.backgroundId!)?.isPaper == true
                                              ? Colors.black
                                              : Colors.white.withOpacity(0.9),
                                          fontSize: 17,
                                          height: 1.7,
                                        ),
                                        const quill.VerticalSpacing(0, 0),
                                        const quill.VerticalSpacing(0, 0),
                                        null,
                                      ),
                                      placeHolder: quill.DefaultTextBlockStyle(
                                        TextStyle(
                                          color: widget.backgroundId != null && BackgroundAssets.findById(widget.backgroundId!)?.isPaper == true
                                              ? Colors.black.withOpacity(0.3)
                                              : Colors.white.withOpacity(0.25),
                                          fontSize: 17,
                                        ),
                                        const quill.VerticalSpacing(0, 0),
                                        const quill.VerticalSpacing(0, 0),
                                        null,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ═══════════════════════════════════════════
                // LETTERLY-STYLE BOTTOM BAR
                // ═══════════════════════════════════════════
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D1A),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        // Add content button (left)
                        if (widget.showTopToolbar && !widget.readOnly)
                          _BottomBarIcon(
                            icon: Icons.add,
                            color: Colors.white54,
                            onTap: _showAddContentMenu,
                          ),
                        if (widget.showTopToolbar && !widget.readOnly)
                          const SizedBox(width: 8),

                        // Pin button
                        if (widget.showTopToolbar && !widget.readOnly)
                          _BottomBarIcon(
                            icon: _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            color: _isPinned ? const Color(0xFFF59E0B) : Colors.white54,
                            onTap: _togglePin,
                          ),

                        const Spacer(),

                        // ✨ REWRITE BUTTON (center, hero) ✨
                        if (!widget.readOnly)
                          GestureDetector(
                            onTap: _showAIMenu,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF5F0),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, size: 18, color: Color(0xFF1A1A2E)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Rewrite',
                                    style: TextStyle(
                                      color: Color(0xFF1A1A2E),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        const Spacer(),

                        // Background picker
                        if (widget.showTopToolbar && !widget.readOnly)
                          _BottomBarIcon(
                            icon: Icons.palette_outlined,
                            color: Colors.white54,
                            onTap: _showBackgroundPicker,
                          ),
                        if (widget.showTopToolbar && !widget.readOnly)
                          const SizedBox(width: 8),

                        // Copy button — same size as other bottom bar icons
                        if (!widget.readOnly)
                          _InlineCopyButton(onCopy: _copyDocumentToClipboard),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // AI selection indicator - subtle hint when text selected
            if (_hasSelection)
              Positioned(
                right: 16,
                bottom: 110,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Tap Rewrite',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ),

            // First-open bubble — styled like home welcome, one-time only.
            // Sits directly above Rewrite (just a tiny lift off the bar).
            if (_showFirstOpenBubble && !widget.readOnly)
              Positioned(
                left: 32,
                right: 32,
                bottom: 85,
                child: _FirstOpenBubble(onDismiss: _dismissFirstOpenBubble),
              ),

            // Continue recording — SAME size as copy (40x40), aligned directly above it
            if (!widget.readOnly && widget.onContinuePressed != null)
              Positioned(
                right: 12,
                bottom: 70,
                child: GestureDetector(
                  onTap: widget.onContinuePressed,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
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

  /// Copy the current plain-text of the editor to the clipboard.
  Future<void> _copyDocumentToClipboard() async {
    final text = _controller.document.toPlainText().trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}

/// Small copy button for the bottom bar — same 40x40 footprint as other
/// bottom bar icons so the row stays uniform. Shows a brief green check
/// when tapped, then reverts.
/// First-open editor bubble. Shows ONCE, ever, above the bottom bar.
/// Styled to match the home "Hi there / Let's make the first recording"
/// welcome — same fonts, same purple, same weights. Arrow points down.
class _FirstOpenBubble extends StatefulWidget {
  final VoidCallback onDismiss;
  const _FirstOpenBubble({required this.onDismiss});

  @override
  State<_FirstOpenBubble> createState() => _FirstOpenBubbleState();
}

class _FirstOpenBubbleState extends State<_FirstOpenBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: widget.onDismiss,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF7C6AE8).withOpacity(0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C6AE8).withOpacity(0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'More magic? ✨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'Tap Rewrite to transform',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C6AE8),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineCopyButton extends StatefulWidget {
  final Future<void> Function() onCopy;
  const _InlineCopyButton({required this.onCopy});

  @override
  State<_InlineCopyButton> createState() => _InlineCopyButtonState();
}

class _InlineCopyButtonState extends State<_InlineCopyButton> {
  bool _copied = false;

  Future<void> _handleTap() async {
    await widget.onCopy();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _copied
              ? const Color(0xFF10B981).withOpacity(0.2)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          color: _copied ? const Color(0xFF10B981) : Colors.white54,
          size: 20,
        ),
      ),
    );
  }
}

/// Floating copy button (legacy — no longer used, kept if reintroduced).
class _CopyButton extends StatefulWidget {
  final Future<void> Function() onCopy;
  const _CopyButton({required this.onCopy});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _handleTap() async {
    await widget.onCopy();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _copied
              ? const Color(0xFF10B981)
              : const Color(0xFF1A1A2E),
          shape: BoxShape.circle,
          border: Border.all(
            color: _copied
                ? const Color(0xFF10B981)
                : Colors.white.withOpacity(0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

// ============================================================
// BOTTOM BAR ICON WIDGET
// ============================================================

class _BottomBarIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BottomBarIcon({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

// ============================================================
// REWRITE PRESET SHEET — Full AI presets (Letterly-style)
// ============================================================

class _RewritePresetSheet extends StatefulWidget {
  final String textToRewrite;
  final Function(String) onResult;
  final AppStateProvider appState;

  const _RewritePresetSheet({
    required this.textToRewrite,
    required this.onResult,
    required this.appState,
  });

  @override
  State<_RewritePresetSheet> createState() => _RewritePresetSheetState();
}

class _RewritePresetSheetState extends State<_RewritePresetSheet> {
  bool _loading = false;
  String? _activePresetId;
  final PresetFavoritesService _favoritesService = PresetFavoritesService();
  Set<String> _favoriteIds = {};

  // Inline instruction recording state (stays on the sheet)
  final AudioRecorder _instructionRecorder = AudioRecorder();
  bool _isRecordingInstruction = false;
  String? _instructionRecordingPath;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _instructionRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final favorites = await _favoritesService.getFavorites();
    if (mounted) {
      setState(() => _favoriteIds = favorites.toSet());
    }
  }

  Future<void> _toggleFavorite(String presetId) async {
    HapticFeedback.lightImpact();
    await _favoritesService.toggleFavorite(presetId);
    await _loadFavorites();
  }

  /// INLINE recording — stays on the sheet, uses OLD backend effect:
  /// combined prompt + master-prompt wrapper via RefinementService.customRefine.
  Future<void> _handleInstructionsTap() async {
    if (_loading) return;

    if (_isRecordingInstruction) {
      // STOP — transcribe + fire old flow
      _recordingTimer?.cancel();
      setState(() => _isRecordingInstruction = false);
      try {
        final path = await _instructionRecorder.stop();
        if (path == null) return;
        final file = File(path);
        if (!await file.exists()) return;

        setState(() {
          _loading = true;
          _activePresetId = '_custom';
        });

        final aiService = AIService();
        final instruction = await aiService.transcribeAudio(file);
        if (instruction.trim().isEmpty) {
          if (mounted) setState(() => _loading = false);
          return;
        }

        // OLD BEAST PATTERN from result_screen.dart _addMoreAndRewrite
        final refinementService = RefinementService();
        final combinedPrompt = '${widget.textToRewrite}\n\n[User adds: $instruction]';
        final refined = await refinementService.customRefine(
          combinedPrompt,
          "Rewrite the entire text incorporating the user's addition or instruction. Maintain the original style unless the user asks to change it.",
        );

        widget.onResult(refined);
      } catch (e) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Instructions failed: $e'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    } else {
      // START recording inline
      try {
        if (!await _instructionRecorder.hasPermission()) return;
        final dir = await getTemporaryDirectory();
        _instructionRecordingPath =
            '${dir.path}/instruction_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _instructionRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _instructionRecordingPath!,
        );
        HapticFeedback.mediumImpact();
        setState(() {
          _isRecordingInstruction = true;
          _recordingSeconds = 0;
        });
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _recordingSeconds++);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mic permission needed: $e'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    }
  }

  String _formatRecordingTime() {
    final m = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _handlePresetTap(Preset preset) async {
    if (_loading) return;

    // Use same gate as recording — 10 min free, then upgrade
    final canUse = await FeatureGate.canUseSTT(context);
    if (!canUse) return;

    setState(() {
      _loading = true;
      _activePresetId = preset.id;
    });

    try {
      final aiService = AIService();
      // Read language FRESH at AI-call time — exact pattern from the old
      // ResultScreen._generateRewrite() that worked reliably.
      final language = widget.appState.selectedLanguage;
      debugPrint('🎨 Rewriting with preset=${preset.id} language=${language.code} (${language.name})');
      final result = await aiService.rewriteText(
        widget.textToRewrite,
        preset,
        language.code,
      );
      widget.onResult(result);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rewrite failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = AppPresets.categories;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Rewrite with AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(color: Color(0xFF1A1A1A), height: 1),

            // Custom instruction input — type or tap mic, stays in place
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _buildInstructionInput(),
            ),

            // "Or choose an AI preset" divider label
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'Or choose an AI preset',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ],
              ),
            ),

            // Preset list
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Favorites section at top (if any)
                    if (_favoriteIds.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'FAVORITES',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...AppPresets.allPresets
                          .where((p) => _favoriteIds.contains(p.id))
                          .map((preset) => _buildPresetRow(preset)),
                      const SizedBox(height: 12),
                    ],

                    // All categories (non-favorites hidden from their group since they're at top)
                    ...categories.map((category) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (category.name.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                              child: Text(
                                category.name.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ...category.presets.map((preset) => _buildPresetRow(preset)),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Slim voice-only instruction button — sits at the top of the sheet.
  /// Same visual weight as the preset rows below (no big purple card).
  /// Idle: small purple mic + "Give AI Instructions" / "Say it out loud"
  /// Recording: red stop + "Listening..." + live timer
  /// Loading: spinner + "Rewriting..."
  Widget _buildInstructionInput() {
    final isRecording = _isRecordingInstruction;
    final isRunning = _loading && _activePresetId == '_custom';

    const purple = Color(0xFF7C6AE8);
    final Color accent = isRecording ? const Color(0xFFEF4444) : purple;
    final String label = isRunning
        ? 'Rewriting...'
        : isRecording
            ? 'Listening... tap to stop'
            : 'Give AI Custom Instruction';

    return GestureDetector(
      onTap: isRunning ? null : _handleInstructionsTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
              child: isRunning
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isRecording)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatRecordingTime(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetRow(Preset preset) {
    final isActive = _activePresetId == preset.id;
    final isFav = _favoriteIds.contains(preset.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive
            ? (preset.color ?? const Color(0xFF8B5CF6)).withOpacity(0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _loading ? null : () => _handlePresetTap(preset),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (preset.color ?? const Color(0xFF8B5CF6)).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: isActive && _loading
                          ? Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: preset.color ?? const Color(0xFF8B5CF6),
                                ),
                              ),
                            )
                          : Icon(
                              preset.icon,
                              color: preset.color ?? const Color(0xFF8B5CF6),
                              size: 18,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            preset.description,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Star button
          GestureDetector(
            onTap: () => _toggleFavorite(preset.id),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFav ? const Color(0xFFFFD700) : Colors.white.withOpacity(0.3),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

