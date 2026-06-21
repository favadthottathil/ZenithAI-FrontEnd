import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls Android's FLAG_SECURE — when enabled, the OS blocks screenshots and
/// blanks the app's preview in the recent-apps switcher, keeping chat content
/// private. The user's choice is persisted and re-applied on every launch.
///
/// Android is the supported platform; calls are no-ops elsewhere (iOS true
/// screenshot blocking isn't possible and is tracked as a follow-up).
class ScreenSecurity {
  ScreenSecurity._();

  static final ScreenSecurity instance = ScreenSecurity._();

  static const MethodChannel _channel = MethodChannel('app/screen_security');
  static const String _prefKey = 'screen_security_enabled';

  /// Default ON: chats are hidden from screenshots/app-switcher unless the user
  /// opts out.
  static const bool _defaultEnabled = true;

  bool _enabled = _defaultEnabled;
  bool get isEnabled => _enabled;

  /// Reads the saved preference and applies it to the native window. Call once
  /// during startup.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? _defaultEnabled;
    await _apply(_enabled);
  }

  /// Persists and applies a new value.
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
    await _apply(enabled);
  }

  Future<void> _apply(bool enabled) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', enabled);
    } on PlatformException {
      // Platform side unavailable — leave the OS default in place.
    } on MissingPluginException {
      // Channel not registered (e.g. unit tests) — ignore.
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
