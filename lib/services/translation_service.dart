import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dreamweaver/openai/openai_config.dart' as openai;
import 'package:dreamweaver/services/language_service.dart';

/// Provides on-the-fly translations of UI strings and content using OpenAI.
/// Caches results in SharedPreferences to minimize API calls.
class TranslationService extends ChangeNotifier {
  final LanguageService languageService;
  TranslationService({required this.languageService});

  static const _cachePrefix = 'txcache_';
  Map<String, String> _cache = {};
  String _cachedLang = 'en';

  String get currentLang => languageService.languageCode;

  Future<void> _ensureLoaded() async {
    final lang = currentLang;
    if (_cachedLang == lang && _cache.isNotEmpty) return;
    _cachedLang = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$lang') ?? '{}';
      try {
        final decoded = json.decode(raw);
        if (decoded is Map) {
          _cache = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        } else {
          _cache = {};
        }
      } catch (e) {
        debugPrint('Translation cache decode error for $lang: $e');
        _cache = {};
        // Sanitize: write clean map back
        await prefs.setString('$_cachePrefix$lang', json.encode({}));
      }
    } catch (e) {
      debugPrint('Load translation cache error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cachePrefix$_cachedLang', json.encode(_cache));
    } catch (e) {
      debugPrint('Persist translation cache error: $e');
    }
  }

  /// Translate any text into the current language.
  /// If current language is English or same as source, returns input.
  Future<String> translate(String text, {String? contextKey}) async {
    final target = currentLang;
    if (target.isEmpty || target == 'en') return text;
    await _ensureLoaded();
    final key = '${target}|${contextKey ?? ''}|$text';
    if (_cache.containsKey(key)) return _cache[key]!;

    // Call OpenAI translation
    String? translated;
    try {
      translated = await openai.openAiTranslate(
        text: text,
        targetLanguage: target,
        context: contextKey,
      );
    } catch (e) {
      debugPrint('OpenAI translate error: $e');
    }
    if (translated == null || translated.trim().isEmpty) return text;
    _cache[key] = translated.trim();
    await _persist();
    return _cache[key]!;
  }
}
