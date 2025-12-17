import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts/flutter_tts.dart';

/// Manages the current app language/locale.
/// - Detects device locale on first run
/// - Persists user selection in SharedPreferences
/// - Coordinates with TTS for correct language voice
class LanguageService extends ChangeNotifier {
  static const _prefsKey = 'app_language_code';

  LanguageService() {
    _init();
  }

  final FlutterTts _tts = FlutterTts();

  String _languageCode = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.isNotEmpty) {
        _languageCode = saved;
      } else {
        // Normalize unsupported or overly specific codes
        final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
        _languageCode = _normalizeLang(device);
      }
      // Best-effort TTS alignment
      try {
        await _tts.setLanguage(_ttsLangFor(_languageCode));
      } catch (e) {
        debugPrint('TTS setLanguage init error: $e');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('LanguageService init error: $e');
    }
  }

  /// Change app language, persist and notify listeners.
  Future<void> setLanguage(String code) async {
    final normalized = _normalizeLang(code);
    if (normalized == _languageCode) return;
    _languageCode = normalized;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _languageCode);
    } catch (e) {
      debugPrint('Persist language error: $e');
    }
    try {
      await _tts.setLanguage(_ttsLangFor(_languageCode));
    } catch (e) {
      debugPrint('TTS setLanguage error: $e');
    }
    notifyListeners();
  }

  /// Map simple codes to TTS-friendly locale identifiers when needed.
  String _ttsLangFor(String code) {
    switch (code) {
      case 'zh':
        return 'zh-CN';
      case 'pt':
        return 'pt-PT';
      case 'he':
        return 'he-IL';
      case 'ar':
        return 'ar-SA';
      case 'fa':
        return 'fa-IR';
      case 'ur':
        return 'ur-PK';
      default:
        return code; // e.g., 'en', 'es', 'fr'
    }
  }

  String _normalizeLang(String code) {
    final lc = code.toLowerCase();
    // Reduce region-specific codes to base language
    if (lc.contains('-')) return lc.split('-').first;
    if (lc.contains('_')) return lc.split('_').first;
    return lc;
  }
}
