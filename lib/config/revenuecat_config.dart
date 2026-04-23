/// RevenueCat configuration.
///
/// SETUP:
///   1. RevenueCat dashboard → Project settings → API keys.
///   2. Copy the **Public Android SDK key** (starts with `goog_...`).
///   3. Paste it below, replacing PASTE_YOUR_ANDROID_KEY_HERE.
///   4. (iOS, later) Paste the **Public iOS SDK key** (starts with `appl_...`).
///
/// The Pro entitlement identifier MUST match what you configured in the
/// dashboard — the default is `pro` (lowercase).
///
/// Product IDs are NOT duplicated here — RevenueCat reads them from the
/// Products you configure in the dashboard. Keep those IDs matching the
/// constants in SubscriptionService: `voicebubble_pro_monthly` and
/// `voicebubble_pro_yearly`.
class RevenueCatConfig {
  // Temporary project-wide test key (issued by RevenueCat before a platform
  // app was added). Works for SDK wiring / init but will NOT see real Play
  // purchases. Swap for the real Android key (starts with `goog_...`) once
  // the Google Play app is attached in the RevenueCat dashboard.
  static const String androidApiKey = 'test_HMdPlxXKtDhrSHxyKfJnJHcOcqu';
  static const String iosApiKey = 'PASTE_YOUR_IOS_KEY_HERE';

  /// Entitlement identifier in the RevenueCat dashboard. Case-sensitive.
  static const String proEntitlement = 'pro';

  static bool get isConfiguredForAndroid =>
      androidApiKey.isNotEmpty && !androidApiKey.startsWith('PASTE_');
  static bool get isConfiguredForIos =>
      iosApiKey.isNotEmpty && !iosApiKey.startsWith('PASTE_');
}
