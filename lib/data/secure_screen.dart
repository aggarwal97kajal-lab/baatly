import 'package:no_screenshot/no_screenshot.dart';

import 'app_state.dart';

/// Blocks screenshots / screen recording (Android FLAG_SECURE) while a
/// protected screen is open: view-once media, locked chats, or everywhere
/// when "All chats" is on. Blocked screens also show black in recent apps.
class SecureScreen {
  SecureScreen._();
  static int _holds = 0;
  static bool? _applied;

  static Future<void> _apply() async {
    final want = _holds > 0 || AppState.instance.shotBlockAll;
    if (_applied == want) return;
    _applied = want;
    try {
      if (want) {
        await NoScreenshot.instance.screenshotOff();
      } else {
        await NoScreenshot.instance.screenshotOn();
      }
    } catch (_) {}
  }

  /// Call on app start and after the setting changes.
  static Future<void> refresh() => _apply();

  static Future<void> hold() {
    _holds++;
    return _apply();
  }

  static Future<void> release() {
    if (_holds > 0) _holds--;
    return _apply();
  }
}
