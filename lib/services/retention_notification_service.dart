import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'notification_service.dart';
import 'subscription_service.dart';

/// Schedules retention notifications after onboarding.
/// Psychologically optimized timing and copy.
///
/// Scheduled once after onboarding, never again.
/// Cancelled when user becomes a paying subscriber.
class RetentionNotificationService {
  static final RetentionNotificationService _instance =
      RetentionNotificationService._internal();
  factory RetentionNotificationService() => _instance;
  RetentionNotificationService._internal();

  static const String _boxName = 'usage_data';
  static const String _scheduledKey = 'retention_notifications_scheduled';
  static const String _lastOpenKey = 'last_app_open_date';

  // Notification IDs — fixed so we can cancel them
  static const int _id1 = 900001;
  static const int _id2 = 900002;
  static const int _id3 = 900003;
  static const int _id4 = 900004;
  static const int _id5 = 900005;
  static const int _id6 = 900006;
  static const int _id7 = 900007;

  final NotificationService _notificationService = NotificationService();

  /// Record that the user opened the app today.
  /// Call this from SplashScreen or MainNavigation.
  Future<void> recordAppOpen() async {
    final box = await Hive.openBox(_boxName);
    await box.put(_lastOpenKey, DateTime.now().toIso8601String());
  }

  /// Schedule the full retention sequence. Call once after onboarding.
  /// Idempotent — won't schedule twice.
  Future<void> scheduleOnboardingRetention() async {
    final box = await Hive.openBox(_boxName);
    final alreadyScheduled = box.get(_scheduledKey, defaultValue: false);
    if (alreadyScheduled) return;

    final now = DateTime.now();

    // ═══════════════════════════════════════════════════════════
    // THE SEQUENCE — every notification earns its open
    // ═══════════════════════════════════════════════════════════

    // Day 1 — 6pm. The "instant gratification" reminder.
    // They just onboarded. The product is fresh. Remind them
    // of the core promise before bedtime routine sets in.
    await _schedule(
      id: _id1,
      time: _nextOccurrence(now, 1, 18, 0),
      title: 'Got something to say?',
      body: 'Just say it. VoiceBubble writes it for you. \u{1F399}',
    );

    // Day 2 — 8am. Morning productivity window.
    // People think about what they need to do today.
    // Give them a specific use case, not a generic nudge.
    await _schedule(
      id: _id2,
      time: _nextOccurrence(now, 2, 8, 0),
      title: 'Morning thought?',
      body: 'That thing you need to tell someone \u2014 say it in 10 seconds. VoiceBubble makes it perfect.',
    );

    // Day 3 — 9am. The "procrastination killer."
    // By day 3 the novelty has worn off. Attack a real pain point.
    await _schedule(
      id: _id3,
      time: _nextOccurrence(now, 3, 9, 0),
      title: 'That email you\'ve been putting off',
      body: 'Say it in 10 seconds. Done. No typing needed.',
    );

    // Day 5 — 12pm. Lunch break discovery.
    // Introduce a feature they might not have tried yet.
    await _schedule(
      id: _id4,
      time: _nextOccurrence(now, 5, 12, 0),
      title: 'Did you know?',
      body: 'You can record a full meeting and VoiceBubble pulls out every action item automatically. \u{1F4CB}',
    );

    // Day 7 — 6pm. The "feature unlock" moment.
    // One week in. Push the floating bubble — it's the stickiest feature.
    await _schedule(
      id: _id5,
      time: _nextOccurrence(now, 7, 18, 0),
      title: 'One tap away',
      body: 'Turn on the floating bubble. It sits on your screen, ready whenever you are. Never lose a thought again. \u{1F4AC}',
    );

    // Day 10 — 9am. Social proof + FOMO.
    // They're either forming a habit or drifting. Pull them back.
    await _schedule(
      id: _id6,
      time: _nextOccurrence(now, 10, 9, 0),
      title: 'People are saying things',
      body: 'VoiceBubble users save hours every week. Your free minutes are still waiting. \u{23F3}',
    );

    // Day 14 — 10am. The "use it or lose it" close.
    // Two weeks. Final push. Create urgency around free minutes.
    await _schedule(
      id: _id7,
      time: _nextOccurrence(now, 14, 10, 0),
      title: 'Your free minutes are waiting',
      body: 'Open the app. Speak. Done. It takes 10 seconds to see the magic. \u{1F525}',
    );

    await box.put(_scheduledKey, true);
    debugPrint('\u{1F514} Retention notifications scheduled (7 total)');
  }

  /// Cancel all retention notifications.
  /// Call when user subscribes.
  Future<void> cancelAll() async {
    for (final id in [_id1, _id2, _id3, _id4, _id5, _id6, _id7]) {
      await _notificationService.cancelReminder(id);
    }
    debugPrint('\u{1F515} All retention notifications cancelled');
  }

  /// Cancel retention notifications if user is now pro.
  /// Call on app start.
  Future<void> cancelIfSubscribed() async {
    final isPro = await SubscriptionService().isPro();
    if (isPro) {
      await cancelAll();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════

  /// Calculate the DateTime for [daysFromNow] at [hour]:[minute].
  DateTime _nextOccurrence(DateTime from, int daysFromNow, int hour, int minute) {
    final date = DateTime(from.year, from.month, from.day + daysFromNow, hour, minute);
    return date;
  }

  /// Schedule a single notification using the existing NotificationService.
  Future<void> _schedule({
    required int id,
    required DateTime time,
    required String title,
    required String body,
  }) async {
    if (time.isBefore(DateTime.now())) return; // Skip past times

    try {
      await _notificationService.scheduleReminder(
        itemId: 'retention_$id',
        title: title,
        body: body,
        scheduledTime: time,
      );
    } catch (e) {
      debugPrint('\u{26A0}\u{FE0F} Failed to schedule retention notification $id: $e');
    }
  }
}
