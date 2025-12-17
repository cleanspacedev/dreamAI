import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls the app ThemeMode with persistence. Defaults to system.
class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'app_theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  ThemeService() {
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        _mode = _fromString(saved);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('ThemeService init error: $e');
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _mode.name);
    } catch (e) {
      debugPrint('ThemeService persist error: $e');
    }
    notifyListeners();
  }

  ThemeMode _fromString(String name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
