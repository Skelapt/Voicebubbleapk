import 'package:hive/hive.dart';
import 'outcome_type.dart';

part 'recording_item.g.dart';

@HiveType(typeId: 1)
class RecordingItem {
  @HiveField(0)
  String id;

  @HiveField(1)
  String rawTranscript;

  @HiveField(2)
  String finalText; // User editable

  @HiveField(3)
  String presetUsed; // Display name

  @HiveField(4)
  List<String> outcomes; // Store as strings for Hive

  @HiveField(5)
  String? projectId;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  List<String> editHistory; // Track refinements

  @HiveField(8)
  String presetId; // For backend API

  @HiveField(9)
  String? continuedFromId; // Link to previous item in continuation chain

  @HiveField(10)
  List<String> continuedInIds; // Items that built on this one
  
  @HiveField(11)
  bool hiddenInLibrary; // Hidden from library view
  
  @HiveField(12)
  bool hiddenInOutcomes; // Hidden from outcomes view
  
  @HiveField(13)
  bool isCompleted; // For tasks - whether they're completed
  
  @HiveField(14)
  List<String> tags; // List of tag IDs
  
  @HiveField(15)
  DateTime? reminderDateTime; // When to trigger notification
  
  @HiveField(16)
  int? reminderNotificationId; // Store notification ID for cancellation
  
  @HiveField(17)
  String? formattedContent; // Quill Delta JSON for rich text editing
  
  @HiveField(18)
  String? customTitle; // User-defined custom title
  
  @HiveField(19)
  String contentType; // 'voice', 'text', 'image', etc.
  
  @HiveField(20)
  String? background; // Background ID (e.g., 'color_lavender', 'gradient_sunset', 'mountain')
  
  @HiveField(21)
  bool isPinned; // Whether the item is pinned to top

  RecordingItem({
    required this.id,
    required this.rawTranscript,
    required this.finalText,
    required this.presetUsed,
    required this.outcomes,
    this.projectId,
    required this.createdAt,
    required this.editHistory,
    required this.presetId,
    this.continuedFromId,
    List<String>? continuedInIds,
    this.hiddenInLibrary = false,
    this.hiddenInOutcomes = false,
    this.isCompleted = false,
    List<String>? tags,
    this.reminderDateTime,
    this.reminderNotificationId,
    this.formattedContent,
    this.customTitle,
    this.contentType = 'voice', // Default to voice for backward compatibility
    this.background, // Optional background
    this.isPinned = false, // Default to not pinned
  }) : continuedInIds = continuedInIds ?? [],
       tags = tags ?? [];

  // Helper getter to convert string outcomes to enum list
  List<OutcomeType> get outcomeTypes {
    return outcomes
        .map((s) => OutcomeTypeExtension.fromString(s))
        .toList();
  }

  // Helper setter to convert enum list to string list
  set outcomeTypes(List<OutcomeType> types) {
    outcomes = types.map((t) => t.toStorageString()).toList();
  }

  // Formatted date helper (matching ArchivedItem)
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays == 0) {
      return 'Today, ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  RecordingItem copyWith({
    String? id,
    String? rawTranscript,
    String? finalText,
    String? presetUsed,
    List<String>? outcomes,
    String? projectId,
    DateTime? createdAt,
    List<String>? editHistory,
    String? presetId,
    String? continuedFromId,
    List<String>? continuedInIds,
    bool? hiddenInLibrary,
    bool? hiddenInOutcomes,
    bool? isCompleted,
    List<String>? tags,
    DateTime? reminderDateTime,
    int? reminderNotificationId,
    String? formattedContent,
    String? customTitle,
    String? contentType,
    String? background,
    bool? isPinned,
    bool clearReminder = false, // Flag to explicitly clear reminder
    bool clearBackground = false, // Flag to explicitly clear background
    bool clearFormattedContent = false, // Flag to force editor reload from plain text
  }) {
    return RecordingItem(
      id: id ?? this.id,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      finalText: finalText ?? this.finalText,
      presetUsed: presetUsed ?? this.presetUsed,
      outcomes: outcomes ?? List.from(this.outcomes),
      projectId: projectId ?? this.projectId,
      createdAt: createdAt ?? this.createdAt,
      editHistory: editHistory ?? List.from(this.editHistory),
      presetId: presetId ?? this.presetId,
      continuedFromId: continuedFromId ?? this.continuedFromId,
      continuedInIds: continuedInIds ?? List.from(this.continuedInIds),
      hiddenInLibrary: hiddenInLibrary ?? this.hiddenInLibrary,
      hiddenInOutcomes: hiddenInOutcomes ?? this.hiddenInOutcomes,
      isCompleted: isCompleted ?? this.isCompleted,
      tags: tags ?? List.from(this.tags),
      reminderDateTime: clearReminder ? null : (reminderDateTime ?? this.reminderDateTime),
      reminderNotificationId: clearReminder ? null : (reminderNotificationId ?? this.reminderNotificationId),
      formattedContent: clearFormattedContent ? null : (formattedContent ?? this.formattedContent),
      customTitle: customTitle ?? this.customTitle,
      contentType: contentType ?? this.contentType,
      background: clearBackground ? null : (background ?? this.background),
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
