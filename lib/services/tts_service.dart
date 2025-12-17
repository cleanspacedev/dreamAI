import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Simple wrapper around FlutterTts with sane defaults.
class TTSService {
  TTSService._();
  static final TTSService instance = TTSService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _initialized = true;
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  Future<void> setLanguage(String langCode) async {
    await _ensureInit();
    try {
      await _tts.setLanguage(langCode);
    } catch (e) {
      debugPrint('TTS setLanguage error: $e');
    }
  }

  Future<void> speak(String text) async {
    await _ensureInit();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
  }
}
