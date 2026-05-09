import 'package:flutter/services.dart';

/// Bridge to the native `VoiceBubbleA11yService` — lets Flutter ask the
/// AccessibilityService to drop AI-rewritten text into whatever editable
/// field the user is currently focused on, anywhere on the device.
///
/// Use [injectText] for the happy path. It returns `false` when:
///   • the user hasn't enabled the accessibility permission yet, OR
///   • there's no editable text field currently focused on screen.
/// Callers should fall back to the system clipboard in that case.
class TextInjectionService {
  static const _channel = MethodChannel('voicebubble/overlay');

  /// True if the user has flipped on the accessibility toggle for this app.
  static Future<bool> isEnabled() async {
    final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
    return result ?? false;
  }

  /// Deep-link into the system Accessibility settings so the user can
  /// enable VoiceBubble's service. Returns immediately; pair with
  /// [isEnabled] on app resume to detect when they've granted it.
  static Future<void> openSettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  /// Inject [text] at the current cursor in the focused editable field.
  /// Returns `true` on success. On `false`, fall back to clipboard.
  static Future<bool> injectText(String text) async {
    if (text.isEmpty) return false;
    final result = await _channel.invokeMethod<bool>(
      'injectText',
      <String, dynamic>{'text': text},
    );
    return result ?? false;
  }

  /// Package name of the foreground app, e.g. `com.whatsapp`. Useful for
  /// preset auto-selection (e.g. show "Reply" when in WhatsApp/Messages,
  /// "Email" when in Gmail). Returns `null` if the accessibility service
  /// hasn't observed any window changes yet.
  static Future<String?> getFocusedAppPackage() async {
    return _channel.invokeMethod<String?>('getFocusedAppPackage');
  }
}
